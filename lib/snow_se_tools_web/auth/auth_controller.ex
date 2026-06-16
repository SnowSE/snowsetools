defmodule SnowSeToolsWeb.AuthController do
  use SnowSeToolsWeb, :controller
  require Logger
  alias SnowSeTools.Data.User

  @doc false
  def call(conn, action) do
    try do
      super(conn, action)
    rescue
      e in Oidcc.Plug.Authorize.Error ->
        Logger.error("OIDC authorize failed reason=#{inspect(e.reason)}")

        conn
        |> put_flash(:error, "Login unavailable: #{inspect(e.reason)}")
        |> redirect(to: ~p"/")
        |> halt()
    end
  end

  def client_id,
    do: Application.fetch_env!(:snow_se_tools, :oidc) |> Keyword.fetch!(:client_id)

  def callback_uri(conn) do
    case Application.fetch_env!(:snow_se_tools, :oidc) |> Keyword.get(:redirect_uri) do
      uri when is_binary(uri) ->
        uri

      nil ->
        default_port = URI.default_port(to_string(conn.scheme))
        port_str = if conn.port == default_port, do: "", else: ":#{conn.port}"
        "#{conn.scheme}://#{conn.host}#{port_str}/auth/callback"
    end
  end

  @pkce_profile_opts %{require_pkce: true}

  plug :save_return_to when action in [:authorize]

  plug Oidcc.Plug.Authorize,
       [
         provider: SnowSeTools.OidcProvider,
         client_id: &__MODULE__.client_id/0,
         client_secret: :unauthenticated,
         redirect_uri: &__MODULE__.callback_uri/1,
         client_profile_opts: @pkce_profile_opts,
         scopes: ["openid", "profile", "email"]
       ]
       when action in [:authorize]

  plug Oidcc.Plug.AuthorizationCallback,
       [
         provider: SnowSeTools.OidcProvider,
         client_id: &__MODULE__.client_id/0,
         client_secret: :unauthenticated,
         redirect_uri: &__MODULE__.callback_uri/1,
         client_profile_opts: @pkce_profile_opts,
         preferred_auth_methods: [:none],
         check_peer_ip: false,
         check_useragent: false
       ]
       when action in [:callback]

  def authorize(conn, _params), do: conn

  def callback(
        %Plug.Conn{
          private: %{Oidcc.Plug.AuthorizationCallback => {:ok, {token, userinfo}}}
        } = conn,
        _params
      ) do
    email = Map.get(userinfo, "email")
    token_exp = Map.get(token.id.claims, "exp")
    Logger.info("User login successful email=#{email}")

    refresh_token =
      case token.refresh do
        %Oidcc.Token.Refresh{token: rt} -> rt
        _ -> nil
      end

    case User.find_or_create(email) do
      {:ok, user} ->
        return_to = get_session(conn, "return_to") || "/"

        conn
        |> configure_session(renew: true)
        |> delete_session("return_to")
        |> put_session("oidc_claims", userinfo)
        |> put_session("current_user_id", user.id)
        |> put_session("session_expires_at", token_exp)
        |> put_session("refresh_token", refresh_token)
        |> redirect(to: return_to)

      {:error, reason} ->
        Logger.error("Failed to find_or_create user email=#{email} reason=#{inspect(reason)}")

        conn
        |> put_flash(:error, "Login failed: could not load user profile")
        |> redirect(to: ~p"/")
    end
  end

  def callback(
        %Plug.Conn{
          private: %{Oidcc.Plug.AuthorizationCallback => {:error, reason}}
        } = conn,
        _params
      ) do
    Logger.warning("User login failed reason=#{inspect(reason)}")

    conn
    |> put_status(400)
    |> put_flash(:error, "Login failed: #{inspect(reason)}")
    |> redirect(to: ~p"/")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  def refresh(conn, _params) do
    refresh_token = get_session(conn, "refresh_token")
    claims = get_session(conn, "oidc_claims")
    sub = claims && Map.get(claims, "sub")

    with true <- is_binary(refresh_token) and is_binary(sub),
         {:ok, client_context} <-
           Oidcc.ClientContext.from_configuration_worker(
             SnowSeTools.OidcProvider,
             client_id(),
             :unauthenticated
           ),
         {:ok, new_token} <-
           Oidcc.Token.refresh(refresh_token, client_context, %{expected_subject: sub}) do
      new_exp = Map.get(new_token.id.claims, "exp")

      %Oidcc.Token.Refresh{token: new_refresh} = new_token.refresh
      refresh_reused? = new_refresh == refresh_token
      now = System.system_time(:second)

      Logger.info(
        "auth_controller.refresh success sub=#{sub} new_exp=#{new_exp} ttl=#{new_exp - now}s refresh_token_rotated=#{!refresh_reused?}"
      )

      conn
      |> put_session("session_expires_at", new_exp)
      |> put_session("refresh_token", new_refresh)
      |> json(%{exp: new_exp})
    else
      false ->
        Logger.warning("auth_controller.refresh missing refresh_token or sub, returning 401")
        send_resp(conn, 401, "")

      {:error, reason} ->
        Logger.error(
          "auth_controller.refresh OIDC error sub=#{inspect(sub)} reason=#{inspect(reason)}"
        )

        send_resp(conn, 401, "")
    end
  end

  defp save_return_to(conn, _opts) do
    case conn.params["return_to"] do
      "/" <> _ = path -> put_session(conn, "return_to", path)
      _ -> conn
    end
  end
end
