defmodule SimpleSyllabusReporterWeb.CacheController do
  use SimpleSyllabusReporterWeb, :controller

  def clear(conn, _params) do
    SimpleSyllabusReporter.Cache.clear()

    redirect_path = safe_referer_path(conn) || ~p"/"

    conn
    |> put_flash(:info, "Cache cleared.")
    |> redirect(to: redirect_path)
  end

  defp safe_referer_path(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: path} <- URI.parse(referer),
         true <- host == conn.host do
      path
    else
      _ -> nil
    end
  end
end
