defmodule SnowSeToolsWeb.Router do
  use SnowSeToolsWeb, :router

  import Phoenix.LiveDashboard.Router

  alias SnowSeTools.Data.{Access, User}

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    # Enforces OIDC token expiry server-side (refreshes or clears the session).
    plug SnowSeToolsWeb.Plugs.RefreshToken
    plug :fetch_live_flash
    plug :put_root_layout, html: {SnowSeToolsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_authenticated do
    plug :require_authenticated_user
  end

  pipeline :require_admin do
    plug :require_admin_user
  end

  scope "/", SnowSeToolsWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", SnowSeToolsWeb do
    pipe_through [:browser, :require_authenticated]

    get "/ui/account-image/:id", AssetController, :account_image

    live "/pending", Auth.PendingLive
    live "/home", Home.HomeLive
    live "/syllabi", Syllabus.SyllabusLive, :index
    live "/scheduling", Scheduling.SchedulingLive, :index
    live "/curriculum", Curriculum.CurriculumLive, :index
    live "/curriculum/courses/:subject/:number", Curriculum.CurriculumLive, :course
    live "/discord", Discord.DiscordLive, :index
    live "/admin", Admin.AdminLive
    live "/syllabi/report", Syllabus.SyllabusReportLive
  end

  # LiveDashboard on the running system, with a page for GenServer state.
  # Admins only: it shows every process and lets you kill one. The plug turns
  # others away on the first request; on_mount does it again when the socket
  # connects, since a LiveView socket does not go through this pipeline.
  scope "/admin" do
    pipe_through [:browser, :require_authenticated, :require_admin]

    live_dashboard "/system",
      metrics: SnowSeToolsWeb.Telemetry,
      live_session_name: :admin_live_dashboard,
      on_mount: [{SnowSeToolsWeb.UserAuth, :ensure_admin}],
      additional_pages: [genserver_state: SnowSeToolsWeb.Admin.ProcessStatePage]
  end

  scope "/auth", SnowSeToolsWeb do
    pipe_through :browser

    get "/login", AuthController, :authorize
    get "/callback", AuthController, :callback
    get "/logout", AuthController, :logout
    get "/refresh", AuthController, :refresh
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:snow_se_tools, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SnowSeToolsWeb.Telemetry
    end
  end

  # No flash on the way out: this redirect lands on the IdP, which never renders
  # a page to show it, so the message would sit in the session and pop up on the
  # first page *after* a successful login. A login that actually fails gets its
  # own flash from AuthController.
  defp require_authenticated_user(conn, _opts) do
    if get_session(conn, "current_user_id") do
      conn
    else
      conn
      |> Phoenix.Controller.redirect(
        to: "/auth/login?" <> URI.encode_query(%{"return_to" => return_to(conn)})
      )
      |> halt()
    end
  end

  defp require_admin_user(conn, _opts) do
    with id when not is_nil(id) <- get_session(conn, "current_user_id"),
         {:ok, user} <- User.get_by_id(id),
         true <- Access.admin?(user) do
      conn
    else
      _not_admin ->
        conn
        |> Phoenix.Controller.put_flash(:error, "You do not have access to that area.")
        |> Phoenix.Controller.redirect(to: "/home")
        |> halt()
    end
  end

  # The query string is part of where they were going: /scheduling carries the
  # term and the saved layout there, and a link that loses it lands on a
  # different page than the one that was shared.
  defp return_to(%{query_string: ""} = conn), do: conn.request_path
  defp return_to(conn), do: "#{conn.request_path}?#{conn.query_string}"
end
