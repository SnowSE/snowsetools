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

  describe "the Observer page" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, "system-dashboard-observer@example.com", ["admin"])}
    end

    test "draws the app's supervision tree from its root supervisor", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/system/observer")

      assert has_element?(view, "#observer-svg")
      assert render(view) =~ "SnowSeTools.Supervisor"
      assert render(view) =~ "SnowSeToolsWeb.Endpoint"
      assert has_element?(view, ~s(#observer-svg g[data-type="supervisor"]))
    end

    test "a process's details include the messages waiting in its mailbox", %{conn: conn} do
      # A task that never reads what it is sent, under a supervisor in the tree.
      {:ok, task} =
        Task.Supervisor.start_child(SnowSeTools.TaskSupervisor, fn ->
          receive do
            :stop -> :ok
          end
        end)

      on_exit(fn -> send(task, :stop) end)
      send(task, {:hello_from_the_test, 42})

      {:ok, view, _html} = live(conn, "/admin/system/observer")
      pid = task |> :erlang.pid_to_list() |> List.to_string()

      view |> element(~s([id="observer-node-#{pid}"])) |> render_click()

      assert has_element?(view, "#observer-details", "Message queue")
      assert has_element?(view, "#observer-mailbox", "{:hello_from_the_test, 42}")
    end

    test "reads an OTP process's state on request", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/system/observer")

      pid =
        SnowSeTools.TaskSupervisor
        |> Process.whereis()
        |> :erlang.pid_to_list()
        |> List.to_string()

      view |> element(~s([id="observer-node-#{pid}"])) |> render_click()
      refute has_element?(view, "#observer-state")

      view |> element("#observer-read-state") |> render_click()
      assert has_element?(view, "#observer-state", "DynamicSupervisor")
    end

    test "a big supervisor starts folded and opens on request", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/system/observer")

      # The endpoint's connection pool has dozens of children.
      folded =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(~s(g[id^="observer-toggle-"]))
        |> Enum.find(&(LazyHTML.text(&1) |> String.trim() |> String.starts_with?("+")))

      assert folded, "expected a supervisor with more children than the fold limit"
      [toggle_id] = LazyHTML.attribute(folded, "id")

      view |> element(~s([id="#{toggle_id}"])) |> render_click()
      assert view |> element(~s([id="#{toggle_id}"])) |> render() =~ "−"
    end

    test "ignores a pid that isn't in the tree", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/system/observer")
      stranger = self() |> :erlang.pid_to_list() |> List.to_string()

      render_click(view, "observer_select", %{"pid" => stranger})
      refute has_element?(view, "#observer-details")
    end
  end
end
