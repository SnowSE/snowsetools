defmodule SimpleSyllabusReporterWeb.Router do
  use SimpleSyllabusReporterWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SimpleSyllabusReporterWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_authenticated do
    plug :require_authenticated_user
  end

  scope "/", SimpleSyllabusReporterWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/ui/account-image/:id", AssetController, :account_image
  end

  scope "/", SimpleSyllabusReporterWeb do
    pipe_through [:browser, :require_authenticated]

    live "/syllabi", Syllabus.SyllabusLive
    live "/syllabi/report", Syllabus.SyllabusReportLive
    live "/reports/required-elements", Reports.RequiredElementsLive
    live "/ai/completions", AI.CompletionsHistoryLive
    live "/config", Config.ConfigLive

    post "/cache/clear", CacheController, :clear
  end

  scope "/auth", SimpleSyllabusReporterWeb do
    pipe_through :browser

    get "/login", AuthController, :authorize
    get "/callback", AuthController, :callback
    get "/logout", AuthController, :logout
    get "/refresh", AuthController, :refresh
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:simple_syllabus_reporter, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SimpleSyllabusReporterWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
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
