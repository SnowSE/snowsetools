defmodule SnowSeToolsWeb.Scheduling.ScheduleOwnerData do
  @days ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
  @default_start_minutes 8 * 60
  @default_end_minutes 17 * 60

  def build_schedule_owner_entries(courses, academic_programs) do
    courses_with_preparsed =
      Enum.map(courses, fn course ->
        Map.put(
          course,
          "meet_info",
          Enum.map(course["meet_info"] || [], &preparse_meeting/1)
        )
      end)

    professor_entries(courses_with_preparsed) ++
      program_semester_entries(courses_with_preparsed, academic_programs) ++
      room_entries(courses_with_preparsed)
  end

  def build_schedule_owners(courses: courses, query: query, academic_programs: academic_programs) do
    normalized_query = normalize(query)
    query_words = String.split(normalized_query, ~r/\s+/, trim: true)

    courses
    |> build_schedule_owner_entries(academic_programs)
    |> Enum.filter(fn schedule_owner ->
      query_words == [] or query_matches_all?(schedule_owner.search_text, query_words)
    end)
    |> Enum.sort_by(fn schedule_owner ->
      {schedule_owner.type_order, String.downcase(schedule_owner.name)}
    end)
    |> Enum.take(250)
  end

  def lookup_selected(schedule_owners, selected_keys, _academic_programs) do
    by_key = Map.new(schedule_owners, &{&1.key, &1})

    Enum.map(selected_keys, &Map.get(by_key, &1))
    |> Enum.reject(&is_nil/1)
  end

  def selected_schedule_owners(
        courses: courses,
        selected_schedule_owner_keys: selected_schedule_owner_keys,
        academic_programs: academic_programs
      ) do
    schedule_owners = build_schedule_owner_entries(courses, academic_programs)
    lookup_selected(schedule_owners, selected_schedule_owner_keys, academic_programs)
  end

  defp professor_entries(courses) do
    courses
    |> Enum.flat_map(fn course ->
      for instructor <- Map.get(course, "instructors", []),
          name = instructor["name"],
          !blank?(name),
          do: {name, course}
    end)
    |> Enum.group_by(fn {name, _course} -> name end, fn {_name, course} -> course end)
    |> Enum.map(fn {name, schedule_owner_courses} ->
      build_schedule_owner(:professor, name, schedule_owner_courses)
    end)
  end

  defp room_entries(courses) do
    courses
    |> Enum.flat_map(fn course ->
      for meeting <- Map.get(course, "meet_info", []),
          {room, true} <- [{meeting["__room_name"], !is_nil(meeting["__room_name"])}],
          uniq: true,
          do: {room, course}
    end)
    |> Enum.group_by(fn {room, _course} -> room end, fn {_room, course} -> course end)
    |> Enum.map(fn {room, schedule_owner_courses} ->
      build_schedule_owner(:room, room, schedule_owner_courses)
    end)
  end

  defp build_schedule_owner(type, name, courses) do
    regular_courses =
      Enum.filter(courses, fn course ->
        Enum.any?(course["meet_info"] || [], fn meeting ->
          meeting["days"] != [] and is_binary(meeting["start_time"]) and
            is_binary(meeting["end_time"])
        end)
      end)

    meetings_by_day = meetings_by_day(type, name, regular_courses)
    all_meetings = meetings_by_day |> Map.values() |> List.flatten()
    {start_minutes, end_minutes} = schedule_bounds(all_meetings)

    %{
      key: schedule_owner_key(type, name),
      dom_id: schedule_owner_dom_id(type, name),
      type: type,
      type_order: schedule_owner_type_order(type),
      type_label: schedule_owner_type_label(type),
      name: name,
      search_text: name,
      courses: Enum.uniq_by(courses, & &1["crn"]),
      credit_count: credit_count(courses),
      meetings_by_day: meetings_by_day,
      online_courses: courses -- regular_courses,
      start_minutes: start_minutes,
      end_minutes: end_minutes
    }
  end

  defp program_semester_entries(courses, academic_programs) do
    Enum.flat_map(academic_programs, fn program ->
      Enum.with_index(program["semesters"] || [])
      |> Enum.map(fn {semester, semester_index} ->
        semester_courses = semester["courses"] || []

        matching_courses =
          courses_matching_requirements(courses: courses, required_courses: semester_courses)

        semester_name = semester_label(semester_index)
        name = "#{program["name"]} #{semester_name}"

        build_schedule_owner(:academic_program_semester, name, matching_courses)
        |> Map.merge(%{
          key:
            schedule_owner_key(:academic_program_semester, "#{program["id"]}:#{semester["id"]}"),
          dom_id:
            schedule_owner_dom_id(
              :academic_program_semester,
              "#{program["id"]}-#{semester["id"]}"
            ),
          type_order: 1,
          type_label: "Program Semester",
          program_name: program["name"],
          semester_name: semester_name,
          requirement_count: length(semester_courses),
          search_text: "#{program["name"]} #{semester_name}"
        })
      end)
    end)
  end

  defp courses_matching_requirements(courses: courses, required_courses: required_courses) do
    required_pairs =
      MapSet.new(required_courses, fn course ->
        {normalize_course_code(course["subject_code"]),
         normalize_course_code(course["course_number"])}
      end)

    Enum.filter(courses, fn course ->
      MapSet.member?(
        required_pairs,
        {normalize_course_code(course["subject_code"]),
         normalize_course_code(course["course_number"])}
      )
    end)
  end

  defp meetings_by_day(type, name, courses) do
    tagged_meetings =
      Enum.flat_map(courses, fn course ->
        for meeting <- Map.get(course, "meet_info", []),
            # preparse guard
            !is_nil(meeting["__room_name"]),
            day <- meeting["days"] || [],
            meeting_matches_schedule_owner?(type, name, course, meeting) do
          {day, meeting_from_course(course, meeting)}
        end
      end)

    Enum.reduce(@days, %{}, fn day, acc ->
      meetings =
        for {^day, meeting} <- tagged_meetings, do: meeting

      Map.put(acc, day, Enum.sort_by(meetings, & &1.start_minutes))
    end)
  end

  defp meeting_matches_schedule_owner?(:professor, name, course, _meeting) do
    Enum.any?(course["instructors"] || [], fn instructor -> instructor["name"] == name end)
  end

  defp meeting_matches_schedule_owner?(:room, name, _course, meeting),
    do: meeting["__room_name"] == name

  defp meeting_matches_schedule_owner?(:academic_program_semester, _name, _course, _meeting),
    do: true

  defp meeting_from_course(course, meeting) do
    %{start_minutes: start_minutes, end_minutes: end_minutes} = meeting

    %{
      course_name: course["name"],
      subject_code: course["subject_code"],
      course_number: course["course_number"],
      crn: course["crn"],
      start_time: meeting["start_time"],
      end_time: meeting["end_time"],
      start_minutes: start_minutes,
      end_minutes: end_minutes,
      room: meeting["__room_name"],
      instructors: Enum.map(course["instructors"] || [], & &1["name"])
    }
  end

  defp schedule_bounds([]), do: {@default_start_minutes, @default_end_minutes}

  defp schedule_bounds(meetings) do
    start_minutes =
      meetings
      |> Enum.min_by(& &1.start_minutes)
      |> then(&min(&1.start_minutes, @default_start_minutes))
      |> floor_to_hour()

    end_minutes =
      meetings
      |> Enum.max_by(& &1.end_minutes)
      |> then(&max(&1.end_minutes, @default_end_minutes))
      |> ceil_to_hour()

    {start_minutes, end_minutes}
  end

  defp parse_minutes(time) when is_binary(time) do
    case String.split(time, ":") do
      [hour, minute | _] ->
        with {h, ""} <- Integer.parse(hour),
             {m, ""} <- Integer.parse(minute) do
          h * 60 + m
        else
          _ -> @default_start_minutes
        end

      _ ->
        @default_start_minutes
    end
  end

  defp parse_minutes(_time), do: @default_start_minutes

  defp floor_to_hour(minutes), do: div(minutes, 60) * 60
  defp ceil_to_hour(minutes), do: div(minutes + 59, 60) * 60

  defp room_name(meeting) do
    building_code = meeting["building_code"]
    building = meeting["building"]
    room = meeting["room"]

    cond do
      blank?(room) -> nil
      !blank?(building_code) -> "#{building_code} #{room}"
      !blank?(building) -> "#{building} #{room}"
      true -> room
    end
  end

  defp credit_count(courses) do
    courses
    |> Enum.uniq_by(& &1["crn"])
    |> Enum.reduce(0, fn course, total -> total + (course["credit_hours"] || 0) end)
    |> round()
  end

  defp schedule_owner_key(type, name), do: "#{type}:#{name}"

  defp schedule_owner_type_order(:professor), do: 0
  defp schedule_owner_type_order(:academic_program_semester), do: 1
  defp schedule_owner_type_order(:room), do: 2

  defp schedule_owner_type_label(:professor), do: "Professor"
  defp schedule_owner_type_label(:academic_program_semester), do: "Program Semester"
  defp schedule_owner_type_label(:room), do: "Room"

  defp schedule_owner_dom_id(type, name) do
    "#{type}-#{name}"
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp normalize(value) when is_binary(value), do: value |> String.downcase() |> String.trim()
  defp normalize(_value), do: ""

  defp normalize_course_code(value) when is_binary(value),
    do: value |> String.trim() |> String.upcase()

  defp normalize_course_code(_value), do: ""

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true

  defp semester_label(index) do
    case index do
      0 -> "Freshman first semester"
      1 -> "Freshman second semester"
      2 -> "Sophomore first semester"
      3 -> "Sophomore second semester"
      4 -> "Junior first semester"
      5 -> "Junior second semester"
      6 -> "Senior first semester"
      7 -> "Senior second semester"
      _ -> "Year #{div(index, 2) + 1} semester #{rem(index, 2) + 1}"
    end
  end

  defp preparse_meeting(meeting) do
    meeting
    |> Map.put("__room_name", room_name(meeting))
    |> Map.put(:start_minutes, parse_minutes(meeting["start_time"]))
    |> Map.put(:end_minutes, parse_minutes(meeting["end_time"]))
  end

  defp query_matches_all?(value, words) do
    search_text = normalize(value)
    Enum.all?(words, &String.contains?(search_text, &1))
  end
end
