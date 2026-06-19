defmodule SnowSeToolsWeb.Scheduling.AcademicProgramEditTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.AcademicPrograms.{
    CourseAttrs,
    ProgramAttrs,
    ProgramDomainManager,
    SemesterAttrs
  }

  alias SnowSeTools.Data.{DbHelpers, User}
  alias SnowSeTools.Snow.SnowCourseCacheDb

  setup do
    start_supervised!(ProgramDomainManager)
    insert_test_courses()

    on_exit(fn ->
      DbHelpers.run_sql(
        "DELETE FROM academic_programs WHERE name = $(name)",
        %{"name" => "Test Program"}
      )
    end)

    :ok
  end

  test "clicking edit on an existing program opens the editor with that program's data", %{
    conn: conn
  } do
    # Create a program via the domain manager so it gets broadcast to the LiveView
    create_program_via_manager(%{name: "Test Program"})

    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=programs")

    # Wait for programs to load via PubSub
    _ = :sys.get_state(ProgramDomainManager)
    render(view)

    # Verify the program appears in the list
    assert has_element?(view, "#academic-program-list", "Test Program")

    # Click on the program in the list to select it
    view
    |> element("#academic-program-list button", "Test Program")
    |> render_click()

    # Verify the display shows the program
    assert has_element?(view, "#academic-program-display-name", "Test Program")

    # Click the edit button on the display
    view
    |> element("#edit-academic-program")
    |> render_click()

    # The editor should be visible and pre-filled with the program's data
    assert has_element?(view, "#academic-program-editor-form")
    assert has_element?(view, "#academic-program-name[value='Test Program']")
  end

  defp log_in_test_user(conn) do
    {:ok, user} = User.find_or_create("academic-program-integration@example.com")
    user_id = Map.get(user, :id) || Map.fetch!(user, "id")

    Plug.Test.init_test_session(conn, %{"current_user_id" => user_id})
  end

  defp insert_test_courses do
    courses = [
      %{
        "crn" => "20001",
        "subject_code" => "CE",
        "course_number" => "2010",
        "section_number" => "Lecture 1",
        "name" => "Statics",
        "instructors" => []
      }
    ]

    SnowCourseCacheDb.save_courses(
      term_code: "202590",
      term_name: "Spring 2026",
      courses: courses
    )
  end

  defp create_program_via_manager(attrs) do
    program_attrs = %ProgramAttrs{
      name: attrs.name,
      semesters: [
        %SemesterAttrs{
          courses: [
            %CourseAttrs{subject_code: "CE", course_number: "2010"}
          ]
        }
      ]
    }

    ProgramDomainManager.create_program(pid: self(), program: program_attrs)
  end
end
