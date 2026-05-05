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
    <div
      id="queue-status-widget"
      class="fixed top-0 left-1/2 -translate-x-1/2 h-14 flex items-center pointer-events-none z-50"
    >
      <%= if @in_flight > 0 || @queued > 0 do %>
        <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-slate-900/90 border border-slate-700/60 backdrop-blur-sm shadow-lg text-xs text-slate-300">
          <span class="size-1.5 rounded-full bg-indigo-400 animate-pulse shrink-0" />
          <%= if @in_flight > 0 do %>
            <span>{@in_flight} generating</span>
          <% end %>
          <%= if @in_flight > 0 && @queued > 0 do %>
            <span class="text-slate-600">·</span>
          <% end %>
          <%= if @queued > 0 do %>
            <span class="text-slate-400">{@queued} queued</span>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
