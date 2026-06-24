defmodule SnowSeToolsWeb.Scheduling.AcademicProgramIntegrationTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.AcademicPrograms.ProgramDomainManager
  alias SnowSeTools.Data.User
  alias SnowSeTools.Scheduling.ScheduleOwnerDomainManager
  alias SnowSeTools.Snow.SnowCourseCacheDb

  setup do
    start_supervised!(ProgramDomainManager)
    insert_test_courses()
    start_supervised!(ScheduleOwnerDomainManager)
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

  defp log_in_test_user(conn) do
    {:ok, user} = User.find_or_create("academic-program-integration@example.com")
    user_id = Map.get(user, :id) || Map.fetch!(user, "id")

    Plug.Test.init_test_session(conn, %{"current_user_id" => user_id})
  end

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
