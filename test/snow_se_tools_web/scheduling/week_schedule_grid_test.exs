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
