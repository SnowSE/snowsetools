defmodule SnowSeToolsWeb.Syllabus.SyllabusLiveTest do
  use SnowSeToolsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SnowSeTools.Data.User

  setup do
    {:ok, user} = User.find_or_create("syllabus-live-test@example.com")

    %{user: user}
  end

  test "restores the selected mode from the query string", %{conn: conn, user: user} do
    conn = init_test_session(conn, current_user_id: user.id)

    {:ok, view, _html} = live(conn, "/syllabi?mode=settings")

    assert has_element?(view, "#tab-settings.text-indigo-300")
    refute has_element?(view, "#tab-search.text-indigo-300")
  end

  test "updates the mode in the query string when switching tabs", %{conn: conn, user: user} do
    conn = init_test_session(conn, current_user_id: user.id)

    {:ok, view, _html} = live(conn, "/syllabi")

    render_click(element(view, "#tab-ai_history"))

    assert_patch(view, "/syllabi?mode=ai_history")
  end
end
