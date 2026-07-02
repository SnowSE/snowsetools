defmodule SnowSeToolsWeb.Router do
  use SnowSeToolsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
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

  scope "/", SnowSeToolsWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/ui/account-image/:id", AssetController, :account_image
  end

  scope "/", SnowSeToolsWeb do
    pipe_through [:browser, :require_authenticated]

    live "/home", Home.HomeLive
    live "/syllabi", Syllabus.SyllabusLive, :index
    live "/scheduling", Scheduling.SchedulingLive, :index
    live "/discord", Discord.DiscordLive, :index
    live "/admin", Admin.AdminLive
    live "/syllabi/report", Syllabus.SyllabusReportLive
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
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SnowSeToolsWeb.Telemetry
    end
  end

  defp require_authenticated_user(conn, _opts) do
    if get_session(conn, "current_user_id") do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "You must be logged in to access this page.")
      |> Phoenix.Controller.redirect(to: "/auth/login?return_to=#{conn.request_path}")
      |> halt()
    end
  end
end
