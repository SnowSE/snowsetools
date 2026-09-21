defmodule SnowSeToolsWeb.OnlineUsersLive do
  @moduledoc """
  The "someone else is here" banner in the header, for super users only.

  Nested in the header like the AI queue widget, so it updates itself on a
  presence change without every page having to carry the state. It says nothing
  at all when nobody else is online, and hovering it lists who is here, the
  page they are on, and how long they have been on it.

  A timer re-reads the list every half minute as well: presence only announces
  itself when someone joins or leaves, and the durations on screen — and the
  idle cut-off that removes someone who has wandered off — both move on their
  own.
  """

  use SnowSeToolsWeb, :live_view

  require Logger

  import SnowSeToolsWeb.Components.HoverTooltip

  alias SnowSeTools.Data.{Access, User}
  alias SnowSeToolsWeb.OnlineUsers

  @refresh_every_ms 30_000

  def mount(_params, session, socket) do
    socket =
      case viewer(session) do
        {:ok, viewer} -> watch_others(socket, viewer)
        :none -> assign(socket, viewer_id: nil, others: [])
      end

    {:ok, socket, layout: false}
  end

  defp viewer(session) do
    case session["current_user_id"] && User.get_by_id(session["current_user_id"]) do
      {:ok, user} ->
        if Access.admin?(user), do: {:ok, user}, else: :none

      nil ->
        :none

      {:error, reason} ->
        Logger.warning("Could not read the viewer for the online banner: #{inspect(reason)}")
        :none
    end
  end

  defp watch_others(socket, viewer) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SnowSeTools.PubSub, OnlineUsers.topic())
      :timer.send_interval(@refresh_every_ms, :refresh_online_users)
    end

    socket
    |> assign(:viewer_id, viewer.id)
    |> assign_others()
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, assign_others(socket)}

  def handle_info(:refresh_online_users, socket), do: {:noreply, assign_others(socket)}

  def handle_info(message, socket) do
    Logger.warning("OnlineUsersLive ignored an unhandled message #{inspect(message)}")
    {:noreply, socket}
  end

  defp assign_others(%{assigns: %{viewer_id: nil}} = socket), do: assign(socket, :others, [])

  defp assign_others(socket) do
    now = System.system_time(:second)

    others =
      socket.assigns.viewer_id
      |> OnlineUsers.others()
      |> Enum.map(fn row ->
        %{
          email: row.email,
          page: page_label(row.path),
          here_for: duration(now - row.page_since)
        }
      end)

    assign(socket, :others, others)
  end

  def render(assigns) do
    ~H"""
    <%!-- `contents` so an empty banner leaves no gap beside the site name. --%>
    <div id="online-users" class="contents">
      <.hover_tooltip :if={@others != []} id="online-users-tooltip" width_class="max-w-lg">
        <:label>
          <span
            id="online-users-banner"
            class="flex cursor-default items-center gap-1.5 rounded-md border border-amber-400/40 bg-amber-400/15 px-2 py-0.5 text-xs font-medium text-amber-200"
          >
            <span class="size-1.5 shrink-0 rounded-full bg-amber-300" />
            <%!-- The nav needs the room on a phone, so there it is just a count. --%>
            <span class="hidden sm:inline">{count_label(@others)}</span>
            <span class="sm:hidden">{length(@others)}</span>
          </span>
        </:label>
        <:body>
          <table class="w-max text-left text-xs">
            <thead class="text-[11px] uppercase tracking-wide text-slate-500">
              <tr>
                <th class="pr-4 pb-1 font-medium">Who</th>
                <th class="pr-4 pb-1 font-medium">Page</th>
                <th class="pb-1 font-medium">There for</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={other <- @others} class="align-top">
                <td class="pr-4 py-0.5 text-slate-200">{other.email}</td>
                <td class="pr-4 py-0.5 text-slate-400">{other.page}</td>
                <td class="py-0.5 tabular-nums text-slate-400">{other.here_for}</td>
              </tr>
            </tbody>
          </table>
        </:body>
      </.hover_tooltip>
    </div>
    """
  end

  defp count_label([_one]), do: "1 other user online"
  defp count_label(others), do: "#{length(others)} other users online"

  defp page_label("/home"), do: "Home"
  defp page_label("/syllabi"), do: "Syllabi"
  defp page_label("/syllabi/report"), do: "Syllabus report"
  defp page_label("/scheduling"), do: "Scheduling"
  defp page_label("/discord"), do: "Discord"
  defp page_label("/admin"), do: "Admin"
  defp page_label("/pending"), do: "Waiting for approval"
  defp page_label(path) when is_binary(path), do: path
  defp page_label(_path), do: "Somewhere else"

  defp duration(seconds) when seconds < 60, do: "just arrived"
  defp duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min"

  defp duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    case minutes do
      0 -> "#{hours} hr"
      _ -> "#{hours} hr #{minutes} min"
    end
  end
end
