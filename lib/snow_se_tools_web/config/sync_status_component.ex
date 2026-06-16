defmodule SnowSeToolsWeb.Config.SyncStatusComponent do
  use SnowSeToolsWeb, :live_component

  alias SnowSeTools.Syllabi.Syncing.SyllabusScraperAgent

  def update(%{sync_message: msg} = assigns, socket) do
    socket =
      socket
      |> assign(Map.delete(assigns, :sync_message))
      |> apply_sync_message(msg)

    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:syncing, fn -> false end)
     |> assign_new(:sync_error, fn -> nil end)
     |> assign_new(:sync_progress_total, fn -> 0 end)
     |> assign_new(:sync_progress_completed, fn -> 0 end)
     |> assign_new(:sync_progress_percent, fn -> 0 end)}
  end

  def handle_event("sync_term", %{"term-id" => term_id}, socket) do
    case SyllabusScraperAgent.sync_term(term_id) do
      :ok ->
        {:noreply,
         assign(socket,
           sync_error: nil,
           syncing: true,
           sync_progress_total: 0,
           sync_progress_completed: 0,
           sync_progress_percent: 0,
           sync_status: SyllabusScraperAgent.status()
         )}

      {:error, :sync_in_progress} ->
        {:noreply, assign(socket, :sync_error, "A sync is already running.")}

      {:error, reason} ->
        {:noreply, assign(socket, :sync_error, "Could not start sync: #{inspect(reason)}")}
    end
  end

  def handle_event("sync_term_list", _params, socket) do
    case SyllabusScraperAgent.sync_term_list() do
      :ok ->
        {:noreply,
         assign(socket,
           sync_error: nil,
           syncing: true,
           sync_progress_total: 0,
           sync_progress_completed: 0,
           sync_progress_percent: 0,
           sync_status: SyllabusScraperAgent.status()
         )}

      {:error, :sync_in_progress} ->
        {:noreply, assign(socket, :sync_error, "A sync is already running.")}

      {:error, reason} ->
        {:noreply,
         assign(socket, :sync_error, "Could not start term refresh: #{inspect(reason)}")}
    end
  end

  defp apply_sync_message(socket, {:sync_progress, %{total: total, completed: completed}}) do
    percent = if total > 0, do: div(completed * 100, total), else: 0

    assign(socket,
      syncing: true,
      sync_progress_total: total,
      sync_progress_completed: completed,
      sync_progress_percent: percent
    )
  end

  defp apply_sync_message(socket, {:sync_complete, _sync_id}) do
    socket
    |> put_flash(:info, "Sync completed successfully")
    |> assign(
      syncing: false,
      sync_progress_total: 0,
      sync_progress_completed: 0,
      sync_progress_percent: 0,
      sync_error: nil
    )
  end

  defp apply_sync_message(socket, {:sync_error, _source, error_message}) do
    assign(socket,
      sync_error: error_message,
      syncing: false,
      sync_progress_total: 0,
      sync_progress_completed: 0,
      sync_progress_percent: 0
    )
  end

  def render(assigns) do
    ~H"""
    <section id={"#{@id}-sync-status"} class="bg-slate-800/50 border border-slate-700 rounded-xl p-6">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between mb-5">
        <div>
          <h2 class="text-sm font-medium text-slate-200">Syllabus Data Sync</h2>
          <p class="text-xs text-slate-500 mt-1">
            Refresh the term list or sync syllabi for one term. Only one sync can run at a time.
          </p>
        </div>
        <button
          id="sync-term-list-btn"
          phx-click="sync_term_list"
          phx-target={@myself}
          type="button"
          disabled={syncing?(@sync_status)}
          class={[
            "px-3 py-2 text-sm font-medium rounded-lg transition-colors",
            if(syncing?(@sync_status),
              do: "bg-slate-700 text-slate-400 cursor-not-allowed",
              else: "bg-slate-700 hover:bg-slate-600 text-slate-50"
            )
          ]}
        >
          Refresh Terms
        </button>
      </div>

      <%= if @syncing do %>
        <div id="sync-progress" class="bg-slate-900/50 border border-slate-600 rounded-lg p-4 mb-4">
          <%= if @sync_progress_total > 0 do %>
            <div class="flex items-center justify-between mb-2">
              <p class="text-sm font-medium text-slate-200">
                Syncing {syncing_term_name(@terms, @sync_status)}
              </p>
              <span class="text-xs text-slate-400">
                {@sync_progress_completed}/{@sync_progress_total}
              </span>
            </div>
            <div class="w-full bg-slate-700 rounded-full h-2 overflow-hidden">
              <div
                class="bg-indigo-500 h-2 rounded-full transition-all duration-300 ease-out"
                style={"width: #{@sync_progress_percent}%"}
              >
              </div>
            </div>
          <% else %>
            <div class="flex items-center justify-center gap-3 py-2">
              <span class="hero-arrow-path size-5 animate-spin text-indigo-400" />
              <p class="text-sm font-medium text-slate-200">Preparing sync...</p>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= if @sync_error do %>
        <div id="sync-error" class="bg-red-900/30 border border-red-700 rounded-lg p-4 mb-4">
          <p class="text-sm text-red-400">
            <span class="font-medium">Sync failed:</span> {@sync_error}
          </p>
        </div>
      <% end %>

      <div id="term-sync-list" class="overflow-hidden rounded-lg border border-slate-700">
        <div class="grid grid-cols-[1fr_auto_auto] gap-3 bg-slate-900/70 px-4 py-2 text-xs font-medium uppercase text-slate-500">
          <span>Term</span>
          <span class="hidden text-right sm:block">Last Synced</span>
          <span class="text-right">Action</span>
        </div>
        <div class="divide-y divide-slate-700/70">
          <%= for term <- @terms do %>
            <div
              id={"term-sync-row-#{term["term_id"]}"}
              class="grid grid-cols-[1fr_auto] gap-3 px-4 py-3 sm:grid-cols-[1fr_auto_auto] sm:items-center"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-medium text-slate-200">{term["term_name"]}</p>
                <p class="mt-0.5 text-xs text-slate-500">
                  {term["syllabus_count"] || 0} syllabi cached
                </p>
                <p class="mt-0.5 text-xs text-slate-500 sm:hidden">
                  {format_synced_at(term["last_synced_at"])}
                </p>
              </div>
              <div class="hidden text-right text-xs text-slate-400 sm:block">
                {format_synced_at(term["last_synced_at"])}
              </div>
              <button
                id={"sync-term-#{term["term_id"]}"}
                phx-click="sync_term"
                phx-value-term-id={term["term_id"]}
                phx-target={@myself}
                type="button"
                disabled={syncing?(@sync_status)}
                class={[
                  "self-start rounded-lg px-3 py-1.5 text-sm font-medium transition-colors sm:self-auto",
                  if(syncing?(@sync_status),
                    do: "bg-slate-700 text-slate-400 cursor-not-allowed",
                    else: "bg-indigo-600 hover:bg-indigo-500 text-slate-50"
                  )
                ]}
              >
                Sync
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp syncing?(%{syncing?: syncing?}), do: syncing?
  defp syncing?(_status), do: false

  defp syncing_term_name(terms, %{term_id: term_id}) when is_binary(term_id) do
    Enum.find_value(terms, term_id, fn term ->
      if term["term_id"] == term_id, do: term["term_name"]
    end)
  end

  defp syncing_term_name(_terms, _status), do: "term list"

  defp format_synced_at(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M")
  end

  defp format_synced_at(nil), do: "Never"
  defp format_synced_at(_value), do: "Never"
end
