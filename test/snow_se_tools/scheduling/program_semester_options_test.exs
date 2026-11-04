defmodule SnowSeTools.Scheduling.ProgramSemesterOptionsTest do
  # The cases come from real Spring 2027 sections that left program semesters
  # blank, or showed an online section where an in-person clash was hiding.
  use ExUnit.Case, async: true

  alias SnowSeTools.Scheduling.ScheduleUtils

  @mwf ~w(Monday Wednesday Friday)
  @mtwf ~w(Monday Tuesday Wednesday Friday)

  test "two single-section classes at the same hour show the clash instead of a blank semester" do
    # BSSE (start with CS 1410), sophomore spring.
    options =
      options(
        [
          section("CS", "2860", "001", "1507", @mwf, "09:30", "10:20"),
          section("MATH", "2270", "001", "1068", @mwf, "09:30", "10:20")
        ],
        ["CS 2860", "MATH 2270"]
      )

    assert [%{courses: courses, conflicts: [overlap]}] = options
    assert crns(courses) == ["1068", "1507"]
    assert overlap.type == :overlap
    assert overlap.course_crns == ["1068", "1507"]
    assert Enum.map(overlap.entries, & &1.course_label) == ["CS 2860-001", "MATH 2270-001"]
  end

  test "an online section no longer hides an in-person clash; it is named as the way out" do
    # Electrical Engineering, freshman spring: the ENGR 1405 lab and the
    # PHYS 2215 lab are both Thursday afternoon.
    sections = [
      section("ENGR", "1400", "001", "1808", @mwf, "14:30", "15:20"),
      online("ENGR", "1400", "N01", "2092"),
      section("ENGR", "1405", "001", "1809", ["Thursday"], "13:30", "15:20"),
      online("ENGR", "1405", "N01", "2093"),
      section("PHYS", "2210", "001", "1482", @mtwf, "13:30", "14:20"),
      section("PHYS", "2215", "001", "1483", ["Thursday"], "13:30", "16:20"),
      section("MATH", "1220", "001", "1161", @mtwf, "10:30", "11:20"),
      section("MATH", "1220", "1F1", "1152", @mtwf, "13:30", "14:20")
    ]

    options = options(sections, ["ENGR 1400", "ENGR 1405", "MATH 1220", "PHYS 2210", "PHYS 2215"])

    refute Enum.any?(options, fn option ->
             Enum.any?(option.courses, &(&1["crn"] in ["2092", "2093"]))
           end)

    # Fewest clashes first: MATH 1220-001 avoids PHYS 2210; 1F1 does not.
    [best | rest] = options
    assert "1161" in crns(best.courses)
    assert [lab_clash] = best.conflicts
    assert lab_clash.course_crns == ["1483", "1809"]
    assert lab_clash.online_alternatives == ["ENGR 1405-N01"]
    assert Enum.all?(rest, &(length(&1.conflicts) >= 2))
  end

  test "a lab goes with the lecture of the same section number, and in-person with in-person" do
    sections = [
      section("CS", "1410", "001", "1903", @mwf, "08:30", "09:20"),
      section("CS", "1410", "002", "2028", @mwf, "13:30", "14:20"),
      online("CS", "1410", "N01", "2087"),
      section("CS", "1415", "001", "1071", ["Tuesday"], "08:30", "10:20"),
      section("CS", "1415", "002", "2027", ["Tuesday"], "13:30", "15:20"),
      online("CS", "1415", "N01", "2088")
    ]

    assert sections |> options(["CS 1410", "CS 1415"]) |> Enum.map(&crns(&1.courses)) == [
             ["1071", "1903"],
             ["2027", "2028"]
           ]
  end

  test "a lab section numbered like no lecture can go with any lecture" do
    sections = [
      section("CHEM", "1210", "001", "1", @mwf, "08:30", "09:20"),
      section("CHEM", "1210", "002", "2", @mwf, "11:30", "12:20"),
      section("CHEM", "1215", "001", "11", ["Tuesday"], "07:30", "10:20"),
      section("CHEM", "1215", "007", "17", ["Thursday"], "13:30", "16:20")
    ]

    assert sections |> options(["CHEM 1210", "CHEM 1215"]) |> Enum.map(&crns(&1.courses)) == [
             ["1", "11"],
             ["1", "17"],
             ["17", "2"]
           ]
  end

  test "a course offered only online still counts, and its lab is matched to it" do
    sections = [
      online("ENGR", "1400", "N01", "2092"),
      online("ENGR", "1405", "N01", "2093"),
      section("MATH", "1220", "001", "1161", @mtwf, "10:30", "11:20")
    ]

    assert [%{courses: courses, conflicts: []}] =
             options(sections, ["ENGR 1400", "ENGR 1405", "MATH 1220"])

    assert crns(courses) == ["1161", "2092", "2093"]
  end

  test "an in-person lecture still pairs with a lab offered only online" do
    sections = [
      section("ENGR", "1400", "001", "1808", @mwf, "14:30", "15:20"),
      online("ENGR", "1405", "N01", "2093")
    ]

    assert [%{courses: courses}] = options(sections, ["ENGR 1400", "ENGR 1405"])
    assert crns(courses) == ["1808", "2093"]
  end

  test "hybrid sections count as in person" do
    hybrid =
      section("TEMT", "1150", "300", "2716", ~w(Tuesday Thursday), "08:00", "09:25")
      |> Map.update!("meet_info", &(&1 ++ [online_meeting()]))

    sections = [hybrid, online("TEMT", "1150", "337", "2717")]

    assert [%{courses: [%{"crn" => "2716"}]}] = options(sections, ["TEMT 1150"])
  end

  test "nothing required, or a course not offered, gives no options" do
    assert options([section("CS", "1400", "001", "1", @mwf, "09:00", "09:50")], []) == []
    assert options([section("CS", "1400", "001", "1", @mwf, "09:00", "09:50")], ["CS 9999"]) == []
  end

  defp options(sections, required) do
    ScheduleUtils.academic_program_semester_schedule_variants(
      courses: sections,
      required_courses:
        Enum.map(required, fn code ->
          [subject, number] = String.split(code)
          %{"subject_code" => subject, "course_number" => number}
        end)
    )
  end

  defp crns(courses), do: courses |> Enum.map(& &1["crn"]) |> Enum.sort()

  defp section(subject, number, section_number, crn, days, start_time, end_time) do
    base(subject, number, section_number, crn, [
      %{
        "building" => "Science",
        "building_code" => "GRSC",
        "room" => "142",
        "days" => days,
        "start_time" => start_time <> ":00",
        "end_time" => end_time <> ":00"
      }
    ])
  end

  defp online(subject, number, section_number, crn),
    do: base(subject, number, section_number, crn, [online_meeting()])

  defp online_meeting do
    %{
      "building" => "ONLINE",
      "building_code" => "ONLINE",
      "room" => "ONLINE",
      "days" => [],
      "start_time" => nil,
      "end_time" => nil
    }
  end

  defp base(subject, number, section_number, crn, meet_info) do
    %{
      "crn" => crn,
      "term_code" => "202710",
      "subject_code" => subject,
      "course_number" => number,
      "section_number" => section_number,
      "name" => "#{subject} #{number}",
      "credit_hours" => 3,
      "instructors" => [],
      "meet_info" => meet_info
    }
  end
end
