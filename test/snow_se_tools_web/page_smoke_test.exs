defmodule SnowSeToolsWeb.PageSmokeTest do
  @moduledoc """
  Every page, rendered with data actually in it.

  The bug this exists to catch: a database read started answering `{:ok, rows}`,
  one caller kept a catch-all clause binding the whole tuple, and the admin
  page's template then did `for course <- term["courses"]` over it. The LiveView
  died with a Protocol.UndefinedError — red banner, reload, card that could
  never be expanded — and nothing in the suite noticed, because no test rendered
  that page with cached semesters in it.

  So these tests assert two things per page: that it renders at all, and that
  the seeded data reached the markup. A page that renders only its empty state
  passes the first and fails the second, which is the case that hid this bug.
  """
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.AcademicPrograms.{
    CourseAttrs,
    ProgramAttrs,
    ProgramDb,
    ProgramDomainManager,
    SemesterAttrs
  }

  alias SnowSeTools.Discord.{DiscordDb, DiscordDomainManager}
  alias SnowSeTools.Scheduling.{ScheduleChangeDomainManager, ScheduleOwnerDomainManager}
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}
  alias SnowSeTools.UserGroups.UserGroupDomainManager

  @term_name "Smoke Term"
  @course_name "Smoke Data Structures"
  @crn "77001"
  @room "Smoke Hall 101"
  @professor "Smoke Professor"
  @channel "smoke-channel-fall"

  setup do
    term_code = "2028#{System.unique_integer([:positive])}"

    # The suite shares one database, so anything unique-constrained needs a
    # name of its own per test.
    program_name = "Smoke Program #{System.unique_integer([:positive])}"

    seed_courses(term_code)
    seed_discord()
    seed_program(program_name)

    start_supervised!(ProgramDomainManager)
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)
    start_supervised!(UserGroupDomainManager)
    start_supervised!(DiscordDomainManager)

    {:ok, term_code: term_code, program_name: program_name}
  end

  test "the admin page lists cached semesters and expands one to its courses", %{
    conn: conn,
    term_code: term_code
  } do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    html = settle(view)

    assert html =~ @term_name, "the cached semester never reached the page"

    # Courses only render once the card is expanded, which is the click that
    # took the page down: the template iterates term["courses"].
    view
    |> element("#snow-term-#{term_code} button[phx-click='toggle_term']")
    |> render_click()

    html = settle(view)

    assert html =~ @crn, "the semester's courses never reached the expanded card"
    assert html =~ @course_name
  end

  test "the scheduling page draws a schedule", %{conn: conn, term_code: term_code} do
    conn = log_in_admin(conn)
    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")

    settle(view)

    view |> form("#scheduling-search-form") |> render_change(%{"query" => @room})

    view
    |> element("button[phx-click='schedule-owner-search:select'][phx-value-key='room:#{@room}']")
    |> render_click()

    html = settle(view)

    assert html =~ @room
    assert html =~ @course_name
  end

  test "the discord page lists channels", %{conn: conn} do
    html = render_page(conn, ~p"/discord")

    assert html =~ @channel, "the seeded channel never reached the page"
  end

  test "the academic programs page lists programs", %{
    conn: conn,
    term_code: term_code,
    program_name: program_name
  } do
    html = render_page(conn, ~p"/scheduling?mode=programs&term=#{term_code}")

    assert html =~ program_name
  end

  test "the home and syllabi pages render", %{conn: conn} do
    assert render_page(conn, ~p"/home") =~ "Scheduling"
    assert render_page(conn, ~p"/syllabi") =~ "Syllabi"
  end

  defp render_page(conn, path) do
    {:ok, view, _html} = live(log_in_admin(conn), path)
    settle(view)
  end

  # Each page loads through its domain managers; a render taken before those
  # answer is a picture of an empty page, which is how this class of bug hides.
  defp settle(view) do
    for _pass <- 1..3 do
      :ok = ScheduleOwnerDomainManager.await_idle()
      _ = :sys.get_state(SnowCourseCacheDomainManager)
      _ = :sys.get_state(DiscordDomainManager)
      _ = :sys.get_state(ProgramDomainManager)
      _ = :sys.get_state(view.pid)
      render(view)
    end

    render(view)
  end

  defp log_in_admin(conn), do: log_in_user(conn, unique_email("smoke-admin"), ["admin"])

  defp seed_courses(term_code) do
    :ok =
      SnowCourseCacheDb.save_courses(
        term_code: term_code,
        term_name: @term_name,
        courses: [
          %{
            "crn" => @crn,
            "subject_code" => "CS",
            "course_number" => "2420",
            "section_number" => "01",
            "name" => @course_name,
            "credit_hours" => 3,
            "instructors" => [%{"name" => @professor, "primary_instructor" => true}],
            "meet_info" => [
              %{
                "building" => "Smoke Hall",
                "building_code" => "SMK",
                "days" => ["Monday"],
                "start_time" => "09:00",
                "end_time" => "09:50",
                "room" => "101"
              }
            ]
          }
        ]
      )
  end

  defp seed_discord do
    :ok =
      DiscordDb.save_channels(
        channels: [
          %{"id" => "smoke-cat", "name" => "Smoke Courses", "type" => 4, "position" => 1},
          %{
            "id" => "smoke-chan",
            "name" => @channel,
            "type" => 0,
            "parent_id" => "smoke-cat",
            "position" => 1
          }
        ]
      )
  end

  defp seed_program(program_name) do
    {:ok, _program} =
      ProgramDb.create_program(
        program: %ProgramAttrs{
          name: program_name,
          semesters: [
            %SemesterAttrs{courses: [%CourseAttrs{subject_code: "CS", course_number: "2420"}]}
          ]
        }
      )
  end
end
