defmodule SnowSeTools.Scheduling.ScheduleUtilsTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Scheduling.ScheduleUtils

  test "academic program semester variants choose one non-conflicting section per required course" do
    variants =
      ScheduleUtils.academic_program_semester_schedule_variants(
        courses: [
          course(crn: "10001", subject_code: "MATH", course_number: "1050"),
          course(crn: "10002", subject_code: "MATH", course_number: "1050", days: ["Tuesday"]),
          course(crn: "20001", subject_code: "ENGL", course_number: "1010"),
          course(crn: "20002", subject_code: "ENGL", course_number: "1010", days: ["Wednesday"])
        ],
        required_courses: [
          %{"subject_code" => "MATH", "course_number" => "1050"},
          %{"subject_code" => "ENGL", "course_number" => "1010"}
        ]
      )

    assert length(variants) == 3

    assert Enum.map(variants, fn variant -> Enum.map(variant.courses, & &1["crn"]) end) == [
             ["10001", "20002"],
             ["10002", "20001"],
             ["10002", "20002"]
           ]
  end

  test "academic program semester owner exposes first variant instead of every matching section" do
    [program_semester_owner] =
      ScheduleUtils.owner_course_lists(
        courses: [
          course(crn: "10001", subject_code: "MATH", course_number: "1050"),
          course(crn: "10002", subject_code: "MATH", course_number: "1050", days: ["Tuesday"]),
          course(crn: "20001", subject_code: "ENGL", course_number: "1010"),
          course(crn: "20002", subject_code: "ENGL", course_number: "1010", days: ["Wednesday"])
        ],
        academic_programs: [
          %{
            "id" => 7,
            "name" => "Math Education",
            "semesters" => [
              %{
                "id" => 11,
                "courses" => [
                  %{"subject_code" => "MATH", "course_number" => "1050"},
                  %{"subject_code" => "ENGL", "course_number" => "1010"}
                ]
              }
            ]
          }
        ]
      )
      |> Enum.filter(&(&1.type == :academic_program_semester))

    assert Enum.map(program_semester_owner.courses, & &1["crn"]) == ["10001", "20002"]
    assert length(program_semester_owner.schedule_variants) == 3
  end

  defp course(opts) do
    %{
      "crn" => Keyword.fetch!(opts, :crn),
      "term_code" => "202777",
      "subject_code" => Keyword.fetch!(opts, :subject_code),
      "course_number" => Keyword.fetch!(opts, :course_number),
      "section_number" => "01",
      "name" => "Test Course",
      "credit_hours" => 3,
      "instructors" => [],
      "meet_info" => [
        %{
          "building" => "Main",
          "building_code" => "MAIN",
          "room" => Keyword.get(opts, :room, "101"),
          "days" => Keyword.get(opts, :days, ["Monday"]),
          "start_time" => Keyword.get(opts, :start_time, "09:00:00"),
          "end_time" => Keyword.get(opts, :end_time, "09:50:00")
        }
      ]
    }
  end
end
