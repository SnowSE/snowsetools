defmodule SimpleSyllabusReporterWeb.Plugs.RefreshToken do
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

  def init(opts), do: opts

  # Skip token checks on auth routes to avoid interfering with login/callback/logout.
  def call(%{request_path: "/auth/" <> _} = conn, _opts), do: conn

  def call(conn, _opts) do
    with user_id when not is_nil(user_id) <- get_session(conn, "current_user_id"),
         expires_at when is_integer(expires_at) <- get_session(conn, "token_expires_at"),
         true <- System.system_time(:second) >= expires_at do
      attempt_refresh(conn)
    else
      _ -> conn
    end
  end

  defp attempt_refresh(conn) do
    refresh_token = get_session(conn, "refresh_token")
    oidc_sub = get_session(conn, "oidc_sub")

    if is_binary(refresh_token) and is_binary(oidc_sub) do
      oidc_config = Application.fetch_env!(:simple_syllabus_reporter, :oidc)
      client_id = Keyword.fetch!(oidc_config, :client_id)

      case Oidcc.refresh_token(
             refresh_token,
             SimpleSyllabusReporter.OidcProvider,
             client_id,
             :unauthenticated,
             %{expected_subject: oidc_sub}
           ) do
        {:ok, new_token} ->
          Logger.info("Refreshed OIDC access token for sub=#{oidc_sub}")

          new_expires_at =
            case new_token.access do
              %{expires: exp} when is_integer(exp) -> exp
              _ -> nil
            end

          new_refresh_token =
            case new_token.refresh do
              %Oidcc.Token.Refresh{token: rt} -> rt
              _ -> refresh_token
            end

          conn
          |> put_session("token_expires_at", new_expires_at)
          |> put_session("refresh_token", new_refresh_token)

        {:error, reason} ->
          Logger.warning("OIDC token refresh failed, clearing session reason=#{inspect(reason)}")
          clear_session(conn)
      end
    else
      # No refresh token or sub claim in session – access token expired with no way
      # to renew. Clear the session; downstream auth guards will redirect to login.
      Logger.info("Access token expired with no refresh token, clearing session")
      clear_session(conn)
    end
  end
end
