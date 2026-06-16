defmodule SnowSeToolsWeb.Config.SyncStatusComponent do
  use SnowSeToolsWeb, :live_component

  alias SnowSeTools.Syllabi.Syncing.SyllabusScraperAgent

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> apply_sync_message()
     |> assign_new(:syncing, fn -> false end)
     |> assign_new(:sync_error, fn -> nil end)
     |> assign_new(:sync_progress_total, fn -> 0 end)
     |> assign_new(:sync_progress_completed, fn -> 0 end)
     |> assign_new(:sync_progress_percent, fn -> 0 end)}
  end

  defp apply_sync_message(socket) do
    case Map.get(socket.assigns, :sync_message) do
      {:sync_progress, %{total: total, completed: completed}}
      when not is_nil(total) and not is_nil(completed) ->
        percent = if total > 0, do: div(completed * 100, total), else: 0

        assign(socket,
          syncing: true,
          sync_progress_total: total,
          sync_progress_completed: completed,
          sync_progress_percent: percent
        )

      {:sync_complete, _} ->
        put_flash(socket, :info, "Sync completed successfully")
        |> assign(
          syncing: false,
          sync_progress_total: 0,
          sync_progress_completed: 0,
          sync_progress_percent: 0
        )

      {:sync_error, _source, error_message} ->
        assign(socket,
          sync_error: error_message,
          syncing: false,
          sync_progress_total: 0,
          sync_progress_completed: 0,
          sync_progress_percent: 0
        )

      _ ->
        socket
    end
  end

  def handle_event("sync_current_term", _params, socket) do
    current_term_id = socket.assigns.current_term_id

    case current_term_id do
      nil ->
        {:noreply, put_flash(socket, :error, "Please select a term first")}

      term_id ->
        SyllabusScraperAgent.sync_term(term_id)
        {:noreply, assign(socket, sync_error: nil, syncing: true)}
    end
  end

  def handle_event("sync_term_list", _params, socket) do
    SyllabusScraperAgent.sync_term_list()
    {:noreply, assign(socket, sync_error: nil, syncing: true)}
  end

  def render(assigns) do
    ~H"""
    <div id={"#{@id}-sync-status"}>
      <%= if @syncing do %>
        <div class="bg-slate-900/50 border border-slate-600 rounded-lg p-4 mb-4">
          <%= if @sync_progress_total > 0 do %>
            <div class="flex items-center justify-between mb-2">
              <p class="text-sm font-medium text-slate-200">Syncing syllabi...</p>
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
              <svg
                class="animate-spin h-5 w-5 text-indigo-400"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                >
                </circle>
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                >
                </path>
              </svg>
              <p class="text-sm font-medium text-slate-200">Preparing sync...</p>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="space-y-3 mb-4">
          <button
            phx-click="sync_current_term"
            phx-target={@myself}
            type="button"
            disabled={is_nil(@current_term_id)}
            class={[
              "w-full px-4 py-2 text-sm font-medium rounded-lg transition-colors",
              if(is_nil(@current_term_id),
                do: "bg-slate-700 text-slate-400 cursor-not-allowed",
                else: "bg-indigo-600 hover:bg-indigo-500 text-slate-50"
              )
            ]}
          >
            Sync Current Term ({@current_term_name})
          </button>

          <button
            phx-click="sync_term_list"
            phx-target={@myself}
            type="button"
            class="w-full px-4 py-2 text-sm font-medium rounded-lg transition-colors bg-slate-700 hover:bg-slate-600 text-slate-50"
          >
            Sync Term List
          </button>
        </div>
      <% end %>

      <%= if @sync_error do %>
        <div class="bg-red-900/30 border border-red-700 rounded-lg p-4 mb-4">
          <p class="text-sm text-red-400">
            <span class="font-medium">Sync failed:</span> {@sync_error}
          </p>
        </div>
      <% end %>
    </div>
    """
  end
end
