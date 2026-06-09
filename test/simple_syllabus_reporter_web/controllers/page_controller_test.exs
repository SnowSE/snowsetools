defmodule SimpleSyllabusReporterWeb.PageControllerTest do
  use SimpleSyllabusReporterWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Simple Syllabus Reporter"
  end
end
