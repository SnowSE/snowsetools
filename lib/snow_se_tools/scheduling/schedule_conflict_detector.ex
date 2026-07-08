defmodule SnowSeTools.Scheduling.ScheduleConflictDetector do
  alias SnowSeTools.Scheduling.ScheduleUtils

  # Placeholder professor used by registrar for unassigned courses.
  # Filtered out from professor conflict detection entirely.
  @tba_staff "TBA Staff"

  def detect_term_conflicts(
        owner_course_lists: owner_course_lists,
        active_changes: active_changes
      )
      when is_list(owner_course_lists) and is_list(active_changes) do
    owner_keys_by_crn = owner_keys_by_crn(owner_course_lists)
    owner_targets_by_key = owner_targets_by_key(owner_course_lists)
    base_courses = unique_courses(owner_course_lists)
    effective_courses = apply_changes(courses: base_courses, changes: active_changes)
    change_ids_by_crn = change_ids_by_crn(active_changes)
    entries = meeting_entries(courses: effective_courses, owner_keys_by_crn: owner_keys_by_crn)

    # Resource-first conflict detection: partition by shared resource (room or professor),
    # then find temporal overlaps WITHIN each partition. This prevents "bridge" entries
    # in other rooms from creating false positive conflicts between non-overlapping courses
    # that happen to share a room or professor.
    all_room_conflicts = detect_room_conflicts(entries)
    all_prof_conflicts = detect_professor_conflicts(entries)

    all_conflicts =
      Enum.concat(all_room_conflicts, all_prof_conflicts)
      |> Enum.map(&attach_schedule_targets(&1, owner_targets_by_key))
      |> Enum.map(&attach_change_ids(&1, change_ids_by_crn))
      |> Enum.uniq_by(&conflict_key/1)

    %{
      all_conflicts: all_conflicts,
      conflicts_by_change_id: conflicts_by_change_id(all_conflicts),
      conflicts_by_owner_key: conflicts_by_owner_key(all_conflicts),
      conflicts_by_crn: conflicts_by_crn(all_conflicts)
    }
  end

  # -- Course extraction & owner mapping --

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

  defp owner_targets_by_key(owner_course_lists) do
    Enum.reduce(owner_course_lists, %{}, fn owner, acc ->
      case owner_target(owner) do
        nil -> acc
        target -> Map.put(acc, target.key, target)
      end
    end)
  end

  defp owner_target(%{owner_key: owner_key, type: type} = owner) when is_binary(owner_key) do
    owner_target(owner_key, type, owner)
  end

  defp owner_target(%{"owner_key" => owner_key, "type" => type} = owner)
       when is_binary(owner_key) do
    owner_target(owner_key, type, owner)
  end

  defp owner_target(_owner), do: nil

  defp owner_target(owner_key, :room, _owner), do: room_target(owner_key)
  defp owner_target(owner_key, :professor, _owner), do: professor_target(owner_key)

  defp owner_target(owner_key, :academic_program_semester, owner) do
    case {owner_name(owner), owner_key} do
      {name, key} when is_binary(name) and name != "" ->
        %{kind: :academic_program_semester, key: key, label: name}

      _other ->
        nil
    end
  end

  defp owner_target(_owner_key, _type, _owner), do: nil

  # -- Change application --

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

  defp changed_instructors(_change, course), do: Map.get(course, "instructors", [])

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

  # -- Meeting entry construction --

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
            MapSet.union(
              course_owner_keys,
              derived_owner_keys(room: room, instructors: instructors)
            )
        }
      end)
    end)
  end

  defp owner_keys_for_course(course: course, owner_keys_by_crn: owner_keys_by_crn) do
    Map.get(owner_keys_by_crn, course["crn"], MapSet.new())
  end

  defp derived_owner_keys(room: room, instructors: instructors) do
    room_keys = if blank?(room), do: [], else: ["room:#{room}"]

    professor_keys =
      instructors
      |> Enum.reject(&blank?/1)
      |> Enum.reject(&(&1 == @tba_staff))
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

  # -- Resource-first conflict detection --
  #
  # Partition entries by shared resource FIRST, then find temporal overlaps WITHIN
  # each partition. This prevents "bridge" entries in other rooms from creating false
  # positive conflicts between non-overlapping courses that share a room/professor.
  #
  # Example of the bug this avoids:
  #   Course A (Room X, Mon 9:00-9:50) doesn't overlap with Course B (Room X, Mon 14:00-14:50).
  #   But both overlap temporally with Course C (Room Y, Mon 8:00-16:00).
  #   Old approach: groups {A, B, C} by temporal overlap. Then room_conflicts sees A+B share Room X.
  #   New approach: partitions Room X entries {A, B}. No temporal overlap → no conflict.

  defp detect_room_conflicts(entries) do
    entries
    |> Enum.reject(&blank?(&1.room))
    |> Enum.group_by(& &1.room)
    |> Enum.flat_map(fn {_room, room_entries} ->
      build_conflicts_for_group(room_entries, :room)
    end)
  end

  defp detect_professor_conflicts(entries) do
    professor_to_entries =
      entries
      |> Enum.flat_map(fn entry ->
        entry.instructors
        |> Enum.reject(&(&1 == @tba_staff))
        |> Enum.map(&{&1, entry})
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Enum.flat_map(professor_to_entries, fn {_professor, prof_entries} ->
      # Deduplicate by CRN so a course taught by the same professor twice doesn't self-conflict
      uniq = Enum.uniq_by(prof_entries, & &1.crn)

      if length(uniq) >= 2 do
        build_conflicts_for_group(uniq, :professor)
      else
        []
      end
    end)
  end

  defp build_conflicts_for_group(entries, _type) when length(entries) < 2, do: []

  defp build_conflicts_for_group(entries, type) do
    entries
    |> temporal_overlap_groups()
    # Deduplicate same-course sections and co-taught courses within temporal overlap groups.
    # Two entries are considered duplicates when they share:
    #   - Same subject_code + course_number (same course identity)
    #   - Identical sorted instructor lists (co-teaching exemption)
    #
    # This handles two scenarios:
    #   1. A professor teaching multiple sections of the same course (e.g., MATH 101 Sec 1 + Sec 2)
    #      The first section seen is kept; additional sections with matching code are filtered.
    #   2. Two professors co-teaching the same course (same time, same room, identical instructors).
    #      Both professor and room partitions get this treatment to avoid false conflicts.
    #
    # NOTE: The co-teaching exemption only applies when instructor lists are IDENTICAL.
    # If two courses share subject_code + course_number but have DIFFERENT instructor
    # combinations, they are treated as separate courses and may still conflict.
    |> Enum.map(fn group -> dedup_same_course_sections(group) end)
    |> Enum.filter(&(length(&1) >= 2))
    |> Enum.map(fn group -> build_conflict(group, type) end)
  end

  defp dedup_same_course_sections(entries) do
    {_seen, filtered} =
      Enum.reduce(entries, {%MapSet{}, []}, fn entry, {seen, acc} ->
        course_id = {
          Map.get(entry, :subject_code),
          Map.get(entry, :course_number),
          entry.instructors |> Enum.sort() |> :erlang.term_to_binary()
        }

        if MapSet.member?(seen, course_id) do
          {seen, acc}
        else
          {MapSet.put(seen, course_id), [entry | acc]}
        end
      end)

    Enum.reverse(filtered)
  end

  # -- Union-find temporal overlap grouping (within a resource partition) --

  defp temporal_overlap_groups(entries) do
    indexed = Enum.with_index(entries)
    n = length(indexed)
    parent = Map.new(0..(n - 1), &{&1, &1})

    parent_final =
      for i <- 0..(n - 2), reduce: parent do
        p_acc ->
          left_entry = Enum.at(indexed, i) |> elem(0)
          union_overlapping(p_acc, indexed, i, i + 1, n, left_entry)
      end

    roots = Map.new(0..(n - 1), fn i -> {i, find_root(parent_final, i)} end)

    roots
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.map(fn {_root, indices} ->
      indices
      |> Enum.sort()
      |> Enum.map(&(Enum.at(indexed, &1) |> elem(0)))
    end)
  end

  defp union_overlapping(parent, _indexed, _i, j, n, _left_entry) when j >= n, do: parent

  defp union_overlapping(parent, indexed, i, j, n, left_entry) do
    right_entry = Enum.at(indexed, j) |> elem(0)

    parent_next =
      if left_entry.crn != right_entry.crn and
           meetings_overlap?(left_entry.meeting, right_entry.meeting) do
        root_i = find_root(parent, i)
        root_j = find_root(parent, j)

        if root_i == root_j, do: parent, else: Map.put(parent, root_i, root_j)
      else
        parent
      end

    union_overlapping(parent_next, indexed, i, j + 1, n, left_entry)
  end

  defp find_root(parent, node) do
    root = Map.fetch!(parent, node)
    if root == node, do: node, else: find_root(parent, root)
  end

  # -- Build conflict structs from an overlapping group within a resource partition --

  defp build_conflict(entries, :room) do
    room = List.first(entries).room
    owner_key = "room:#{room}"

    all_owner_keys =
      entries
      |> Enum.reduce(MapSet.new(), fn entry, acc -> MapSet.union(acc, entry.owner_keys) end)
      |> MapSet.put(owner_key)
      |> MapSet.reject(&tba_staff_owner?/1)

    base_conflict(
      type: :room,
      owner_keys: all_owner_keys,
      course_crns: extract_sorted_crns(entries),
      title: "Room conflict",
      entries: build_frontend_entries(entries),
      resource_label: room
    )
  end

  defp build_conflict(entries, :professor) do
    professor = List.first(entries).instructors |> List.first()
    owner_key = "professor:#{professor}"

    all_owner_keys =
      entries
      |> Enum.reduce(MapSet.new(), fn entry, acc -> MapSet.union(acc, entry.owner_keys) end)
      |> MapSet.put(owner_key)
      |> MapSet.reject(&tba_staff_owner?/1)

    base_conflict(
      type: :professor,
      owner_keys: all_owner_keys,
      course_crns: extract_sorted_crns(entries),
      title: "Professor conflict",
      entries: build_frontend_entries(entries),
      resource_label: professor
    )
  end

  # -- Conflict struct construction --

  defp base_conflict(
         type: type,
         owner_keys: owner_keys,
         course_crns: course_crns,
         title: title,
         entries: entries,
         resource_label: resource_label
       ) do
    %{
      type: type,
      title: title,
      resource_label: resource_label,
      entries: entries,
      owner_keys: MapSet.to_list(owner_keys),
      course_crns: course_crns,
      introduced_by_change_ids: [],
      schedule_targets: []
    }
  end

  # -- Post-processing attachments --

  defp attach_change_ids(conflict, change_ids_by_crn) do
    change_ids =
      conflict.course_crns
      |> Enum.map(&Map.get(change_ids_by_crn, &1))
      |> Enum.reject(&is_nil/1)

    %{conflict | introduced_by_change_ids: change_ids}
  end

  defp attach_schedule_targets(conflict, owner_targets_by_key) do
    schedule_targets =
      conflict.owner_keys
      |> Enum.map(&Map.get(owner_targets_by_key, &1, fallback_target(&1)))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.key)

    Map.put(conflict, :schedule_targets, schedule_targets)
  end

  defp fallback_target("room:" <> _room = owner_key), do: room_target(owner_key)
  defp fallback_target("professor:" <> _professor = owner_key), do: professor_target(owner_key)
  defp fallback_target(_owner_key), do: nil

  defp room_target("room:" <> room) when room != "" do
    %{kind: :room, key: "room:#{room}", label: "Room: #{room}"}
  end

  defp room_target(_owner_key), do: nil

  defp professor_target("professor:" <> professor) when professor != "" do
    %{kind: :professor, key: "professor:#{professor}", label: "Professor: #{professor}"}
  end

  defp professor_target(_owner_key), do: nil

  defp owner_name(%{name: name}), do: name
  defp owner_name(%{"name" => name}), do: name
  defp owner_name(_owner), do: nil

  # -- Indexing helpers --

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
    [conflict.type, Enum.sort(conflict.owner_keys)]
  end

  # -- Time overlap helpers --

  defp meetings_overlap?(left, right) do
    shares_day?(left["days"] || [], right["days"] || []) and
      time_minutes(left["start_time"]) < time_minutes(right["end_time"]) and
      time_minutes(right["start_time"]) < time_minutes(left["end_time"])
  end

  defp shares_day?(left_days, right_days) do
    !MapSet.disjoint?(MapSet.new(left_days), MapSet.new(right_days))
  end

  # -- Formatting helpers --

  defp extract_sorted_crns(entries) do
    entries |> Enum.map(& &1.crn) |> Enum.sort() |> Enum.uniq()
  end

  defp build_frontend_entries(entries) do
    entries
    |> Enum.uniq_by(& &1.crn)
    |> Enum.map(fn entry ->
      course_label =
        [entry.subject_code, entry.course_number, entry.course_name]
        |> Enum.reject(&blank?/1)
        |> Enum.join(" ")

      time_range = format_time_range(entry.meeting)

      %{course_label: course_label, time_range: time_range}
    end)
  end

  defp format_time_range(meeting) do
    [normalize_time(meeting["start_time"]), normalize_time(meeting["end_time"])]
    |> Enum.reject(&blank?/1)
    |> Enum.join("-")
  end

  defp normalize_time(time) when is_binary(time) do
    case String.split(time, ":") do
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

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp tba_staff_owner?("professor:" <> rest) do
    String.trim(rest) == @tba_staff
  end

  defp tba_staff_owner?(_owner_key), do: false
end
