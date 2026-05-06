defmodule SimpleSyllabusReporterWeb.AI.CompletionsHistoryLive do
  use SimpleSyllabusReporterWeb, :live_view

  alias SimpleSyllabusReporter.AI.CompletionLog
  import SimpleSyllabusReporterWeb.AI.CompletionDetails

  on_mount {SimpleSyllabusReporterWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "AI Completions History")
      |> assign(:loading, true)
      |> assign(:completions_empty?, true)
      |> stream_configure(:completions, dom_id: fn item -> "completion-#{item["id"]}" end)
      |> stream(:completions, [])
      |> start_async(:fetch, fn -> CompletionLog.list_recent(200) end)

    {:ok, socket}
  end

  def handle_async(:fetch, {:ok, {:ok, completions}}, socket) do
    {:noreply,
     socket
     |> stream(:completions, completions)
     |> assign(:completions_empty?, completions == [])
     |> assign(:loading, false)}
  end

  def handle_async(:fetch, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> put_flash(:error, "Failed to load completions: #{inspect(reason)}")}
  end

  def handle_async(:fetch, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> put_flash(:error, "Unexpected error: #{inspect(reason)}")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="max-w-5xl mx-auto w-full px-3 pt-3 pb-6 flex flex-col gap-4">
        <div class="flex items-center gap-3 mb-3 shrink-0">
          <h1 class="text-xl font-semibold text-slate-100">AI Completions History</h1>
          <%= if @loading do %>
            <span class="text-slate-400 text-sm">Loading…</span>
          <% end %>
        </div>

        <div
          :if={@completions_empty? && !@loading}
          class="text-slate-500 text-sm italic py-8 text-center"
        >
          No completions recorded yet.
        </div>

        <div id="completions" phx-update="stream" class="flex flex-col gap-2">
          <div
            :for={{dom_id, completion} <- @streams.completions}
            id={dom_id}
            class="rounded-xl border border-slate-700 bg-slate-800/60"
          >
            <button
              id={"toggle-#{completion["id"]}"}
              type="button"
              phx-click={
                JS.toggle(to: "#details-#{completion["id"]}")
                |> JS.toggle_class("rotate-180", to: "#chevron-#{completion["id"]}")
              }
              class="w-full flex items-start gap-4 px-4 py-3 text-left hover:bg-slate-800 transition-colors cursor-pointer"
            >
              <span class={[
                "mt-0.5 shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider",
                if(completion["status"] == "ok",
                  do: "bg-green-900/60 text-green-400",
                  else: "bg-red-900/60 text-red-400"
                )
              ]}>
                {completion["status"]}
              </span>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="text-slate-200 text-sm font-medium truncate">
                    {completion["topic"]}
                  </span>
                  <span class="text-slate-500 text-xs">·</span>
                  <span class="text-slate-400 text-xs font-mono">{completion["event"]}</span>
                </div>
                <div class="flex items-center gap-3 mt-0.5 flex-wrap">
                  <span class="text-xs text-slate-500 font-mono">{completion["model"]}</span>
                  <span class="text-xs text-slate-600">
                    {message_count(completion["messages"])} messages
                  </span>
                  <span class="text-xs text-slate-600">{format_time(completion["inserted_at"])}</span>
                </div>
              </div>
              <span
                id={"chevron-#{completion["id"]}"}
                class="shrink-0 hero-chevron-down size-4 text-slate-500 transition-transform mt-0.5"
              />
            </button>

            <div id={"details-#{completion["id"]}"} class="hidden">
              <.completion_details completion={completion} />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp message_count(nil), do: 0
  defp message_count(msgs) when is_list(msgs), do: length(msgs)
  defp message_count(_), do: 0

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_time(other), do: to_string(other)
end
