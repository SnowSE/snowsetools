defmodule SnowSeToolsWeb.Admin.SystemDashboardTest do
  # LiveDashboard on the running system shows every process and can kill one,
  # so only admins may open it -- on the first request and on the socket.
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.User
  alias SnowSeToolsWeb.Admin.ProcessStatePage

  setup do
    # The first user ever is made admin; keep that from being one of these.
    {:ok, _bootstrap} = User.find_or_create("system-dashboard-bootstrap@example.com")
    :ok
  end

  describe "who can open it" do
    test "someone not logged in is sent to log in", %{conn: conn} do
      conn = get(conn, "/admin/system/home")
      assert redirected_to(conn) =~ "/auth/login?return_to=%2Fadmin%2Fsystem%2Fhome"
    end

    test "a logged-in user who isn't an admin is turned away", %{conn: conn} do
      conn =
        conn
        |> log_in_user("system-dashboard-editor@example.com", ["scheduling_admin"])
        |> get("/admin/system/home")

      assert redirected_to(conn) == "/home"
    end

    test "nor can they reach it over the socket", %{conn: conn} do
      conn = log_in_user(conn, "system-dashboard-socket@example.com", ["scheduling_admin"])

      assert {:error, {:redirect, %{to: "/home"}}} = live(conn, "/admin/system/home")
    end

    test "an admin can", %{conn: conn} do
      conn = log_in_user(conn, "system-dashboard-admin@example.com", ["admin"])

      {:ok, _view, html} = live(conn, "/admin/system/home")
      assert html =~ "GenServer state"
    end

    test "the Admin page links to it", %{conn: conn} do
      conn = log_in_user(conn, "system-dashboard-link@example.com", ["admin"])

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, ~s(#admin-system-dashboard-link[href="/admin/system"]))
    end
  end

  describe "the GenServer state page" do
    setup %{conn: conn} do
      start_supervised!(%{
        id: :dashboard_state_probe,
        start:
          {Agent, :start_link,
           [fn -> %{probe: "the state held"} end, [name: SnowSeTools.DashboardStateProbe]]}
      })

      %{conn: log_in_user(conn, "system-dashboard-state@example.com", ["admin"])}
    end

    test "lists this app's named processes and shows the state of one", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/system/genserver_state")

      assert render(view) =~ "SnowSeTools.DashboardStateProbe"

      view
      |> element(~s(#process-state-table tr[phx-value-name="SnowSeTools.DashboardStateProbe"]))
      |> render_click()

      assert has_element?(view, "#process-state-value", "the state held")
    end

    test "a name that isn't one of this app's processes is refused, not looked up",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/system/genserver_state")

      render_click(view, "show_state", %{"name" => "Logger"})
      assert has_element?(view, "#process-state-value", "No process is registered")
    end

    test "is listed in the dashboard's menu" do
      assert ProcessStatePage.menu_link(%{}, %{}) == {:ok, "GenServer state"}
    end
  end
end
