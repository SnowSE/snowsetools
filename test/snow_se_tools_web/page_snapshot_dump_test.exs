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

  alias SnowSeTools.Discord.{DiscordDb, DiscordDomainManager}
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
    seed_discord()

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

  # Pages load through their domain managers, so a render before those have
  # answered is a picture of an empty page.
  defp settle(view) do
    for _pass <- 1..3 do
      :ok = ScheduleOwnerDomainManager.await_idle()
      _ = :sys.get_state(DiscordDomainManager)
      _ = :sys.get_state(ProgramDomainManager)
      _ = :sys.get_state(view.pid)
      render(view)
    end

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

  # An empty Discord page hides every layout problem the real one has.
  defp seed_discord do
    :ok =
      DiscordDb.save_channels(
        channels: [
          %{"id" => "cat-1", "name" => "Courses", "type" => 4, "position" => 1},
          %{
            "id" => "chan-1",
            "name" => "cs-2420-data-structures-fall",
            "type" => 0,
            "parent_id" => "cat-1",
            "position" => 1
          },
          %{
            "id" => "chan-2",
            "name" => "cs-3550-operating-systems-fall",
            "type" => 0,
            "parent_id" => "cat-1",
            "position" => 2
          },
          %{
            "id" => "chan-3",
            "name" => "cs-3200-database-design-fall",
            "type" => 0,
            "parent_id" => "cat-1",
            "position" => 3
          },
          %{"id" => "cat-2", "name" => "class of 2030(MAY)", "type" => 4, "position" => 2},
          %{
            "id" => "chan-4",
            "name" => "general-discussion",
            "type" => 0,
            "parent_id" => "cat-2",
            "position" => 1
          }
        ]
      )

    :ok =
      DiscordDb.save_roles(
        roles: [
          %{"id" => "guild-id", "name" => "@everyone", "position" => 0},
          %{"id" => "role-cs2420", "name" => "CS 2420", "position" => 10},
          %{"id" => "role-may30", "name" => "may_30", "position" => 11}
        ]
      )

    :ok =
      DiscordDb.save_members(
        members: [
          %{
            "user" => %{"id" => "u1", "username" => "ada", "global_name" => "Ada Lovelace"},
            "nick" => "Ada",
            "roles" => ["role-cs2420"]
          },
          %{
            "user" => %{"id" => "u2", "username" => "grace", "global_name" => "Grace Hopper"},
            "nick" => nil,
            "roles" => []
          }
        ]
      )
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
