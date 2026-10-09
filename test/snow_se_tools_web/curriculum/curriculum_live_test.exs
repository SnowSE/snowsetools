defmodule SnowSeToolsWeb.CurriculumLiveTest do
  @moduledoc """
  The curriculum pages with data in them, as a viewer and as an editor, plus
  review runs against a stubbed snow.edu (the AI is mocked in test and answers
  with nothing, so a full run ends with no suggestions).
  """
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.AcademicPrograms.{CourseAttrs, ProgramAttrs, ProgramDb, SemesterAttrs}

  alias SnowSeTools.Curriculum.{
    CurriculumDomainManager,
    CurriculumPubSub,
    OutcomeDb,
    SkillDb,
    SuggestionDb
  }

  @fixtures Path.expand("../../fixtures/curriculum", __DIR__)

  setup do
    start_supervised!(CurriculumDomainManager)

    tag = System.unique_integer([:positive])
    first = Integer.to_string(1000 + rem(tag, 4000))
    second = Integer.to_string(5000 + rem(tag, 4000))

    {:ok, program} =
      ProgramDb.create_program(
        program: %ProgramAttrs{
          name: "Curriculum Program #{tag}",
          semesters: [
            %SemesterAttrs{courses: [%CourseAttrs{subject_code: "QZ", course_number: first}]},
            %SemesterAttrs{courses: [%CourseAttrs{subject_code: "QZ", course_number: second}]}
          ]
        }
      )

    {:ok, _counts} =
      OutcomeDb.save_master_syllabus(
        subject_code: "QZ",
        course_number: second,
        syllabus: %{
          "title" => "QZ #{second} Testing Practices",
          "prerequisites" => "QZ #{first} w/ a minimum grade of C-",
          "outcomes" => [
            "Upon successful completion of this course students will be able to write tests before code. (ABET SLO 2)"
          ]
        }
      )

    {:ok, skill} =
      SkillDb.create_skill(name: "Fixture skill #{tag}", category: "practice", description: "d")

    for {number, level} <- [{first, "introduced"}, {second, "mastered"}] do
      :ok =
        SkillDb.set_course_skill(
          subject_code: "QZ",
          course_number: number,
          skill_id: skill["id"],
          level: level,
          note: "",
          updated_by: "test"
        )
    end

    {:ok, program: program, skill: skill, first: first, second: second, tag: tag}
  end

  defp viewer(conn), do: log_in_user(conn, unique_email("viewer"), ["scheduling_view"])
  defp editor(conn), do: log_in_user(conn, unique_email("editor"), ["curriculum_admin"])

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    settle(view)
    view
  end

  # The page asks the manager for the map and gets it back as a message; an
  # edit goes to the manager, which broadcasts, and the page asks again. A few
  # rounds of waiting on both processes covers that whole exchange.
  defp settle(view) do
    for _round <- 1..3 do
      _ = :sys.get_state(CurriculumDomainManager)
      _ = :sys.get_state(view.pid)
    end

    render(view)
  end

  test "any approved user can read the skill threads",
       %{conn: conn, program: program, skill: skill, second: second} do
    view = open(viewer(conn), ~p"/curriculum?program=#{program["id"]}")

    assert has_element?(view, "#thread-#{skill["id"]}")
    assert has_element?(view, "#skill-threads thead a", "QZ #{second}")
  end

  test "a user waiting for approval cannot open it", %{conn: conn} do
    conn = log_in_user(conn, unique_email("pending"))
    assert {:error, {:redirect, %{to: "/pending"}}} = live(conn, ~p"/curriculum")
  end

  test "a viewer's edit is refused", %{conn: conn, program: program, skill: skill} do
    view = open(viewer(conn), ~p"/curriculum?program=#{program["id"]}&tab=skills")

    render_hook(view, "curriculum-edit:delete_skill", %{"id" => skill["id"]})

    assert has_element?(view, "#flash-error", "view-only access")
    assert {:ok, _still_there} = SkillDb.find_skill_by_name(skill["name"])
  end

  test "the course page shows outcomes, ABET tags and where a skill comes from",
       %{conn: conn, program: program, skill: skill, first: first, second: second} do
    view = open(viewer(conn), ~p"/curriculum/courses/QZ/#{second}?program=#{program["id"]}")

    assert has_element?(view, "#course-outcomes li", "Write tests before code.")
    refute has_element?(view, "#course-outcomes li", "Upon successful completion")
    assert has_element?(view, "#course-outcomes li span", "ABET SLO 2")
    assert has_element?(view, "#course-skill-#{skill["id"]} a", "QZ #{first}")
  end

  test "an editor links a skill to a course",
       %{conn: conn, program: program, first: first, tag: tag} do
    {:ok, other} =
      SkillDb.create_skill(name: "Linkable #{tag}", category: "tool", description: "")

    view = open(editor(conn), ~p"/curriculum/courses/QZ/#{first}?program=#{program["id"]}")

    view
    |> form("#add-course-skill", %{
      "link" => %{"skill_id" => other["id"], "level" => "reinforced", "note" => "lab 2"}
    })
    |> render_submit()

    settle(view)
    assert has_element?(view, "#course-skill-#{other["id"]}")
  end

  test "an editor accepts a suggestion", %{conn: conn, program: program, first: first, tag: tag} do
    name = "Suggested skill #{tag}"

    {:ok, run} =
      SuggestionDb.create_run(program_id: program["id"], started_by: "test", total_courses: 1)

    :ok =
      SuggestionDb.insert_suggestion(
        run_id: run["id"],
        suggestion: %{
          "kind" => "course_skill",
          "subject_code" => "QZ",
          "course_number" => first,
          "payload" => %{
            "skill_name" => name,
            "skill_id" => nil,
            "category" => "tool",
            "description" => "",
            "level" => "introduced"
          },
          "fingerprint" => "course_skill|QZ|#{first}|#{String.downcase(name)}|introduced",
          "evidence" => "week 1"
        }
      )

    {:ok, pending} = SuggestionDb.list_pending()
    suggestion = Enum.find(pending, &(&1["payload"]["skill_name"] == name))

    view = open(editor(conn), ~p"/curriculum?program=#{program["id"]}&tab=suggestions")
    view |> form("#suggestion-#{suggestion["id"]}") |> render_submit()
    settle(view)

    assert {:ok, _skill} = SkillDb.find_skill_by_name(name)
    refute has_element?(view, "#suggestion-#{suggestion["id"]}")
  end

  test "the prerequisite map draws the edge and highlights a skill",
       %{conn: conn, program: program, skill: skill, first: first, second: second} do
    view =
      open(
        viewer(conn),
        ~p"/curriculum?program=#{program["id"]}&tab=graph&overlay=skill:#{skill["id"]}"
      )

    assert has_element?(view, "#graph-node-QZ-#{first}")

    assert has_element?(
             view,
             "#prerequisite-graph path title",
             "QZ #{first} is a prerequisite of QZ #{second}"
           )

    assert has_element?(view, "#graph-node-QZ-#{second} title", "mastered")
  end

  test "an editor imports the ABET matrix and sees the syllabus tag beside it",
       %{conn: conn, program: program, second: second} do
    view = open(editor(conn), ~p"/curriculum?program=#{program["id"]}&tab=abet")

    upload =
      file_input(view, "#abet-upload-form", :abet_matrix, [
        %{
          name: "abet_matrix_sample.xlsx",
          content: File.read!(Path.join(@fixtures, "abet_matrix_sample.xlsx")),
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
      ])

    render_upload(upload, "abet_matrix_sample.xlsx")
    settle(view)
    assert has_element?(view, "#abet-preview", "3 student outcomes, 2 program criteria")

    view |> form("#abet-sheets-form") |> render_submit()
    settle(view)

    assert has_element?(view, "#abet-pc-computing-fundamentals")

    assert has_element?(
             view,
             ~s(#abet-slo-2 span[title="QZ #{second}: the matrix does not mark it; its master syllabus tags it"])
           )
  end

  describe "a review run" do
    setup %{second: second} do
      Req.Test.set_req_test_to_shared(%{})
      previous = Application.get_env(:snow_se_tools, :curriculum_req_options)
      Application.put_env(:snow_se_tools, :curriculum_req_options, plug: {Req.Test, __MODULE__})

      course_page = File.read!(Path.join(@fixtures, "course_se3140.html"))
      syllabus_page = File.read!(Path.join(@fixtures, "master_syllabus_se3140.html"))

      Req.Test.stub(__MODULE__, fn conn ->
        case conn.request_path do
          # The faculty repository is only read when CURRICULUM_GITHUB_TOKEN is
          # set, so without this clause the suite passes on a machine with no
          # token and hangs on one that has it: the unmatched path crashes the
          # task that enqueues the reviews, and the run waits forever.
          "/repos/SnowSE/faculty/git/trees/HEAD" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, ~s({"tree": []}))

          "/academics/science_math/engineering/se/course.html" ->
            if conn.query_string =~ "crse_numb=#{second}",
              do: Plug.Conn.send_resp(conn, 200, course_page),
              else: Plug.Conn.send_resp(conn, 200, "<html><h1></h1></html>")

          "/academics/science_math/engineering/se/syllabus.html" ->
            Plug.Conn.send_resp(conn, 200, syllabus_page)
        end
      end)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:snow_se_tools, :curriculum_req_options, previous),
          else: Application.delete_env(:snow_se_tools, :curriculum_req_options)
      end)

      CurriculumPubSub.subscribe()
      :ok
    end

    test "re-reads the master syllabi and reports the course it could not read",
         %{conn: conn, program: program, first: first, second: second} do
      program_id = program["id"]
      view = open(editor(conn), ~p"/curriculum?program=#{program_id}&tab=suggestions")

      view |> element("#start-syllabi-only") |> render_click()

      assert_receive {:curriculum,
                      {:run, %{running?: false, run: %{"program_id" => ^program_id}}}},
                     5_000

      {:ok, syllabi} = OutcomeDb.list_master_syllabi()
      read = Enum.find(syllabi, &(&1["course_number"] == second))
      failed = Enum.find(syllabi, &(&1["course_number"] == first))

      assert read["title"] == "SE 3140 Ethics and Craftsmanship"
      assert failed["fetch_error"] =~ "no master syllabus"

      settle(view)
      assert has_element?(view, "#last-run li", "QZ #{first}: master syllabus not read")
    end

    test "a full run reviews every course and finishes", %{conn: conn, program: program} do
      program_id = program["id"]
      view = open(editor(conn), ~p"/curriculum?program=#{program_id}&tab=suggestions")

      view |> element("#start-review") |> render_click()

      assert_receive {:curriculum,
                      {:run,
                       %{
                         running?: false,
                         run: %{"program_id" => ^program_id, "status" => "completed"} = run
                       }}},
                     5_000

      assert run["finished_courses"] == 2
    end

    test "a course with nothing to read is reported rather than sent to the model",
         %{conn: conn, program: program} do
      program_id = program["id"]
      view = open(editor(conn), ~p"/curriculum?program=#{program_id}&tab=suggestions")

      view |> element("#start-review") |> render_click()

      assert_receive {:curriculum,
                      {:run,
                       %{
                         running?: false,
                         run: %{"program_id" => ^program_id, "status" => "completed"} = run
                       }}},
                     5_000

      assert Enum.any?(run["notes"], &(&1 =~ "not reviewed — no faculty materials"))

      # The run finishes when every course has reported once. A skipped course
      # still has to count, or the run waits forever for an answer that was
      # never asked for.
      assert run["finished_courses"] == 2
    end
  end
end
