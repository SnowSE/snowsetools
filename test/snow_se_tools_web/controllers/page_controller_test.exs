defmodule SnowSeToolsWeb.PageControllerTest do
  use SnowSeToolsWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Snow SE Tools"
  end
end
