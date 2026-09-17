defmodule SnowSeToolsWeb.PageSnapshotDumpTest do
  @moduledoc """
  Not a test: a way to look at the pages.

  Writes the real rendered HTML of each page to tmp/screens so a headless
  browser can open it at a phone width with the production stylesheet. Excluded
  from the suite; run it deliberately:

      mix test --only snapshot test/snow_se_tools_web/page_snapshot_dump_test.exs
  """
  use SnowSeToolsWeb.ConnCase, async: false

  @moduletag :snapshot

  alias SnowSeTools.AcademicPrograms.{
    CourseAttrs,
    ProgramAttrs,
    ProgramDb,
    ProgramDomainManager,
    SemesterAttrs
  }

  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeTools.Scheduling.{ScheduleChangeDomainManager, ScheduleOwnerDomainManager}
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}
  alias SnowSeTools.UserGroups.UserGroupDomainManager

  @out "tmp/screens"
  @room "Tanner Building 101"
  @professor "Ada Lovelace"

  setup do
    File.mkdir_p!(@out)

    term_code = "202610"
    seed_courses(term_code)
    seed_program()

    start_supervised!(ProgramDomainManager)
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)
    start_supervised!(UserGroupDomainManager)
    start_supervised!(DiscordDomainManager)

    {:ok, term_code: term_code}
  end

  test "dump every page", %{conn: conn, term_code: term_code} do
    conn = log_in_user(conn, "snapshot-admin@example.com", ["admin"])

    dump("home", live_html(conn, ~p"/home"))
    dump("syllabi", live_html(conn, ~p"/syllabi"))
    dump("discord", live_html(conn, ~p"/discord"))
    dump("admin", live_html(conn, ~p"/admin"))
    dump("programs", live_html(conn, ~p"/scheduling?mode=programs&term=#{term_code}"))
    dump("scheduling", scheduling_with_cards(conn, term_code))

    assert File.ls!(@out) != []
  end

  defp live_html(conn, path) do
    {:ok, view, _html} = live(conn, path)
    settle(view)
  end

  # The interesting scheduling page is one with schedules open on it.
  defp scheduling_with_cards(conn, term_code) do
    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")

    :ok = ScheduleOwnerDomainManager.await_idle()
    render(view)

    for owner <- ["room:#{@room}", "professor:#{@professor}"] do
      query = owner |> String.split(":", parts: 2) |> List.last()

      view |> form("#scheduling-search-form") |> render_change(%{"query" => query})

      view
      |> element("button[phx-click='schedule-owner-search:select'][phx-value-key='#{owner}']")
      |> render_click()
    end

    settle(view)
  end

  defp settle(view) do
    :ok = ScheduleOwnerDomainManager.await_idle()
    _ = :sys.get_state(view.pid)
    render(view)
    :ok = ScheduleOwnerDomainManager.await_idle()
    _ = :sys.get_state(view.pid)
    render(view)
  end

  defp dump(name, html) do
    File.write!(Path.join(@out, "#{name}.html"), html)
  end

  defp seed_courses(term_code) do
    :ok =
      SnowCourseCacheDb.save_courses(
        term_code: term_code,
        term_name: "Spring 2026",
        courses: [
          course(
            "40100",
            "Data Structures",
            "CS",
            "2420",
            ["Monday", "Wednesday"],
            "09:00",
            "10:15"
          ),
          course(
            "40101",
            "Operating Systems",
            "CS",
            "3550",
            ["Tuesday", "Thursday"],
            "11:00",
            "12:15"
          ),
          course(
            "40102",
            "Database Design",
            "CS",
            "3200",
            ["Monday", "Wednesday"],
            "13:00",
            "14:15"
          ),
          course("40103", "Web Development", "CS", "2550", ["Friday"], "10:00", "11:50")
        ]
      )
  end

  defp course(crn, name, subject, number, days, start_time, end_time) do
    %{
      "crn" => crn,
      "subject_code" => subject,
      "course_number" => number,
      "section_number" => "01",
      "name" => name,
      "credit_hours" => 3,
      "instructors" => [%{"name" => @professor, "primary_instructor" => true}],
      "meet_info" => [
        %{
          "building" => "Tanner Building",
          "building_code" => "TB",
          "days" => days,
          "start_time" => start_time,
          "end_time" => end_time,
          "room" => "101"
        }
      ]
    }
  end

  defp seed_program do
    {:ok, _program} =
      ProgramDb.create_program(
        program: %ProgramAttrs{
          name: "Computer Science",
          semesters: [
            %SemesterAttrs{
              courses: [
                %CourseAttrs{subject_code: "CS", course_number: "2420"},
                %CourseAttrs{subject_code: "CS", course_number: "3550"}
              ]
            }
          ]
        }
      )
  end
end
