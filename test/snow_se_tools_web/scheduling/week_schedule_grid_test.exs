defmodule SnowSeToolsWeb.Scheduling.WeekScheduleGridTest do
  use SnowSeToolsWeb.ConnCase, async: true

  alias SnowSeTools.Scheduling.ScheduleUtils
  alias SnowSeToolsWeb.Scheduling.WeekScheduleGrid

  test "renders half-hour labels and aligns meetings to the time grid" do
    schedule_owner =
      ScheduleUtils.build_week_schedule(
        type: :academic_program_semester,
        name: "CS:Fall2024",
        courses: [
          build_course("10001", "Intro to CS", ["Monday"], "09:00", "10:30"),
          build_course("10002", "Data Structures", ["Monday"], "11:00", "12:00")
        ]
      )

    html =
      render_component(&WeekScheduleGrid.schedule_grid/1,
        schedule_owner: schedule_owner,
        owner_key: "academic_program_semester:cs-fall2024",
        selected_term_code: "202501",
        active_change_group: nil
      )

    assert html =~ "8:30 AM"
    assert html =~ "9:30 AM"
    assert html =~ "top: 60px; height: 90px"
    assert html =~ "top: 180px; height: 60px"
    assert html =~ "data-week-schedule-course"
    assert html =~ "data-week-schedule-day=\"Monday\""
  end

  test "renders overlapping meetings side by side" do
    schedule_owner =
      ScheduleUtils.build_week_schedule(
        type: :academic_program_semester,
        name: "CS:Fall2024",
        courses: [
          build_course("10001", "Intro to CS", ["Monday"], "09:00", "10:30"),
          build_course("10002", "Data Structures", ["Monday"], "09:30", "10:45"),
          build_course("10003", "Algorithms", ["Monday"], "11:00", "12:00")
        ]
      )

    html =
      render_component(&WeekScheduleGrid.schedule_grid/1,
        schedule_owner: schedule_owner,
        owner_key: "academic_program_semester:cs-fall2024",
        selected_term_code: "202501",
        active_change_group: nil
      )

    style_attributes =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-week-schedule-course]")
      |> LazyHTML.attribute("style")

    assert [
             first_overlapping_style,
             second_overlapping_style,
             non_overlapping_style
           ] = style_attributes

    assert first_overlapping_style =~ "left: 0%; width: calc(50% - 2px)"
    assert second_overlapping_style =~ "left: 50%; width: calc(50% - 2px)"
    assert non_overlapping_style =~ "left: 0%; width: calc(100% - 0px)"
  end

  test "combines same course meetings at the same time into one card with multiple CRNs" do
    schedule_owner =
      ScheduleUtils.build_week_schedule(
        type: :academic_program_semester,
        name: "Math:Fall2024",
        courses: [
          build_course("20001", "College Algebra", ["Monday"], "09:00", "10:00",
            subject_code: "MATH",
            course_number: "101"
          ),
          build_course("20002", "College Algebra", ["Monday"], "09:00", "10:00",
            subject_code: "MATH",
            course_number: "101"
          )
        ]
      )

    html =
      render_component(&WeekScheduleGrid.schedule_grid/1,
        schedule_owner: schedule_owner,
        owner_key: "academic_program_semester:math-fall2024",
        selected_term_code: "202501",
        active_change_group: nil
      )

    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("[data-week-schedule-course]")
           |> LazyHTML.attributes()
           |> length() == 1

    assert LazyHTML.text(document) =~ "2 CRNs: 20001, 20002"

    [style] =
      document
      |> LazyHTML.query("[data-week-schedule-course]")
      |> LazyHTML.attribute("style")

    assert style =~ "left: 0%; width: calc(100% - 0px)"
  end

  test "marks meetings with conflicted CRNs" do
    schedule_owner =
      ScheduleUtils.build_week_schedule(
        type: :academic_program_semester,
        name: "Math:Fall2024",
        courses: [
          build_course("21001", "College Algebra", ["Monday"], "09:00", "10:00",
            subject_code: "MATH",
            course_number: "101"
          ),
          build_course("21002", "College Algebra", ["Monday"], "09:00", "10:00",
            subject_code: "MATH",
            course_number: "101"
          ),
          build_course("21003", "Calculus", ["Monday"], "11:00", "12:00",
            subject_code: "MATH",
            course_number: "201"
          )
        ]
      )

    html =
      render_component(&WeekScheduleGrid.schedule_grid/1,
        schedule_owner: schedule_owner,
        owner_key: "academic_program_semester:math-fall2024",
        selected_term_code: "202501",
        active_change_group: nil,
        conflicted_course_crns: MapSet.new(["21002"]),
        active_conflicted_course_crns: MapSet.new()
      )

    conflicted_attributes =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-week-schedule-course]")
      |> LazyHTML.attribute("data-week-schedule-conflicted")

    assert ["true", "false"] = conflicted_attributes
  end

  test "renders only one card when six meetings of the same course are in the same room" do
    schedule_owner =
      ScheduleUtils.build_week_schedule(
        type: :academic_program_semester,
        name: "BIO:Fall2024",
        courses: [
          build_course("30001", "Intro to Biology", ["Wednesday"], "13:00", "14:30",
            subject_code: "BIO",
            course_number: "101"
          ),
          build_course("30002", "Intro to Biology", ["Wednesday"], "13:00", "14:30",
            subject_code: "BIO",
            course_number: "101"
          ),
          build_course("30003", "Intro to Biology", ["Wednesday"], "13:00", "14:30",
            subject_code: "BIO",
            course_number: "101"
          ),
          build_course("30004", "Intro to Biology", ["Wednesday"], "13:00", "14:30",
            subject_code: "BIO",
            course_number: "101"
          ),
          build_course("30005", "Intro to Biology", ["Wednesday"], "13:00", "14:30",
            subject_code: "BIO",
            course_number: "101"
          ),
          build_course("30006", "Intro to Biology", ["Wednesday"], "13:00", "14:30",
            subject_code: "BIO",
            course_number: "101"
          )
        ]
      )

    html =
      render_component(&WeekScheduleGrid.schedule_grid/1,
        schedule_owner: schedule_owner,
        owner_key: "academic_program_semester:bio-fall2024",
        selected_term_code: "202501",
        active_change_group: nil
      )

    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("[data-week-schedule-course]")
           |> LazyHTML.attributes()
           |> length() == 1

    assert LazyHTML.text(document) =~ "6 CRNs: 30001, 30002, 30003, 30004, 30005, 30006"
  end

  test "combines cross-listed courses with different subject codes into one card" do
    schedule_owner =
      ScheduleUtils.build_week_schedule(
        type: :academic_program_semester,
        name: "ENG:Fall2024",
        courses: [
          build_course("40001", "Digital Circuits", ["Tuesday"], "10:00", "11:30",
            subject_code: "CS",
            course_number: "2700"
          ),
          build_course("40002", "Digital Circuits", ["Tuesday"], "10:00", "11:30",
            subject_code: "ENGR",
            course_number: "2700"
          )
        ]
      )

    html =
      render_component(&WeekScheduleGrid.schedule_grid/1,
        schedule_owner: schedule_owner,
        owner_key: "academic_program_semester:eng-fall2024",
        selected_term_code: "202501",
        active_change_group: nil
      )

    document = LazyHTML.from_fragment(html)

    assert document
           |> LazyHTML.query("[data-week-schedule-course]")
           |> LazyHTML.attributes()
           |> length() == 1

    assert LazyHTML.text(document) =~ "2 CRNs: 40001, 40002"
  end

  defp build_course(crn, name, days, start_time, end_time, opts \\ []) do
    %{
      "crn" => crn,
      "name" => name,
      "subject_code" => Keyword.get(opts, :subject_code, "CS"),
      "course_number" => Keyword.get(opts, :course_number, crn),
      "section_number" => "01",
      "credit_hours" => 3,
      "instructors" => [%{"name" => "Dr. Smith", "primary_instructor" => true}],
      "meet_info" => [
        %{
          "days" => days,
          "start_time" => start_time,
          "end_time" => end_time,
          "room" => "Room 101",
          "building" => nil
        }
      ]
    }
  end
end
