defmodule SimpleSyllabusReporterWeb.PageController do
  use SimpleSyllabusReporterWeb, :controller
  alias SimpleSyllabusReporter.Data.User

  def home(conn, _params) do
    current_user =
      case get_session(conn, "current_user_id") do
        nil ->
          nil

        id ->
          case User.get_by_id(id) do
            {:ok, user} -> user
            _ -> nil
          end
      end

    if current_user do
      redirect(conn, to: "/syllabi")
    else
      render(conn, :home, current_user: current_user)
    end
  end
end
