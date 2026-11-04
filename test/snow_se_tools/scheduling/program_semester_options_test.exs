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

  describe "campuses" do
    test "a Richfield section never stands in for an Ephraim student's" do
      # MATH 2040 is broadcast to both campuses at 9:30; ENGR 2140 is only in
      # Ephraim at 9:30. The Richfield copy must not look like a way out.
      sections = [
        section("MATH", "2040", "1F1", "1339", @mtwf, "09:30", "10:20", "Ephraim Campus"),
        section("MATH", "2040", "2A1", "1240", @mtwf, "09:30", "10:20", "Richfield Campus"),
        section("ENGR", "2140", "001", "1411", @mtwf, "09:30", "10:20", "Ephraim Campus")
      ]

      assert [%{courses: courses, conflicts: [_clash]} = option] =
               options(sections, ["MATH 2040", "ENGR 2140"])

      assert crns(courses) == ["1339", "1411"]
      assert option.campus == "Ephraim Campus"
    end

    test "a course taught in person only on another campus is still in person, not online" do
      # Manufacturing: TEMT meets in Richfield, everything else in Ephraim.
      sections = [
        section("ENGR", "2140", "001", "1411", @mtwf, "09:30", "10:20", "Ephraim Campus"),
        section(
          "ENGL",
          "3260",
          "001",
          "1445",
          ~w(Tuesday Thursday),
          "14:00",
          "15:15",
          "Ephraim Campus"
        ),
        section(
          "TEMT",
          "1150",
          "300",
          "2716",
          ~w(Tuesday Thursday),
          "08:00",
          "09:25",
          "Richfield Campus"
        ),
        online("TEMT", "1150", "N01", "2719")
      ]

      assert [%{courses: courses, campus: "Ephraim Campus"}] =
               options(sections, ["ENGR 2140", "ENGL 3260", "TEMT 1150"])

      assert crns(courses) == ["1411", "1445", "2716"]
    end

    test "the home campus is the one teaching the most of the semester's courses" do
      sections = [
        section("TEMT", "1150", "300", "1", @mwf, "08:00", "08:50", "Richfield Campus"),
        section("TEMT", "1150", "800", "2", @mwf, "08:00", "08:50", "Richfield Campus"),
        section("TEMT", "1300", "300", "3", @mwf, "11:00", "11:50", "Richfield Campus"),
        section("MATH", "2040", "1F1", "4", @mwf, "13:00", "13:50", "Ephraim Campus"),
        section("ENGR", "2140", "001", "5", @mwf, "14:00", "14:50", "Ephraim Campus"),
        section("ENGL", "3260", "001", "6", @mwf, "15:00", "15:50", "Ephraim Campus")
      ]

      [option | _] =
        options(sections, ["TEMT 1150", "TEMT 1300", "MATH 2040", "ENGR 2140", "ENGL 3260"])

      assert option.campus == "Ephraim Campus"
    end

    test "a tie goes to the campus with more in-person sections that term" do
      sections = [
        section("MATH", "2040", "1F1", "1", @mwf, "09:00", "09:50", "Ephraim Campus"),
        section("MATH", "2040", "2A1", "2", @mwf, "09:00", "09:50", "Richfield Campus"),
        # Elsewhere in the term, Ephraim is busier.
        section("HIST", "1700", "001", "3", @mwf, "10:00", "10:50", "Ephraim Campus")
      ]

      assert [%{courses: [%{"crn" => "1"}], campus: "Ephraim Campus"}] =
               ScheduleUtils.academic_program_semester_schedule_variants(
                 courses: sections,
                 required_courses: [%{"subject_code" => "MATH", "course_number" => "2040"}]
               )
    end

    test "a high-school section without set times is not an online way out" do
      sections = [
        section("MATH", "1210", "1F1", "1", @mtwf, "13:30", "14:20", "Ephraim Campus"),
        base("MATH", "1210", "460", "2", [%{"days" => [], "start_time" => nil, "end_time" => nil}])
        |> Map.put("campus", "High School"),
        online("MATH", "1210", "N01", "3"),
        section("CHEM", "1215", "001", "4", ~w(Monday), "13:30", "16:20", "Ephraim Campus")
      ]

      assert [%{conflicts: [clash]}] = options(sections, ["MATH 1210", "CHEM 1215"])
      assert clash.online_alternatives == ["MATH 1210-N01"]
    end
  end

  describe "when nothing fits" do
    test "the clash is found in any of a class's meetings" do
      # ENGR 2240 lectures Tue/Thu morning and has a Thursday lab.
      engr =
        section("ENGR", "2240", "001", "4219", ~w(Tuesday Thursday), "08:30", "09:20")
        |> Map.update!("meet_info", fn [lecture] ->
          [
            lecture,
            Map.merge(lecture, %{
              "days" => ["Thursday"],
              "start_time" => "10:30:00",
              "end_time" => "13:20:00"
            })
          ]
        end)

      geo = section("GEO", "1115", "001", "4344", ["Thursday"], "12:00", "13:50")

      assert [%{conflicts: [clash]}] = options([engr, geo], ["ENGR 2240", "GEO 1115"])
      assert [%{days: ["Thursday"]}, %{days: ["Thursday"]}] = clash.entries
    end

    test "offers the fewest-overlap combinations first, and no more than fifty" do
      # Four courses with four sections each: 256 combinations. Sections 2-4
      # all meet at 9:00; each course's section 1 shares an hour with one
      # other course's, so no combination fits and the best has one overlap.
      first_hours = %{"AAA" => "10:00", "BBB" => "10:00", "CCC" => "11:00", "DDD" => "11:00"}

      sections =
        for subject <- ~w(AAA BBB CCC DDD), n <- 1..4 do
          start = if n == 1, do: first_hours[subject], else: "09:00"
          finish = String.replace(start, ":00", ":50")
          section(subject, "1000", "00#{n}", "#{subject}#{n}", ["Monday"], start, finish)
        end

      options = options(sections, ["AAA 1000", "BBB 1000", "CCC 1000", "DDD 1000"])
      counts = Enum.map(options, &length(&1.conflicts))

      assert length(options) == 50
      assert counts == Enum.sort(counts)
      assert hd(counts) == 1
      assert List.last(counts) > 1
    end
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

  defp section(subject, number, section_number, crn, days, start_time, end_time, campus \\ nil) do
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
    |> then(&if(campus, do: Map.put(&1, "campus", campus), else: &1))
  end

  defp online(subject, number, section_number, crn),
    do:
      base(subject, number, section_number, crn, [online_meeting()])
      |> Map.put("campus", "Online")

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
