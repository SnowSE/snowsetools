defmodule SnowSeToolsWeb.OnlineUsers do
  @moduledoc """
  Who else is using the site right now, for the banner super users see in the
  header.

  Every signed-in page tracks its viewer: `UserAuth`'s session hook attaches to
  `handle_params`, so a presence entry appears on the first render and follows
  the person from page to page. The entry lives in the LiveView process, so
  closing the tab, losing the connection or navigating off the site removes it
  without anything having to notice.

  Being connected is not the same as being at the desk, so the browser reports
  activity (a click, a keystroke, coming back to the tab) at most once a
  minute, and anyone whose last report is older than five minutes is left out
  of the list. Nothing is untracked for idleness — the cut-off is
  applied when the list is read, so a tab that has been sitting untouched all
  afternoon reappears the moment its person touches it again.

  One row per person, not per tab: their most recently active tab is the one
  that says where they are.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  require Logger

  alias SnowSeToolsWeb.Presence

  @topic "users:online"
  @idle_after_seconds 300

  def topic, do: @topic

  @doc "How long after someone's last click they stop counting as online."
  def idle_after_seconds, do: @idle_after_seconds

  @doc """
  Tracks the person on this page and keeps their entry current as they move
  around. Only the page itself: a nested LiveView shares its parent's viewer
  and would otherwise list them twice.
  """
  def track_viewer(%{parent_pid: nil} = socket) do
    socket
    |> attach_hook(:online_users_params, :handle_params, &hooked_params/3)
    |> attach_hook(:online_users_active, :handle_event, &hooked_event/3)
  end

  def track_viewer(socket), do: socket

  defp hooked_params(_params, uri, socket) do
    %{path: path} = URI.parse(uri)
    {:cont, put_presence(socket, path: path)}
  end

  defp hooked_event("online-users:active", _params, socket) do
    {:halt, put_presence(socket, path: socket.assigns[:current_path])}
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  defp put_presence(socket, path: path) do
    user = socket.assigns[:current_user]

    cond do
      !connected?(socket) or is_nil(user) or is_nil(path) ->
        socket

      socket.assigns[:online_user_tracked?] ->
        update_entry(user, path)
        socket

      true ->
        track_entry(user, path)
        assign(socket, :online_user_tracked?, true)
    end
  end

  defp track_entry(user, path) do
    now = System.system_time(:second)

    case Presence.track(self(), @topic, to_string(user.id), %{
           email: user.email,
           path: path,
           page_since: now,
           active_at: now
         }) do
      {:ok, _ref} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not track #{user.email} as online: #{inspect(reason)}")
        :error
    end
  end

  defp update_entry(user, path) do
    now = System.system_time(:second)

    result =
      Presence.update(self(), @topic, to_string(user.id), fn meta ->
        if meta.path == path do
          %{meta | active_at: now}
        else
          %{meta | path: path, page_since: now, active_at: now}
        end
      end)

    case result do
      {:ok, _ref} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not update #{user.email}'s online entry: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Everyone online except `viewer_id`, most recently arrived first.

  Each row is `%{id:, email:, path:, page_since:, active_at:}`, with the times
  as unix seconds so the caller can say how long ago they were relative to its
  own clock.
  """
  def others(viewer_id) do
    now = System.system_time(:second)
    viewer_id = to_string(viewer_id)

    @topic
    |> Presence.list()
    |> Enum.reject(fn {user_id, _presence} -> user_id == viewer_id end)
    |> Enum.map(fn {user_id, %{metas: metas}} -> summarise(user_id, metas) end)
    |> Enum.filter(&active?(&1, now))
    |> Enum.sort_by(& &1.page_since, :desc)
  end

  # The tab they last touched is the one that says where they are.
  defp summarise(user_id, metas) do
    meta = Enum.max_by(metas, & &1.active_at)

    %{
      id: user_id,
      email: meta.email,
      path: meta.path,
      page_since: meta.page_since,
      active_at: meta.active_at
    }
  end

  defp active?(row, now), do: now - row.active_at <= @idle_after_seconds
end
