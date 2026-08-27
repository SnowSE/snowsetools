defmodule SnowSeToolsWeb.Scheduling.ScheduleViewerTermPersistenceTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Scheduling.{ScheduleChangeDomainManager, ScheduleOwnerDomainManager}
  alias SnowSeTools.Snow.SnowCourseCacheDb
  alias SnowSeTools.Snow.SnowCourseCacheDomainManager

  setup do
    insert_test_courses()
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)
    :ok
  end

  test "selected term stays in the query string and survives refresh", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=202690")

    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)

    assert has_element?(view, "#scheduling-term-select option[value='202690'][selected]")

    view
    |> element("#scheduling-term-form")
    |> render_change(%{"term_code" => "202590"})

    assert_patch(view, ~p"/scheduling?mode=viewer&term=202590")

    {:ok, refreshed_view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=202590")

    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(refreshed_view)

    assert has_element?(
             refreshed_view,
             "#scheduling-term-select option[value='202590'][selected]"
           )
  end

  defp log_in_test_user(conn),
    do: log_in_user(conn, "schedule-viewer-term-persistence@example.com", ["scheduling_admin"])

  defp insert_test_courses do
    spring_courses = [
      %{
        "crn" => "30001",
        "subject_code" => "CE",
        "course_number" => "2010",
        "section_number" => "Lecture 1",
        "name" => "Statics",
        "instructors" => []
      }
    ]

    fall_courses = [
      %{
        "crn" => "40001",
        "subject_code" => "CE",
        "course_number" => "3020",
        "section_number" => "Lecture 1",
        "name" => "Dynamics",
        "instructors" => []
      }
    ]

    SnowCourseCacheDb.save_courses(
      term_code: "202590",
      term_name: "Spring 2026",
      courses: spring_courses
    )

    SnowCourseCacheDb.save_courses(
      term_code: "202690",
      term_name: "Fall 2026",
      courses: fall_courses
    )
  end
end
