defmodule SnowSeToolsWeb.Scheduling.AcademicProgramIntegrationTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.AcademicPrograms.ProgramDomainManager
  alias SnowSeTools.Data.User

  setup do
    start_supervised!(ProgramDomainManager)
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

    assert has_element?(view, "#academic-program-display-name", "Civil Engineering")
    assert has_element?(view, "#academic-program-semester-0-course-0", "CE 2010")
  end

  defp log_in_test_user(conn) do
    {:ok, user} = User.find_or_create("academic-program-integration@example.com")
    user_id = Map.get(user, :id) || Map.fetch!(user, "id")

    Plug.Test.init_test_session(conn, %{"current_user_id" => user_id})
  end
end
