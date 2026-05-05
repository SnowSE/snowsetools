defmodule SimpleSyllabusReporterWeb.UserAuth do
  import Phoenix.LiveView
  import Phoenix.Component
  alias SimpleSyllabusReporter.Data.User

  def on_mount(:ensure_authenticated, _params, session, socket) do
    user_result =
      if session_expired?(session) do
        :expired
      else
        session["current_user_id"] && User.get_by_id(session["current_user_id"])
      end

    case user_result do
      {:ok, user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> schedule_session_refresh(session)

        {:cont, socket}

      _ ->
        socket =
          socket
          |> put_flash(:error, "Your session has expired. Please log in again.")
          |> redirect(to: "/auth/logout")

        {:halt, socket}
    end
  end

  defp schedule_session_refresh(socket, %{"session_expires_at" => exp}) when is_integer(exp) do
    now = System.system_time(:second)
    # Fire 10 minutes before the JWT expires
    refresh_at_ms = (exp - 10 * 60 - now) * 1000

    if connected?(socket) && refresh_at_ms > 0 do
      Process.send_after(self(), :session_refresh_soon, refresh_at_ms)
    end

    attach_hook(socket, :session_refresh_hook, :handle_info, fn
      :session_refresh_soon, socket ->
        {:halt, push_event(socket, "session_refresh", %{})}

      _other, socket ->
        {:cont, socket}
    end)
  end

  defp schedule_session_refresh(socket, _session), do: socket

  defp session_expired?(%{"session_expires_at" => exp}) when is_integer(exp) do
    System.system_time(:second) >= exp
  end

  defp session_expired?(_), do: false
end
