defmodule SnowSeToolsWeb.PageControllerTest do
  use SnowSeToolsWeb.ConnCase

  test "a visitor who isn't logged in goes straight to the login", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/auth/login?return_to=%2Fhome"
  end

  test "someone logged in goes to their home page", %{conn: conn} do
    conn = conn |> log_in_user("page-controller@example.com") |> get(~p"/")
    assert redirected_to(conn) == "/home"
  end

  test "a failed login is shown, not sent back to the login it failed at", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"phoenix_flash" => %{"error" => "Login failed: :timeout"}})
      |> get(~p"/")

    html = html_response(conn, 200)
    assert html =~ "Login failed: :timeout"
    assert html =~ ~s(id="landing-log-in")
  end

  test "logging out stays logged out, with a way back in", %{conn: conn} do
    conn = conn |> log_in_user("page-controller-logout@example.com") |> get(~p"/auth/logout")
    assert redirected_to(conn) == "/"

    conn = conn |> recycle() |> get(~p"/")

    html = html_response(conn, 200)
    assert html =~ "You&#39;re logged out."
    assert html =~ ~s(id="landing-log-in")
  end
end
