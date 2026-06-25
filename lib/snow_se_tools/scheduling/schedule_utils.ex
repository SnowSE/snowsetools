defmodule SnowSeTools.Scheduling.ScheduleUtils do
  @days ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
  @default_start_minutes 8 * 60
  @default_end_minutes 17 * 60

  def build_week_schedule(type: type, name: name, courses: courses) do
    courses = Enum.map(courses, &preparse_course/1)

    regular_courses =
      Enum.filter(courses, fn course ->
        Enum.any?(course["meet_info"] || [], fn meeting ->
          meeting["days"] != [] and is_binary(meeting["start_time"]) and
            is_binary(meeting["end_time"])
        end)
      end)

    meetings_by_day = meetings_by_day(type: type, name: name, courses: regular_courses)
    all_meetings = meetings_by_day |> Map.values() |> List.flatten()
    {start_minutes, end_minutes} = schedule_bounds(all_meetings)

    %{
      type: type,
      type_label: type_label(type),
      name: name,
      credit_count: credit_count(courses),
      start_minutes: start_minutes,
      end_minutes: end_minutes,
      meetings_by_day: meetings_by_day,
      online_courses: courses -- regular_courses,
      courses: Enum.uniq_by(courses, & &1["crn"])
    }
  end

  def owner_course_lists(courses: courses, academic_programs: academic_programs) do
    courses = Enum.map(courses, &preparse_course/1)

    professor_course_lists(courses: courses) ++
      academic_program_semester_course_lists(
        courses: courses,
        academic_programs: academic_programs
      ) ++
      room_course_lists(courses: courses)
  end

  def room_name(meeting: meeting) do
    building_code = meeting["building_code"]
    building = meeting["building"]
    room = meeting["room"]

    cond do
      blank?(room) -> nil
      !blank?(building) -> "#{building} #{room}"
      !blank?(building_code) -> "#{building_code} #{room}"
      true -> room
    end
  end

  def semester_label(0), do: "Freshman first semester"
  def semester_label(1), do: "Freshman second semester"
  def semester_label(2), do: "Sophomore first semester"
  def semester_label(3), do: "Sophomore second semester"
  def semester_label(4), do: "Junior first semester"
  def semester_label(5), do: "Junior second semester"
  def semester_label(6), do: "Senior first semester"
  def semester_label(7), do: "Senior second semester"

  def semester_label(index) do
    "Year #{div(index, 2) + 1} semester #{rem(index, 2) + 1}"
  end

  def courses_matching_requirements(courses: courses, required_courses: required_courses) do
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

  defp professor_course_lists(courses: courses) do
    courses
    |> Enum.flat_map(fn course ->
      for instructor <- Map.get(course, "instructors", []),
          name = instructor["name"],
          !blank?(name),
          do: {:professor, name, course}
    end)
    |> Enum.group_by(fn {_type, name, _course} -> name end, fn {_type, _name, course} ->
      course
    end)
    |> Enum.map(fn {name, owner_courses} ->
      %{
        owner_key: owner_key(type: :professor, name: name),
        type: :professor,
        name: name,
        courses: owner_courses
      }
    end)
  end

  defp room_course_lists(courses: courses) do
    courses
    |> Enum.flat_map(fn course ->
      for meeting <- Map.get(course, "meet_info", []),
          {room, true} <- [{meeting["__room_name"], !is_nil(meeting["__room_name"])}],
          uniq: true,
          do: {room, course}
    end)
    |> Enum.group_by(fn {room, _course} -> room end, fn {_room, course} -> course end)
    |> Enum.map(fn {room, owner_courses} ->
      %{
        owner_key: owner_key(type: :room, name: room),
        type: :room,
        name: room,
        courses: owner_courses
      }
    end)
  end

  defp academic_program_semester_course_lists(
         courses: courses,
         academic_programs: academic_programs
       ) do
    Enum.flat_map(academic_programs, fn program ->
      (program["semesters"] || [])
      |> Enum.with_index()
      |> Enum.map(fn {semester, semester_index} ->
        required_courses = semester["courses"] || []
        semester_name = semester_label(semester_index)

        %{
          owner_key:
            owner_key(
              type: :academic_program_semester,
              name: "#{program["id"]}:#{semester["id"]}"
            ),
          type: :academic_program_semester,
          name: "#{program["name"]} #{semester_name}",
          program_name: program["name"],
          semester_name: semester_name,
          courses:
            courses_matching_requirements(
              courses: courses,
              required_courses: required_courses
            )
        }
      end)
    end)
  end

  defp meetings_by_day(type: type, name: name, courses: courses) do
    tagged_meetings =
      Enum.flat_map(courses, fn course ->
        for meeting <- Map.get(course, "meet_info", []),
            !is_nil(meeting["__room_name"]),
            day <- meeting["days"] || [],
            meeting_matches?(type: type, name: name, course: course, meeting: meeting) do
          {day, meeting_from_course(course: course, meeting: meeting)}
        end
      end)

    Enum.reduce(@days, %{}, fn day, acc ->
      meetings = for {^day, meeting} <- tagged_meetings, do: meeting
      Map.put(acc, day, Enum.sort_by(meetings, & &1.start_minutes))
    end)
  end

  defp meeting_matches?(type: :professor, name: name, course: course, meeting: _meeting) do
    Enum.any?(course["instructors"] || [], &(&1["name"] == name))
  end

  defp meeting_matches?(type: :room, name: name, course: _course, meeting: meeting),
    do: meeting["__room_name"] == name

  defp meeting_matches?(
         type: :academic_program_semester,
         name: _name,
         course: _course,
         meeting: _meeting
       ),
       do: true

  defp meeting_from_course(course: course, meeting: meeting) do
    %{start_minutes: start_minutes, end_minutes: end_minutes} = meeting

    %{
      "__source" => Map.get(course, "__source", :base),
      course_name: course["name"],
      subject_code: course["subject_code"],
      course_number: course["course_number"],
      crn: course["crn"],
      term: term_code(course),
      credit_hours: course["credit_hours"] || 0,
      start_time: meeting["start_time"],
      end_time: meeting["end_time"],
      start_minutes: start_minutes,
      end_minutes: end_minutes,
      room: meeting["__room_name"],
      instructors: Enum.map(course["instructors"] || [], & &1["name"]),
      meeting: meeting_payload(meeting),
      meet_info: Enum.map(course["meet_info"] || [], &meeting_payload/1)
    }
  end

  defp term_code(%{"term" => %{"code" => code}}) when is_binary(code), do: code
  defp term_code(%{"term_code" => code}) when is_binary(code), do: code
  defp term_code(_course), do: ""

  defp meeting_payload(meeting) do
    meeting
    |> Map.take([
      "days",
      "start_time",
      "end_time",
      "building",
      "building_code",
      "room"
    ])
    |> Map.put_new("days", [])
    |> Map.put_new("building", nil)
    |> Map.put_new("building_code", nil)
    |> Map.put_new("room", nil)
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

  defp preparse_course(course) do
    Map.put(course, "meet_info", Enum.map(course["meet_info"] || [], &preparse_meeting/1))
  end

  defp preparse_meeting(meeting) do
    meeting
    |> Map.put("__room_name", room_name(meeting: meeting))
    |> Map.put(:start_minutes, parse_minutes(meeting["start_time"]))
    |> Map.put(:end_minutes, parse_minutes(meeting["end_time"]))
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

  defp credit_count(courses) do
    courses
    |> Enum.uniq_by(& &1["crn"])
    |> Enum.reduce(0, fn course, total -> total + (course["credit_hours"] || 0) end)
    |> round()
  end

  defp owner_key(type: type, name: name), do: "#{type}:#{name}"
  defp type_label(:professor), do: "Professor"
  defp type_label(:academic_program_semester), do: "Program Semester"
  defp type_label(:room), do: "Room"
  defp floor_to_hour(minutes), do: div(minutes, 60) * 60
  defp ceil_to_hour(minutes), do: div(minutes + 59, 60) * 60

  defp normalize_course_code(value) when is_binary(value),
    do: value |> String.trim() |> String.upcase()

  defp normalize_course_code(_value), do: ""
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true
end
