defmodule SnowSeTools.Scheduling.ProgramSemesterOptions do
  @moduledoc """
  The ways a student could take one program semester this term: one section
  of every required course.

  Built to answer "can we offer this semester face to face?", so:

    * Only in-person sections are used (hybrid counts as in person), and
      from one home campus where a course is taught there: the campus
      teaching most of the semester's courses in person, ties going to the
      campus with more in-person sections that term (Ephraim). A Richfield
      section can't rescue an Ephraim student's week, and a high-school
      section is no one's way out. A course not taught in person on the home
      campus uses its in-person sections elsewhere (Manufacturing's TEMT
      courses meet in Richfield), and only a course never taught in person
      falls back to online sections, which land in the card's Online box. An
      online section never hides an in-person clash; instead the clash names
      it as a way out.
    * A lab goes with its own lecture. Labs are numbered lecture + 5 (CS 1410
      / CS 1415, PHYS 2210 / PHYS 2215), and a lab section that shares a
      lecture section's number (001, 002) belongs to that lecture only.
    * When no combination fits, the semester is never shown blank: the
      combinations with the fewest overlaps are offered, each carrying
      `:overlap` conflicts that say which classes meet at once.

  Courses must already be preparsed (see `ScheduleUtils`), which gives every
  meeting its `:start_minutes` and `:end_minutes`.
  """

  alias SnowSeTools.Scheduling.TimeOfDay

  # Enough clashing combinations to page through, from a bounded search: a
  # semester of five courses with several sections each has thousands.
  @max_clashing_options 50
  @max_combinations_searched 20_000

  @doc """
  Options as `%{index, label, courses, conflicts, campus}`, clashing ones
  only when nothing fits at all. Empty when a required course has no section, or
  nothing is required.
  """
  def build(courses: courses, required_courses: required_courses) do
    all_sections = Enum.map(required_courses, &sections_of(&1, courses))

    if required_courses == [] or Enum.any?(all_sections, &(&1 == [])) do
      []
    else
      campus = home_campus(all_sections, courses)
      groups = Enum.map(all_sections, &usable_sections(&1, campus))
      pairings = lab_pairings(required_courses, groups)

      alternatives = online_alternatives(all_sections, groups)

      combinations =
        case fitting(groups, pairings) do
          [] ->
            # Pairing data no section satisfies is ignored rather than
            # leaving the semester blank.
            with [] <- clashing(groups, pairings, alternatives),
                 do: clashing(groups, [], alternatives)

          fits ->
            Enum.map(fits, &{&1, []})
        end

      combinations
      |> Enum.with_index()
      |> Enum.map(fn {{sections, conflicts}, index} ->
        %{
          index: index,
          label: "Option #{index + 1}",
          courses: sections,
          conflicts: conflicts,
          campus: campus
        }
      end)
    end
  end

  @doc "Whether a section meets in a room at set times (hybrid does)."
  def in_person?(section) do
    Enum.any?(section["meet_info"] || [], fn meeting ->
      (meeting["days"] || []) != [] and is_binary(meeting["start_time"]) and
        is_binary(meeting["end_time"])
    end)
  end

  defp sections_of(required, courses) do
    subject = code(required["subject_code"])
    number = code(required["course_number"])

    courses
    |> Enum.filter(&(code(&1["subject_code"]) == subject and code(&1["course_number"]) == number))
    |> Enum.uniq_by(& &1["crn"])
  end

  @doc "Whether a section is taught online (not merely without set times)."
  def online?(section) do
    not in_person?(section) and
      (section["campus"] == "Online" or
         Enum.any?(section["meet_info"] || [], &(&1["building_code"] == "ONLINE")))
  end

  # See the moduledoc. Nil when no section names a campus (then any is used).
  defp home_campus(all_sections, term_courses) do
    courses_taught =
      all_sections
      |> Enum.flat_map(fn sections ->
        sections |> Enum.filter(&in_person?/1) |> Enum.map(& &1["campus"]) |> Enum.uniq()
      end)
      |> Enum.filter(&is_binary/1)
      |> Enum.frequencies()

    if courses_taught == %{} do
      nil
    else
      term_sections =
        term_courses
        |> Enum.filter(&(&1["campus"] in Map.keys(courses_taught) and in_person?(&1)))
        |> Enum.frequencies_by(& &1["campus"])

      courses_taught
      |> Enum.max_by(fn {campus, count} -> {count, Map.get(term_sections, campus, 0)} end)
      |> elem(0)
    end
  end

  # In person on the home campus; failing that in person anywhere; failing
  # that online; failing that whatever there is, so the course still shows.
  defp usable_sections(sections, campus) do
    [
      &(in_person?(&1) and (is_nil(campus) or &1["campus"] == campus)),
      &in_person?/1,
      &online?/1
    ]
    |> Enum.find_value(sections, fn keep? ->
      case Enum.filter(sections, keep?) do
        [] -> nil
        kept -> kept
      end
    end)
  end

  # -- Labs and their lectures ------------------------------------------------

  # `%{lecture: i, lab: j, numbered, lab_modes}`: positions in the required
  # list, the lecture section numbers a lab section may claim as its own, and
  # whether the lab is offered in person, online, or both.
  defp lab_pairings(required_courses, groups) do
    indexed = Enum.with_index(required_courses)

    for {lab, j} <- indexed,
        {lecture, i} <- indexed,
        lab_of?(lab, lecture) do
      %{
        lecture: i,
        lab: j,
        numbered: groups |> Enum.at(i) |> MapSet.new(&section_number/1),
        lab_modes: groups |> Enum.at(j) |> MapSet.new(&in_person?/1)
      }
    end
  end

  defp lab_of?(lab, lecture) do
    with true <- code(lab["subject_code"]) == code(lecture["subject_code"]),
         {lab_number, ""} <- Integer.parse(code(lab["course_number"])),
         {lecture_number, ""} <- Integer.parse(code(lecture["course_number"])) do
      rem(lecture_number, 10) == 0 and lab_number == lecture_number + 5
    else
      _other -> false
    end
  end

  # In person with in person, online with online -- unless the lab is only
  # offered the other way.
  defp lab_goes_with?(lecture, lab, %{numbered: numbered, lab_modes: lab_modes}) do
    (in_person?(lecture) == in_person?(lab) or not MapSet.member?(lab_modes, in_person?(lecture))) and
      (not MapSet.member?(numbered, section_number(lab)) or
         section_number(lab) == section_number(lecture))
  end

  # Whether `section`, about to take position `position`, keeps every pairing
  # with the sections already chosen (positions 0..position-1).
  defp keeps_pairings?(chosen, section, position, pairings) do
    Enum.all?(pairings, fn
      %{lecture: ^position, lab: lab} = pairing when lab < position ->
        lab_goes_with?(section, Enum.at(chosen, lab), pairing)

      %{lab: ^position, lecture: lecture} = pairing when lecture < position ->
        lab_goes_with?(Enum.at(chosen, lecture), section, pairing)

      _unrelated ->
        true
    end)
  end

  # -- Combinations -----------------------------------------------------------

  defp fitting(groups, pairings) do
    groups
    |> Enum.with_index()
    |> Enum.reduce([[]], fn {sections, position}, chosen_so_far ->
      for chosen <- chosen_so_far,
          section <- sections,
          keeps_pairings?(chosen, section, position, pairings),
          not Enum.any?(chosen, &(&1["crn"] == section["crn"] or overlap?(&1, section))),
          do: chosen ++ [section]
    end)
  end

  defp clashing(groups, pairings, alternatives) do
    groups
    |> combinations(pairings, 0, [])
    |> Stream.take(@max_combinations_searched)
    |> Enum.map(&{&1, overlaps(&1, alternatives)})
    |> Enum.sort_by(fn {_sections, conflicts} -> length(conflicts) end)
    |> Enum.take(@max_clashing_options)
  end

  defp combinations([], _pairings, _position, chosen), do: [chosen]

  defp combinations([sections | rest], pairings, position, chosen) do
    sections
    |> Stream.filter(&keeps_pairings?(chosen, &1, position, pairings))
    |> Stream.flat_map(&combinations(rest, pairings, position + 1, chosen ++ [&1]))
  end

  # -- Overlaps, shaped like the conflict detector's conflicts -------------------

  defp overlaps(sections, alternatives) do
    for {left, i} <- Enum.with_index(sections),
        {right, j} <- Enum.with_index(sections),
        i < j,
        {left_meeting, right_meeting} <- [overlapping_meetings(left, right)],
        not is_nil(left_meeting) do
      %{
        type: :overlap,
        title: "Class overlap",
        resource_label: "the same students",
        course_crns: Enum.sort([left["crn"], right["crn"]]),
        owner_keys: [],
        entries: [entry(left, left_meeting), entry(right, right_meeting)],
        online_alternatives:
          Enum.flat_map([left, right], &Map.get(alternatives, course_code(&1), []))
      }
    end
  end

  # Online sections a student could switch to, by course, for each course
  # whose online sections were set aside.
  defp online_alternatives(all_sections, groups) do
    all_sections
    |> Enum.zip(groups)
    |> Enum.flat_map(fn {sections, kept} ->
      case Enum.filter(sections -- kept, &online?/1) do
        [] -> []
        [first | _] = online -> [{course_code(first), Enum.map(online, &section_label/1)}]
      end
    end)
    |> Map.new()
  end

  defp overlapping_meetings(left, right) do
    Enum.find_value(left["meet_info"] || [], {nil, nil}, fn left_meeting ->
      Enum.find_value(right["meet_info"] || [], fn right_meeting ->
        if meetings_overlap?(left_meeting, right_meeting),
          do: {left_meeting, right_meeting}
      end)
    end)
  end

  defp overlap?(left, right) do
    {meeting, _other} = overlapping_meetings(left, right)
    not is_nil(meeting)
  end

  defp meetings_overlap?(left, right) do
    has_times?(left) and has_times?(right) and
      not MapSet.disjoint?(MapSet.new(left["days"] || []), MapSet.new(right["days"] || [])) and
      left[:start_minutes] < right[:end_minutes] and right[:start_minutes] < left[:end_minutes]
  end

  defp has_times?(meeting),
    do: is_binary(meeting["start_time"]) and is_binary(meeting["end_time"])

  defp entry(section, meeting) do
    %{
      crn: section["crn"],
      course_label: section_label(section),
      days: meeting["days"] || [],
      start_time: TimeOfDay.normalize_or_nil(meeting["start_time"]),
      end_time: TimeOfDay.normalize_or_nil(meeting["end_time"]),
      building: meeting["building"],
      building_code: meeting["building_code"],
      room: meeting["room"]
    }
  end

  defp section_label(section), do: "#{course_code(section)}-#{section_number(section)}"

  defp course_code(section),
    do: "#{code(section["subject_code"])} #{code(section["course_number"])}"

  defp section_number(section), do: code(section["section_number"])

  defp code(value) when is_binary(value), do: value |> String.trim() |> String.upcase()
  defp code(_value), do: ""
end
