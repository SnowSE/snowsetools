defmodule SimpleSyllabusReporterWeb.AI.QueueStatusLive do
  use SimpleSyllabusReporterWeb, :live_view

  alias SimpleSyllabusReporter.AI.AsyncCompletions

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SimpleSyllabusReporter.PubSub, AsyncCompletions.status_topic())
    end

    %{in_flight: in_flight, queued: queued} = AsyncCompletions.status()

    {:ok, assign(socket, in_flight: in_flight, queued: queued), layout: false}
  end

  def handle_info({:queue_status, %{in_flight: in_flight, queued: queued}}, socket) do
    {:noreply, assign(socket, in_flight: in_flight, queued: queued)}
  end

  def render(assigns) do
    ~H"""
    <div id="queue-status-widget" class="flex items-center gap-2 px-3 py-1 text-xs text-slate-300">
      <%= if @in_flight > 0 || @queued > 0 do %>
        <span class="size-1.5 rounded-full bg-indigo-400 animate-pulse shrink-0" />
        <%= if @in_flight > 0 do %>
          <span>{@in_flight} report{if @in_flight > 1, do: "s"} generating</span>
        <% end %>
        <%= if @in_flight > 0 && @queued > 0 do %>
          <span class="text-slate-600">·</span>
        <% end %>
        <%= if @queued > 0 do %>
          <span class="text-slate-400">{@queued} queued</span>
        <% end %>
      <% end %>
    </div>
    """
  end
end
