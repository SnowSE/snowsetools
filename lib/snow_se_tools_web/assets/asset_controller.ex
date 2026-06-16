defmodule SnowSeToolsWeb.AssetController do
  use SnowSeToolsWeb, :controller

  require Logger

  @upstream_base "https://snow.simplesyllabus.com"

  def account_image(conn, %{"id" => id}) do
    url = "#{@upstream_base}/ui/account-image/#{id}"

    case Req.get(url, receive_timeout: 8_000) do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
        content_type =
          case Map.get(headers, "content-type") do
            [ct | _] -> ct
            ct when is_binary(ct) -> ct
            _ -> "image/jpeg"
          end

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
