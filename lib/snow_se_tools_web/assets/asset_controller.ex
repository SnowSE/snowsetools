defmodule SnowSeToolsWeb.AssetController do
  use SnowSeToolsWeb, :controller

  require Logger

  @upstream_base "https://snow.simplesyllabus.com"

  @id_pattern ~r/^[A-Za-z0-9_-]{1,128}$/

  def account_image(conn, %{"id" => id}) do
    if Regex.match?(@id_pattern, id) do
      proxy_image(conn, id)
    else
      send_resp(conn, 400, "")
    end
  end

  defp proxy_image(conn, id) do
    url = "#{@upstream_base}/ui/account-image/#{id}"

    case Req.get(url, receive_timeout: 8_000) do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
        content_type =
          case Map.get(headers, "content-type") do
            [ct | _] -> ct
            ct when is_binary(ct) -> ct
            _ -> "image/jpeg"
          end

        # Only relay images; never let upstream HTML/JS render on our origin.
        content_type =
          if String.starts_with?(content_type, "image/"), do: content_type, else: "image/jpeg"

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> send_resp(200, body)

      {:ok, %Req.Response{status: status}} ->
        Logger.debug("account_image proxy status=#{status} id=#{id}")
        send_resp(conn, status, "")

      {:error, reason} ->
        Logger.warning("account_image proxy error id=#{id} reason=#{inspect(reason)}")
        send_resp(conn, 502, "")
    end
  end
end
