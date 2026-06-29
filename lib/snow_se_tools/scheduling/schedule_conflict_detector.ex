defmodule SnowSeTools.Scheduling.ScheduleConflictDetector do
  alias SnowSeTools.Scheduling.ScheduleUtils

  def detect_term_conflicts(
        owner_course_lists: owner_course_lists,
        active_changes: active_changes
      )
      when is_list(owner_course_lists) and is_list(active_changes) do
    owner_keys_by_crn = owner_keys_by_crn(owner_course_lists)
    base_courses = unique_courses(owner_course_lists)
    effective_courses = apply_changes(courses: base_courses, changes: active_changes)
    change_ids_by_crn = change_ids_by_crn(active_changes)
    entries = meeting_entries(courses: effective_courses, owner_keys_by_crn: owner_keys_by_crn)

    all_conflicts =
      entries
      |> conflict_pairs()
      |> Enum.flat_map(fn {left, right} ->
        room_conflicts(left: left, right: right) ++
          professor_conflicts(left: left, right: right)
      end)
      |> Enum.map(&attach_change_ids(&1, change_ids_by_crn))
      |> Enum.uniq_by(&conflict_key/1)

    %{
      all_conflicts: all_conflicts,
      conflicts_by_change_id: conflicts_by_change_id(all_conflicts),
      conflicts_by_owner_key: conflicts_by_owner_key(all_conflicts),
      conflicts_by_crn: conflicts_by_crn(all_conflicts)
    }
  end

  defp unique_courses(owner_course_lists) do
    owner_course_lists
    |> Enum.flat_map(&courses_for_owner/1)
    |> Enum.uniq_by(& &1["crn"])
  end

  defp courses_for_owner(%{courses: courses}) when is_list(courses), do: courses
  defp courses_for_owner(%{"courses" => courses}) when is_list(courses), do: courses
  defp courses_for_owner(_owner), do: []

  defp owner_keys_by_crn(owner_course_lists) do
    Enum.reduce(owner_course_lists, %{}, fn owner, acc ->
      owner_key = owner_key(owner)

      owner
      |> courses_for_owner()
      |> Enum.reduce(acc, fn course, owner_acc ->
        Map.update(owner_acc, course["crn"], MapSet.new([owner_key]), &MapSet.put(&1, owner_key))
      end)
    end)
  end

  defp owner_key(%{owner_key: owner_key}), do: owner_key
  defp owner_key(%{"owner_key" => owner_key}), do: owner_key

  defp apply_changes(courses: courses, changes: changes) do
    changes_by_crn = Map.new(changes, &{&1["crn"], &1})
    existing_crns = MapSet.new(courses, & &1["crn"])

    updated_courses =
      courses
      |> Enum.flat_map(fn course ->
        case Map.get(changes_by_crn, course["crn"]) do
          nil ->
            [course]

          %{"course_name" => "__DELETED__"} ->
            []

          %{"operation" => "update"} = change ->
            [apply_change_to_course(course: course, change: change)]

          %{"operation" => "add"} ->
            [course]
        end
      end)

    added_courses =
      changes
      |> Enum.filter(&(&1["operation"] == "add"))
      |> Enum.reject(&MapSet.member?(existing_crns, &1["crn"]))
      |> Enum.map(&change_to_course/1)

    updated_courses ++ added_courses
  end

  defp apply_change_to_course(course: course, change: change) do
    course
    |> Map.put("name", change["course_name"] || course["name"])
    |> Map.put("subject_code", change["subject_code"] || course["subject_code"])
    |> Map.put("course_number", change["course_number"] || course["course_number"])
    |> Map.put("instructors", changed_instructors(change, course))
    |> Map.put("meet_info", change["meet_info"] || course["meet_info"])
  end

  defp changed_instructors(%{"target_professor" => professor}, _course)
       when is_binary(professor) and professor != "" do
    [%{"name" => professor, "primary_instructor" => true}]
  end

  defp changed_instructors(_change, course), do: course["instructors"] || []

  defp change_to_course(change) do
    %{
      "crn" => change["crn"],
      "term_code" => change["term"],
      "subject_code" => change["subject_code"],
      "course_number" => change["course_number"],
      "section_number" => "",
      "name" => change["course_name"] || "",
      "credit_hours" => 0,
      "instructors" => changed_instructors(change, %{}),
      "meet_info" => change["meet_info"] || []
    }
  end

  defp change_ids_by_crn(changes) do
    changes
    |> Enum.filter(&(is_binary(&1["id"]) and is_binary(&1["crn"])))
    |> Map.new(&{&1["crn"], &1["id"]})
  end

  defp meeting_entries(courses: courses, owner_keys_by_crn: owner_keys_by_crn) do
    Enum.flat_map(courses, fn course ->
      course_owner_keys =
        owner_keys_for_course(course: course, owner_keys_by_crn: owner_keys_by_crn)

      course
      |> Map.get("meet_info", [])
      |> Enum.map(fn meeting ->
        room = ScheduleUtils.room_name(meeting: meeting)
        instructors = instructor_names(course)

        %{
          crn: course["crn"],
          course_name: course["name"],
          subject_code: course["subject_code"],
          course_number: course["course_number"],
          room: room,
          instructors: instructors,
          meeting: meeting,
          owner_keys:
            course_owner_keys
            |> MapSet.union(derived_owner_keys(room: room, instructors: instructors))
        }
      end)
    end)
  end

  defp owner_keys_for_course(course: course, owner_keys_by_crn: owner_keys_by_crn) do
    Map.get(owner_keys_by_crn, course["crn"], MapSet.new())
  end

  defp derived_owner_keys(room: room, instructors: instructors) do
    room_keys =
      if blank?(room), do: [], else: ["room:#{room}"]

    professor_keys =
      instructors
      |> Enum.reject(&blank?/1)
      |> Enum.map(&"professor:#{&1}")

    MapSet.new(room_keys ++ professor_keys)
  end

  defp instructor_names(course) do
    course
    |> Map.get("instructors", [])
    |> Enum.map(fn
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _other -> nil
    end)
    |> Enum.reject(&blank?/1)
  end

  defp conflict_pairs(entries) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {left, index} ->
      entries
      |> Enum.drop(index + 1)
      |> Enum.reject(&(&1.crn == left.crn))
      |> Enum.filter(&meetings_overlap?(left.meeting, &1.meeting))
      |> Enum.map(&{left, &1})
    end)
  end

  defp room_conflicts(left: %{room: room} = left, right: %{room: room} = right)
       when is_binary(room) and room != "" do
    [
      base_conflict(
        type: :room,
        owner_keys: MapSet.union(left.owner_keys, right.owner_keys) |> MapSet.put("room:#{room}"),
        left: left,
        right: right,
        title: "Room conflict",
        description:
          "#{room} is shared by #{course_label(left)} and #{course_label(right)} #{format_time_range(right.meeting)}"
      )
    ]
  end

  defp room_conflicts(left: _left, right: _right), do: []

  defp professor_conflicts(left: left, right: right) do
    left.instructors
    |> MapSet.new()
    |> MapSet.intersection(MapSet.new(right.instructors))
    |> Enum.map(fn professor ->
      base_conflict(
        type: :professor,
        owner_keys:
          MapSet.union(left.owner_keys, right.owner_keys)
          |> MapSet.put("professor:#{professor}"),
        left: left,
        right: right,
        title: "Professor conflict",
        description:
          "#{professor} teaches #{course_label(left)} and #{course_label(right)} #{format_time_range(right.meeting)}"
      )
    end)
  end

  defp base_conflict(
         type: type,
         owner_keys: owner_keys,
         left: left,
         right: right,
         title: title,
         description: description
       ) do
    %{
      type: type,
      title: title,
      description: description,
      owner_keys: MapSet.to_list(owner_keys),
      course_crns: [left.crn, right.crn],
      courses: [course_summary(left), course_summary(right)],
      meeting: right.meeting,
      introduced_by_change_ids: []
    }
  end

  defp course_summary(entry) do
    %{
      crn: entry.crn,
      name: entry.course_name,
      subject_code: entry.subject_code,
      course_number: entry.course_number
    }
  end

  defp attach_change_ids(conflict, change_ids_by_crn) do
    change_ids =
      conflict.course_crns
      |> Enum.map(&Map.get(change_ids_by_crn, &1))
      |> Enum.reject(&is_nil/1)

    %{conflict | introduced_by_change_ids: change_ids}
  end

  defp conflicts_by_change_id(conflicts) do
    conflicts
    |> Enum.flat_map(fn conflict ->
      Enum.map(conflict.introduced_by_change_ids, &{&1, conflict})
    end)
    |> group_conflicts()
  end

  defp conflicts_by_owner_key(conflicts) do
    conflicts
    |> Enum.flat_map(fn conflict ->
      Enum.map(conflict.owner_keys, &{&1, conflict})
    end)
    |> group_conflicts()
  end

  defp conflicts_by_crn(conflicts) do
    conflicts
    |> Enum.flat_map(fn conflict ->
      Enum.map(conflict.course_crns, &{&1, conflict})
    end)
    |> group_conflicts()
  end

  defp group_conflicts(entries) do
    Enum.reduce(entries, %{}, fn {key, conflict}, acc ->
      Map.update(acc, key, [conflict], &[conflict | &1])
    end)
  end

  defp conflict_key(conflict) do
    crns = Enum.sort(conflict.course_crns)
    [conflict.type, crns, conflict.description]
  end

  defp meetings_overlap?(left, right) do
    shares_day?(left["days"] || [], right["days"] || []) and
      time_minutes(left["start_time"]) < time_minutes(right["end_time"]) and
      time_minutes(right["start_time"]) < time_minutes(left["end_time"])
  end

  defp shares_day?(left_days, right_days) do
    !MapSet.disjoint?(MapSet.new(left_days), MapSet.new(right_days))
  end

  defp course_label(entry) do
    [entry.subject_code, entry.course_number, entry.course_name]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp format_time_range(meeting) do
    [normalize_time(meeting["start_time"]), normalize_time(meeting["end_time"])]
    |> Enum.reject(&blank?/1)
    |> Enum.join("-")
  end

  defp normalize_time(time) when is_binary(time) do
    time
    |> String.split(":")
    |> case do
      [hour, minute | _] -> "#{hour}:#{minute}"
      _other -> time
    end
  end

  defp normalize_time(_time), do: nil

  defp time_minutes(time) when is_binary(time) do
    case String.split(time, ":") do
      [hour, minute | _] ->
        with {h, ""} <- Integer.parse(hour),
             {m, ""} <- Integer.parse(minute) do
          h * 60 + m
        else
          _other -> 0
        end

      _other ->
        0
    end
  end

  defp time_minutes(_time), do: 0

  defp blank?(value), do: is_nil(value) or value == ""
end
