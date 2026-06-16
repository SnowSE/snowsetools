defmodule SnowSeToolsWeb.Plugs.RefreshToken do
  @moduledoc """
  Plug that validates the OIDC access token expiry on each HTTP request.

  If the access token has expired and a refresh token is available, it attempts
  to exchange it for a new access token using the OIDC provider. On success the
  session is updated in-place. On failure (or when no refresh token exists) the
  session is cleared so downstream auth guards redirect the user to login.

  Auth routes (/auth/*) are skipped so that the login flow itself is not
  interrupted.
  """

  import Plug.Conn
  require Logger
  @refresh_before_seconds 60

  def init(opts), do: opts

  # Skip token checks on auth routes to avoid interfering with login/callback/logout.
  def call(%{request_path: "/auth/" <> _} = conn, _opts), do: conn

  def call(conn, _opts) do
    with user_id when not is_nil(user_id) <- get_session(conn, "current_user_id"),
         expires_at when is_integer(expires_at) <- get_session(conn, "session_expires_at"),
         true <- System.system_time(:second) >= expires_at - @refresh_before_seconds do
      ttl = expires_at - System.system_time(:second)

      Logger.info(
        "RefreshToken plug: token expiring in #{ttl}s, attempting refresh path=#{conn.request_path}"
      )

      attempt_refresh(conn)
    else
      _ -> conn
    end
  end

  defp attempt_refresh(conn) do
    refresh_token = get_session(conn, "refresh_token")
    claims = get_session(conn, "oidc_claims")
    oidc_sub = claims && Map.get(claims, "sub")

    if is_binary(refresh_token) and is_binary(oidc_sub) do
      oidc_config = Application.fetch_env!(:snow_se_tools, :oidc)
      client_id = Keyword.fetch!(oidc_config, :client_id)

      case Oidcc.refresh_token(
             refresh_token,
             SnowSeTools.OidcProvider,
             client_id,
             :unauthenticated,
             %{expected_subject: oidc_sub}
           ) do
        {:ok, new_token} ->
          new_expires_at = Map.get(new_token.id.claims, "exp")
          now = System.system_time(:second)

          Logger.info(
            "RefreshToken plug: refresh success sub=#{oidc_sub} new_exp=#{new_expires_at} ttl=#{new_expires_at - now}s"
          )

          %Oidcc.Token.Refresh{token: new_refresh_token} = new_token.refresh

          conn
          |> put_session("session_expires_at", new_expires_at)
          |> put_session("refresh_token", new_refresh_token)

        {:error, reason} ->
          Logger.warning(
            "RefreshToken plug: refresh failed, clearing session sub=#{oidc_sub} reason=#{inspect(reason)}"
          )

          clear_session(conn)
      end
    else
      Logger.info(
        "RefreshToken plug: token expired with no refresh token or sub, clearing session"
      )

      clear_session(conn)
    end
  end
end
