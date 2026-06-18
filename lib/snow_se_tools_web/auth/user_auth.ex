defmodule SnowSeToolsWeb.UserAuth do
  import Phoenix.LiveView
  import Phoenix.Component
  require Logger
  alias SnowSeTools.Data.{AccessControl, User}

  def on_mount(:ensure_authenticated, _params, session, socket) do
    user_result = session["current_user_id"] && User.get_by_id(session["current_user_id"])

    case user_result do
      {:ok, user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> schedule_session_refresh(session)
          |> track_current_path()

        {:cont, socket}

      _ ->
        socket =
          socket
          |> put_flash(:error, "Your session has expired. Please log in again.")
          |> redirect(to: "/auth/logout")

        {:halt, socket}
    end
  end

  def on_mount(:ensure_admin, params, session, socket) do
    case on_mount(:ensure_authenticated, params, session, socket) do
      {:cont, socket} ->
        if admin_user?(socket.assigns.current_user) do
          {:cont, socket}
        else
          socket =
            socket
            |> put_flash(:error, "You do not have access to the admin area.")
            |> redirect(to: "/home")

          {:halt, socket}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  # Refresh 60 seconds before expiry. Must be shorter than the token lifetime.
  @refresh_before_seconds 60

  defp track_current_path(%{parent_pid: nil} = socket) do
    attach_hook(socket, :track_current_path, :handle_params, fn _params, url, socket ->
      %{path: path} = URI.parse(url)
      {:cont, assign(socket, :current_path, path)}
    end)
  end

  defp track_current_path(socket), do: socket

  defp schedule_session_refresh(socket, %{"session_expires_at" => exp}) when is_integer(exp) do
    now = System.system_time(:second)
    refresh_at_ms = max((exp - @refresh_before_seconds - now) * 1000, 0)

    if connected?(socket) do
      Logger.info(
        "Scheduling session refresh in #{refresh_at_ms}ms (exp=#{exp}, now=#{now}, ttl=#{exp - now}s)"
      )

      Process.send_after(self(), :session_refresh_soon, refresh_at_ms)
    end

    socket
    |> attach_hook(:session_refresh_info, :handle_info, fn
      :session_refresh_soon, socket ->
        Logger.info("session_refresh_soon fired, pushing session_refresh event to client")
        {:halt, push_event(socket, "session_refresh", %{})}

      _other, socket ->
        {:cont, socket}
    end)
    |> attach_hook(:session_refresh_event, :handle_event, fn
      "session_refreshed", %{"exp" => new_exp}, socket when is_integer(new_exp) ->
        now = System.system_time(:second)
        refresh_at_ms = max((new_exp - @refresh_before_seconds - now) * 1000, 0)

        Logger.info(
          "session_refreshed received exp=#{new_exp} now=#{now} ttl=#{new_exp - now}s next_refresh_in=#{refresh_at_ms}ms"
        )

        Process.send_after(self(), :session_refresh_soon, refresh_at_ms)
        {:halt, socket}

      "session_refreshed", params, socket ->
        Logger.warning("session_refreshed received unexpected params=#{inspect(params)}")
        {:halt, socket}

      _event, _params, socket ->
        {:cont, socket}
    end)
  end

  defp schedule_session_refresh(socket, _session), do: socket

  defp admin_user?(%{id: user_id}) when is_binary(user_id) do
    AccessControl.user_has_group?(user_id: user_id, group_name: "admin")
  end

  defp admin_user?(%{"id" => user_id}) when is_binary(user_id) do
    AccessControl.user_has_group?(user_id: user_id, group_name: "admin")
  end

  defp admin_user?(_), do: false
end
