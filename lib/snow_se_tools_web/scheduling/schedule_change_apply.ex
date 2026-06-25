defmodule SnowSeToolsWeb.Scheduling.ScheduleChangeApply do
  alias SnowSeTools.Scheduling.ScheduleUtils
  # add pattern matching with structs on args to enforce structure
  def apply_changes(schedule_owner, changes) when is_list(changes) do
    courses = Map.get(schedule_owner, :courses, [])
    applied = apply_to_courses(courses, changes, schedule_owner.type)

    rebuilt =
      ScheduleUtils.build_week_schedule(
        type: schedule_owner.type,
        name: schedule_owner.name,
        courses: applied
      )
      |> Map.merge(%{
        program_name: schedule_owner[:program_name],
        semester_name: schedule_owner[:semester_name]
      })

    %{rebuilt | online_courses: schedule_owner[:online_courses] || []}
  end

  def effective_schedule(schedule_owner, nil), do: schedule_owner

  def effective_schedule(schedule_owner, active_change_group) do
    changes = Map.get(active_change_group, "changes", [])
    apply_changes(schedule_owner, changes)
  end

  # add pattern matching with structs on args to enforce structure
  defp apply_to_courses(courses, changes, owner_type) do
    changes_by_crn = Enum.group_by(changes, & &1["crn"])
    existing_crns = MapSet.new(courses, & &1["crn"])

    updated_courses =
      Enum.flat_map(courses, fn course ->
        case Map.get(changes_by_crn, course["crn"]) do
          nil ->
            [course]

          [%{"course_name" => "__DELETED__"}] ->
            []

          [%{"operation" => "update"} = change] ->
            [apply_change_to_course(course, change)]

          [%{"operation" => "add"}] ->
            [course]
        end
      end)

    new_courses =
      changes
      |> Enum.filter(&(&1["operation"] == "add"))
      |> Enum.map(&change_to_course/1)

    moved_courses = moved_courses_for_owner(changes, existing_crns, owner_type)

    updated_courses ++ new_courses ++ moved_courses
  end

  defp moved_courses_for_owner(_changes, _existing_crns, :academic_program_semester), do: []

  defp moved_courses_for_owner(changes, existing_crns, _owner_type) do
    changes
    |> Enum.filter(&(&1["operation"] == "update"))
    |> Enum.reject(&(&1["course_name"] == "__DELETED__"))
    |> Enum.reject(&MapSet.member?(existing_crns, &1["crn"]))
    |> Enum.map(&change_to_course/1)
  end

  # add pattern matching with structs on args to enforce structure
  defp apply_change_to_course(course, change) do
    course
    |> Map.put("crn", change["crn"])
    |> Map.put("name", change["course_name"] || course["name"])
    |> Map.put(
      "instructors",
      case change["target_professor"] do
        nil -> course["instructors"]
        prof -> [%{"name" => prof, "primary_instructor" => true}]
      end
    )
    |> Map.put("meet_info", change["meet_info"] || course["meet_info"])
    |> Map.put("__source", :updated)
  end

  # add pattern matching with structs on args to enforce structure
  defp change_to_course(change) do
    %{
      "crn" => change["crn"],
      "name" => change["course_name"] || "",
      "subject_code" => "",
      "course_number" => "",
      "section_number" => "",
      "credit_hours" => 0,
      "instructors" =>
        case change["target_professor"] do
          nil -> []
          prof -> [%{"name" => prof, "primary_instructor" => true}]
        end,
      "meet_info" => change["meet_info"],
      "__source" => :added
    }
  end
end
