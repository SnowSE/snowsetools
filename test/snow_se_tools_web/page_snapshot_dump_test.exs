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

  alias SnowSeTools.Curriculum.{AbetDb, CurriculumDomainManager, OutcomeDb, SkillDb, SuggestionDb}
  alias SnowSeTools.Data.User
  alias SnowSeTools.Discord.{DiscordDb, DiscordDomainManager}
  alias SnowSeTools.Scheduling.{ScheduleChangeDomainManager, ScheduleOwnerDomainManager}
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}
  alias SnowSeTools.UserGroups.UserGroupDomainManager
  alias SnowSeToolsWeb.{OnlineUsers, Presence}

  @out "tmp/screens"
  @room "Tanner Building 101"
  @professor "Ada Lovelace"

  setup do
    File.mkdir_p!(@out)

    term_code = "202610"
    seed_courses(term_code)
    seed_program()
    seed_discord()
    seed_other_people_online()

    start_supervised!(ProgramDomainManager)
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)
    start_supervised!(UserGroupDomainManager)
    start_supervised!(DiscordDomainManager)
    start_supervised!(CurriculumDomainManager)

    {:ok, term_code: term_code, curriculum_program: seed_curriculum()}
  end

  # The header's online banner only exists while someone else is on the site.
  defp seed_other_people_online do
    now = System.system_time(:second)
    test_pid = self()

    for {email, path, minutes_on_page} <- [
          {"snapshot-dee@example.com", "/scheduling", 12},
          {"snapshot-ray@example.com", "/syllabi", 3}
        ] do
      {:ok, user} = User.find_or_create(email)

      meta = %{
        email: email,
        path: path,
        page_since: now - minutes_on_page * 60,
        active_at: now
      }

      spawn(fn ->
        {:ok, _ref} = Presence.track(self(), OnlineUsers.topic(), to_string(user.id), meta)
        send(test_pid, :tracked)
        Process.sleep(:infinity)
      end)

      assert_receive :tracked
    end
  end

  test "dump every page", %{conn: conn, term_code: term_code, curriculum_program: curriculum} do
    conn = log_in_user(conn, "snapshot-admin@example.com", ["admin"])

    dump("home", live_html(conn, ~p"/home"))
    dump("syllabi", live_html(conn, ~p"/syllabi"))
    dump("discord", live_html(conn, ~p"/discord"))
    dump("admin", live_html(conn, ~p"/admin"))
    dump("programs", live_html(conn, ~p"/scheduling?mode=programs&term=#{term_code}"))
    dump("scheduling", scheduling_with_cards(conn, term_code))

    program = "program=#{curriculum["id"]}"
    {:ok, git} = SkillDb.find_skill_by_name("Git (command line)")
    dump("curriculum", live_html(conn, "/curriculum?#{program}"))
    dump("curriculum-abet", live_html(conn, "/curriculum?#{program}&tab=abet"))

    dump(
      "curriculum-graph",
      live_html(conn, "/curriculum?#{program}&tab=graph&overlay=skill:#{git["id"]}")
    )

    dump("curriculum-skills", live_html(conn, "/curriculum?#{program}&tab=skills"))
    dump("curriculum-suggestions", live_html(conn, "/curriculum?#{program}&tab=suggestions"))
    dump("curriculum-course", live_html(conn, "/curriculum/courses/SE/3820?#{program}"))

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
      _ = :sys.get_state(CurriculumDomainManager)
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
          course("40103", "Web Development", "CS", "2550", ["Friday"], "10:00", "11:50"),
          # Overlaps Data Structures in the same room, with the same professor:
          # an empty conflicts panel hides every layout problem the real one has.
          course(
            "40104",
            "Discrete Math",
            "CS",
            "2100",
            ["Monday", "Wednesday"],
            "09:30",
            "10:45"
          )
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

  # A small Software Engineering plan with skills that run through it, one
  # out-of-order skill (so the warning shows), master syllabi with
  # prerequisites (so the map has edges), an ABET matrix and a suggestion.
  defp seed_curriculum do
    plan = [
      [{"CS", "1400"}, {"CS", "1410"}],
      [{"CS", "2420"}, {"CS", "2450"}],
      [{"SE", "3630"}, {"SE", "3820"}],
      [{"SE", "4450"}, {"SE", "4620"}]
    ]

    {:ok, program} =
      ProgramDb.create_program(
        program: %ProgramAttrs{
          name: "Software Engineering (snapshot)",
          semesters:
            for semester <- plan do
              %SemesterAttrs{
                courses:
                  for(
                    {subject, number} <- semester,
                    do: %CourseAttrs{subject_code: subject, course_number: number}
                  )
              }
            end
        }
      )

    syllabi = [
      {"CS", "1400", "Fundamentals of Programming", "",
       ["Write simple programs from the command line."]},
      {"CS", "1410", "Object-Oriented Programming", "CS 1400",
       ["Design classes with unit tests."]},
      {"CS", "2420", "Data Structures & Algorithms", "CS 1410",
       ["Analyze algorithms. (ABET SLO 1)"]},
      {"CS", "2450", "Intro to Software Engineering", "CS 1410",
       ["Work in a team using GitHub. (ABET SLO 2)"]},
      {"SE", "3630", "Mobile Application Development", "CS 2450", ["Ship a mobile app."]},
      {"SE", "3820", "Back-End Web Development", "CS 2450 and CS 2420",
       [
         "Upon successful completion of this course students will be able to build HTTP APIs with automated tests. (ABET SLO 2)",
         "Upon successful completion of this course students will be able to apply onion architecture."
       ]},
      {"SE", "4450", "SE Practicum II", "SE 3820",
       ["Deliver a project for a client. (ABET SLO 3, 5)"]},
      {"SE", "4620", "Distributed Application Development", "SE 3820 or SE 3630",
       ["Build distributed systems."]}
    ]

    for {subject, number, title, prerequisites, outcomes} <- syllabi do
      {:ok, _counts} =
        OutcomeDb.save_master_syllabus(
          subject_code: subject,
          course_number: number,
          syllabus: %{
            "title" => "#{subject} #{number} #{title}",
            "prerequisites" => prerequisites,
            "url" => "https://snow.edu/academics/science_math/engineering/se/syllabus.html?q=1",
            "semester_approved" => "Spring 2026",
            "five_year_review" => "Fall 2030",
            "description" => "Snapshot course description.",
            "outcomes" => outcomes
          }
        )
    end

    links = [
      {"Command line",
       [{"CS", "1400", "introduced"}, {"CS", "1410", "reinforced"}, {"SE", "3820", "mastered"}]},
      {"Git (command line)",
       [{"CS", "1410", "introduced"}, {"CS", "2450", "reinforced"}, {"SE", "4450", "mastered"}]},
      {"GitHub",
       [{"CS", "2450", "introduced"}, {"SE", "3630", "reinforced"}, {"SE", "4450", "mastered"}]},
      {".NET SDK CLI", [{"CS", "1410", "introduced"}, {"SE", "3820", "reinforced"}]},
      {"Unit testing",
       [{"CS", "1410", "introduced"}, {"CS", "2420", "reinforced"}, {"SE", "3820", "reinforced"}]},
      {"Test-driven development (TDD)",
       [{"CS", "2450", "introduced"}, {"SE", "3820", "mastered"}]},
      {"Mocks & fakes", [{"SE", "3820", "reinforced"}, {"SE", "4620", "mastered"}]},
      {"Onion architecture", [{"SE", "3820", "introduced"}, {"SE", "4620", "mastered"}]}
    ]

    for {name, course_links} <- links, {subject, number, level} <- course_links do
      {:ok, skill} = SkillDb.find_skill_by_name(name)

      :ok =
        SkillDb.set_course_skill(
          subject_code: subject,
          course_number: number,
          skill_id: skill["id"],
          level: level,
          note: "",
          updated_by: "snapshot"
        )
    end

    {:ok, _counts} =
      AbetDb.import_matrix(
        matrix: %{
          outcomes: [
            %{
              code: "SLO 1",
              kind: "slo",
              number: 1,
              title: "An ability to identify, formulate, and solve complex engineering problems.",
              position: 1
            },
            %{
              code: "SLO 2",
              kind: "slo",
              number: 2,
              title: "An ability to apply engineering design to produce solutions.",
              position: 2
            },
            %{
              code: "PC: Security",
              kind: "criterion",
              number: nil,
              title: "Security",
              position: 100
            }
          ],
          coverage: [
            %{subject_code: "CS", course_number: "2420", code: "SLO 1", tentative: false},
            %{subject_code: "SE", course_number: "4620", code: "SLO 1", tentative: false},
            %{subject_code: "CS", course_number: "2450", code: "SLO 2", tentative: false},
            %{subject_code: "SE", course_number: "4450", code: "SLO 2", tentative: true},
            %{subject_code: "SE", course_number: "4620", code: "PC: Security", tentative: false}
          ]
        },
        meta: %{
          file_name: "B1 ABET_Matrix_2023.xlsx",
          slo_sheet: "Fall2025_Catalog_Matrix",
          criteria_sheet: "Main table",
          imported_by: "snapshot-admin@example.com"
        }
      )

    {:ok, run} =
      SuggestionDb.create_run(
        program_id: program["id"],
        started_by: "snapshot-admin@example.com",
        total_courses: 8
      )

    :ok =
      SuggestionDb.insert_suggestion(
        run_id: run["id"],
        suggestion: %{
          "kind" => "course_skill",
          "subject_code" => "SE",
          "course_number" => "3820",
          "payload" => %{
            "skill_name" => "Docker Compose",
            "skill_id" => nil,
            "category" => "tool",
            "description" => "Running multi-container apps locally.",
            "level" => "introduced"
          },
          "fingerprint" => "course_skill|SE|3820|docker compose|introduced",
          "evidence" => "3820_BackEnd/2026-fall-dallan/modules/M3/docker.md"
        }
      )

    {:ok, _run} =
      SuggestionDb.update_run(
        run_id: run["id"],
        changes: %{
          status: "completed",
          finished_courses: 8,
          notes: ["Faculty repository skipped: CURRICULUM_GITHUB_TOKEN is not set."]
        }
      )

    program
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
