defmodule SnowSeTools.Scheduling.ScheduleChange do
  @moduledoc """
  What a course looks like once a change group's changes are applied to it.

  This used to exist twice — once in the conflict detector and once in the web
  layer — and the copies had drifted: they disagreed about whether a blank
  `target_professor` wipes the instructors or leaves them alone, about which
  identity fields a change may rewrite, and about what two changes for one CRN
  mean (one silently kept the last, the other raised). What the schedule shows
  and what conflict detection computes must never be able to disagree, so both
  now call this.

  `"__source"` records where a course came from — `:base`, `:updated` or
  `:added` — which the week grid colors by and everything else ignores.
  """

  alias SnowSeTools.Data.Text

  @deleted_marker "__DELETED__"

  def deleted_marker, do: @deleted_marker

  @doc """
  Applies `changes` to `courses`: updates in place, drops deletions, and
  materializes courses the changes add. Courses a change moves in from
  somewhere else are not included — see `moved_courses/2`.
  """
  def apply_changes(courses: courses, changes: changes)
      when is_list(courses) and is_list(changes) do
    changes_by_crn = changes_by_crn(changes)

    updated =
      Enum.flat_map(courses, fn course ->
        case Map.get(changes_by_crn, course["crn"]) do
          nil -> [course]
          change -> apply_to_course(course, change)
        end
      end)

    updated ++ added_courses(courses: courses, changes: changes)
  end

  @doc """
  Courses that changes bring into this set from elsewhere — a course moved into
  a room or handed to a professor who did not have it. Callers filter the
  result down to the owner they are drawing.
  """
  def moved_courses(courses: courses, changes: changes) do
    existing_crns = MapSet.new(courses, & &1["crn"])

    changes
    |> Enum.filter(&(&1["operation"] == "update"))
    |> Enum.reject(&deleted?/1)
    |> Enum.reject(&MapSet.member?(existing_crns, &1["crn"]))
    # New to whichever card is drawing it, however the change is labelled.
    |> Enum.map(&course_from_change(&1, :added))
  end

  @doc "One course with one change applied: `[]` when the change deletes it."
  def apply_to_course(course, change) do
    cond do
      deleted?(change) -> []
      # An "add" for a CRN already on hand leaves the existing course alone.
      change["operation"] == "add" -> [course]
      true -> [updated_course(course, change)]
    end
  end

  defp updated_course(course, change) do
    course
    |> Map.put("name", change["course_name"] || course["name"])
    |> Map.put("subject_code", change["subject_code"] || course["subject_code"])
    |> Map.put("course_number", change["course_number"] || course["course_number"])
    |> Map.put("instructors", instructors(change, course))
    |> Map.put("meet_info", change["meet_info"] || course["meet_info"])
    |> Map.put("__source", :updated)
  end

  @doc "A course built out of a change alone, for a CRN not already on hand."
  def course_from_change(change, source \\ nil)

  def course_from_change(%{"crn" => crn} = change, source) do
    %{
      "crn" => crn,
      "term_code" => change["term"],
      "name" => change["course_name"] || "",
      "subject_code" => change["subject_code"] || "",
      "course_number" => change["course_number"] || "",
      "section_number" => "",
      "credit_hours" => 0,
      "instructors" => instructors(change, %{}),
      "meet_info" => change["meet_info"] || [],
      "__source" => source || source_for(change)
    }
  end

  def deleted?(change), do: change["course_name"] == @deleted_marker

  # Two changes for one CRN mean the later one wins. Neither reading of that was
  # written down before: one copy silently kept the last, the other raised.
  defp changes_by_crn(changes) do
    Enum.reduce(changes, %{}, fn change, acc -> Map.put(acc, change["crn"], change) end)
  end

  defp added_courses(courses: courses, changes: changes) do
    existing_crns = MapSet.new(courses, & &1["crn"])

    changes
    |> Enum.filter(&(&1["operation"] == "add"))
    |> Enum.reject(&MapSet.member?(existing_crns, &1["crn"]))
    |> Enum.map(&course_from_change/1)
  end

  # A blank professor means the change says nothing about who teaches this, not
  # that nobody does.
  defp instructors(%{"target_professor" => professor}, course) do
    if Text.blank?(professor) do
      Map.get(course, "instructors", [])
    else
      [%{"name" => professor, "primary_instructor" => true}]
    end
  end

  defp instructors(_change, course), do: Map.get(course, "instructors", [])

  defp source_for(%{"operation" => "add"}), do: :added
  defp source_for(_change), do: :updated
end
