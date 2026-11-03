defmodule SnowSeToolsWeb.Scheduling.AcademicProgramIntegrationTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.AcademicPrograms.ProgramDomainManager
  alias SnowSeTools.Scheduling.{ScheduleChangeDomainManager, ScheduleOwnerDomainManager}
  alias SnowSeTools.Snow.SnowCourseCacheDomainManager
  alias SnowSeTools.Snow.SnowCourseCacheDb

  setup do
    start_supervised!(ProgramDomainManager)
    insert_test_courses()
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)
    :ok
  end

  test "a user can create and view an academic program", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=programs")

    assert has_element?(view, "#academic-programs-panel")
    assert has_element?(view, "#new-program-from-list")

    view
    |> element("#new-program-from-list")
    |> render_click()

    assert has_element?(view, "#academic-program-editor-form")

    view
    |> form("#academic-program-editor-form", %{"name" => "Civil Engineering"})
    |> render_change()

    view
    |> element("#program-course-input-0-0")
    |> render_change(%{"value" => "CE 2010"})

    view
    |> element("#save-academic-program")
    |> render_click()

    _ = :sys.get_state(ProgramDomainManager)
    _html = render(view)

    assert view |> has_element?("#academic-program-display-name")
    assert has_element?(view, "#academic-program-display-name", "Civil Engineering")
    assert has_element?(view, "#academic-program-semester-0-course-0", "CE 2010")
  end

  test "keyboard navigation selects course and generates new focused field", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=programs")

    # Open program editor
    view |> element("#new-program-from-list") |> render_click()
    assert has_element?(view, "#academic-program-editor-form")

    # Focus the input and type partial course code to trigger suggestions
    input = element(view, "#program-course-input-0-0")
    render_focus(input)
    render_change(input, %{"value" => "CE"})

    # Verify suggestions dropdown appeared with CE courses
    assert has_element?(view, "#program-course-suggestions-0-0")
    assert has_element?(view, "#program-course-suggestion-0-0-0")

    # Navigate down with arrow key to highlight first suggestion
    view |> element("#program-course-input-0-0") |> render_keydown(%{"key" => "ArrowDown"})

    assert has_element?(view, "#program-course-suggestion-0-0-0.bg-slate-900")

    # Press Enter to select the highlighted suggestion
    view |> element("#program-course-input-0-0") |> render_keydown(%{"key" => "Enter"})
    _ = :sys.get_state(ProgramDomainManager)

    _html = render(view)

    # Verify a new empty course field (index 1) was created
    assert has_element?(view, "#program-course-input-0-1")

    # Verify the selected course value is in the first field
    assert has_element?(view, "#program-course-input-0-0[value^='CE']")
  end

  test "clicking a suggestion selects course and generates new focused field", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=programs")

    # Open program editor
    view |> element("#new-program-from-list") |> render_click()
    assert has_element?(view, "#academic-program-editor-form")

    # Focus the input and type partial course code to trigger suggestions
    input = element(view, "#program-course-input-0-0")
    render_focus(input)
    render_change(input, %{"value" => "CE"})

    # Verify suggestions dropdown appeared with CE courses
    assert has_element?(view, "#program-course-suggestions-0-0")
    assert has_element?(view, "#program-course-suggestion-0-0-0")

    # Click the first suggestion to select it
    view |> element("#program-course-suggestion-0-0-0") |> render_click()
    _ = :sys.get_state(ProgramDomainManager)

    _html = render(view)

    # Verify the selected course value is in the first field (not just the typed prefix)
    assert has_element?(view, "#program-course-matched-label-0-0", "Statics")

    # Verify a new empty course field (index 1) was created
    assert has_element?(view, "#program-course-input-0-1")
  end

  test "creating a new change group displays it in the list", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling")

    assert has_element?(view, "#schedule-change-groups")

    # Click "+ New" to show the name input form
    view
    |> element("button[phx-click='schedule-change-groups:new_group']")
    |> render_click()

    assert has_element?(view, "form[phx-submit='schedule-change-groups:save_new']")

    # Type a group name and save
    view
    |> form("form[phx-submit='schedule-change-groups:save_new']", %{"name" => "My Test Group"})
    |> render_submit()

    _ = :sys.get_state(SnowSeTools.Scheduling.ScheduleChangeDomainManager)
    _html = render(view)

    # The new group should appear in the list
    assert has_element?(view, "#schedule-change-groups", "My Test Group")

    # The new group should be selected (active)
    state = :sys.get_state(view.pid)
    change_groups_state = state.socket.assigns.schedule_change_groups_state
    assert change_groups_state.active_change_group_id
    assert change_groups_state.active_change_group["name"] == "My Test Group"
  end

  describe "reviewing a program's schedule conflicts" do
    setup do
      program =
        create_program([
          [%{subject_code: "CE", course_number: "2010"}],
          [%{subject_code: "CE", course_number: "3020"}],
          [%{subject_code: "MATH", course_number: "1010"}]
        ])

      # Something else to have on the canvas as unsaved work.
      other = create_program([[%{subject_code: "CE", course_number: "2010"}]])

      %{program: program, other_key: semester_keys(other) |> hd()}
    end

    test "on an empty canvas, opens every semester in order without asking",
         %{conn: conn, program: program} do
      view = open_programs_tab(conn)

      review(view, program)

      # The program param is consumed and dropped, leaving a plain viewer URL,
      # so a reload keeps whatever is arranged afterwards.
      assert_patch(view, ~p"/scheduling?mode=viewer&term=202590")
      refute has_element?(view, "#schedule-program-choice")
      assert canvas_keys(view) == semester_keys(program)
      assert render(view) =~ "Opened 3 semesters of #{program["name"]}"
    end

    test "with unsaved work, asks first and touches nothing until answered",
         %{conn: conn, program: program, other_key: other_key} do
      view = open_programs_tab(conn)
      put_on_canvas(view, other_key)

      review(view, program)

      assert has_element?(view, "#schedule-program-choice", program["name"])
      assert has_element?(view, "#schedule-program-choice", "hasn't been saved")
      assert canvas_keys(view) == [other_key]
    end

    test "choosing add keeps the work and puts the semesters after it",
         %{conn: conn, program: program, other_key: other_key} do
      view = open_programs_tab(conn)
      put_on_canvas(view, other_key)
      review(view, program)

      view |> element("#schedule-program-choice-add") |> render_click()

      refute has_element?(view, "#schedule-program-choice")
      assert canvas_keys(view) == [other_key | semester_keys(program)]
      assert render(view) =~ "Added 3 semesters of #{program["name"]} to your layout"
    end

    test "choosing add skips semesters already on the canvas",
         %{conn: conn, program: program} do
      [first | rest] = semester_keys(program)
      view = open_programs_tab(conn)
      put_on_canvas(view, first)
      review(view, program)

      view |> element("#schedule-program-choice-add") |> render_click()

      assert canvas_keys(view) == [first | rest]
      assert render(view) =~ "Added 2 semesters"
    end

    test "choosing replace swaps the work for the program",
         %{conn: conn, program: program, other_key: other_key} do
      view = open_programs_tab(conn)
      put_on_canvas(view, other_key)
      review(view, program)

      view |> element("#schedule-program-choice-replace") |> render_click()

      assert canvas_keys(view) == semester_keys(program)
    end

    test "cancelling leaves the canvas exactly as it was",
         %{conn: conn, program: program, other_key: other_key} do
      view = open_programs_tab(conn)
      put_on_canvas(view, other_key)
      review(view, program)

      view |> element("#schedule-program-choice-cancel") |> render_click()

      refute has_element?(view, "#schedule-program-choice")
      assert canvas_keys(view) == [other_key]
    end

    test "a link waits for the remembered canvas, then asks rather than overwriting it",
         %{conn: conn, program: program, other_key: other_key} do
      conn = log_in_test_user(conn)

      {:ok, view, _html} =
        live(conn, ~p"/scheduling?mode=viewer&term=202590&program=#{program["id"]}")

      _ = render(view)
      assert canvas_keys(view) == []

      # What the browser reports from localStorage once the hook mounts.
      render_hook(view, "schedule-layouts:session_read", %{
        "session" => %{
          "term_code" => "202590",
          "entries" => [%{"kind" => "owner", "key" => other_key}],
          "loaded" => nil,
          "baseline" => nil
        }
      })

      assert canvas_keys(view) == [other_key]
      assert has_element?(view, "#schedule-program-choice")
    end

    test "a link with nothing remembered opens the semesters straight away",
         %{conn: conn, program: program} do
      conn = log_in_test_user(conn)

      {:ok, view, _html} =
        live(conn, ~p"/scheduling?mode=viewer&term=202590&program=#{program["id"]}")

      render_hook(view, "schedule-layouts:session_read", %{"session" => nil})

      refute has_element?(view, "#schedule-program-choice")
      assert canvas_keys(view) == semester_keys(program)
    end
  end

  defp create_program(semesters) do
    {:ok, attrs} =
      SnowSeTools.AcademicPrograms.ProgramAttrs.parse(%{
        name: "Conflict Review #{System.unique_integer([:positive])}",
        semesters: Enum.map(semesters, &%{courses: &1})
      })

    ProgramDomainManager.create_program(pid: self(), program: attrs)
    assert_receive {:academic_programs, {:action_result, {:ok, _message, program}}}
    # Let the schedule owners pick up the new program's semesters.
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    program
  end

  defp semester_keys(program) do
    Enum.map(program["semesters"], fn semester ->
      "academic_program_semester:#{program["id"]}:#{semester["id"]}"
    end)
  end

  defp open_programs_tab(conn) do
    conn = log_in_test_user(conn)
    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=programs&term=202590")
    # The program list arrives as a message once the view has connected, and
    # the browser hook reports that it remembers no canvas.
    _ = :sys.get_state(ProgramDomainManager)
    render_hook(view, "schedule-layouts:session_read", %{"session" => nil})
    view
  end

  defp put_on_canvas(view, key),
    do: render_click(view, "schedule-details-order:toggle", %{"key" => key})

  defp review(view, program) do
    view |> element("#academic-program-#{program["id"]}") |> render_click()
    view |> element("#review-program-schedule-conflicts") |> render_click()
  end

  defp canvas_keys(view) do
    :sys.get_state(view.pid).socket.assigns.schedule_details_order
    |> SnowSeToolsWeb.Scheduling.ScheduleDetailsOrder.to_layout_entries()
    |> Enum.flat_map(fn
      %{"kind" => "overlay", "members" => members} -> members
      %{"key" => key} -> [key]
    end)
  end

  defp log_in_test_user(conn),
    do: log_in_user(conn, "academic-program-integration@example.com", ["scheduling_admin"])

  defp insert_test_courses do
    courses = [
      %{
        "crn" => "10001",
        "subject_code" => "CE",
        "course_number" => "2010",
        "section_number" => "Lecture 1",
        "name" => "Statics",
        "instructors" => []
      },
      %{
        "crn" => "10002",
        "subject_code" => "CE",
        "course_number" => "3020",
        "section_number" => "Lecture 1",
        "name" => "Dynamics",
        "instructors" => []
      },
      %{
        "crn" => "10003",
        "subject_code" => "MATH",
        "course_number" => "1010",
        "section_number" => "Lecture 1",
        "name" => "Calculus I",
        "instructors" => []
      }
    ]

    SnowCourseCacheDb.save_courses(
      term_code: "202590",
      term_name: "Spring 2026",
      courses: courses
    )
  end
end
