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

  defp build_course(crn, name, days, start_time, end_time) do
    %{
      "crn" => crn,
      "name" => name,
      "subject_code" => "CS",
      "course_number" => crn,
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
