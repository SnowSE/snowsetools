defmodule SimpleSyllabusReporterWeb.PageController do
  use SimpleSyllabusReporterWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
