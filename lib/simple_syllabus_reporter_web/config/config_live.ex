defmodule SimpleSyllabusReporterWeb.Config.ConfigLive do
  use SimpleSyllabusReporterWeb, :live_view

  require Logger

  alias SimpleSyllabusReporter.ConfigDB
  alias SimpleSyllabusReporter.Syllabi.Syncing.SyllabusScraperAgent
  alias SimpleSyllabusReporter.Syllabi.Syncing.SyllabusSyncPubsub

  on_mount {SimpleSyllabusReporterWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    current_term_id = ConfigDB.get_current_term()
    available_terms = ConfigDB.list_available_terms()
    current_term_name = find_term_name(available_terms, current_term_id)

    if connected?(socket) do
      SyllabusSyncPubsub.subscribe_to_sync_events()
    end

    {:ok,
     assign(socket,
       page_title: "Settings",
       current_term_id: current_term_id,
       current_term_name: current_term_name,
       available_terms: available_terms,
       saved: false,
       syncing: false,
       sync_error: nil,
       sync_progress_total: 0,
       sync_progress_completed: 0,
       sync_progress_percent: 0
     )}
  end

  def handle_event("set_term", %{"term_id" => term_id}, socket) do
    value = if term_id == "", do: nil, else: term_id
    term_name = find_term_name(socket.assigns.available_terms, value)

    case ConfigDB.set_current_term(value) do
      :ok ->
        {:noreply,
         assign(socket,
           current_term_id: value,
           current_term_name: term_name,
           saved: true
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
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

  def handle_info({:sync_progress, %{total: total, completed: completed}}, socket) do
    percent = if total > 0, do: div(completed * 100, total), else: 0

    {:noreply,
     assign(socket,
       syncing: true,
       sync_progress_total: total,
       sync_progress_completed: completed,
       sync_progress_percent: percent
     )}
  end

  def handle_info({:sync_complete, _}, socket) do
    available_terms = ConfigDB.list_available_terms()

    {:noreply,
     socket
     |> assign(available_terms: available_terms, syncing: false)
     |> assign(sync_progress_total: 0, sync_progress_completed: 0, sync_progress_percent: 0)
     |> put_flash(:info, "Sync completed successfully")}
  end

  def handle_info({:sync_error, _, error_message}, socket) do
    {:noreply,
     assign(socket,
       sync_error: error_message,
       syncing: false,
       sync_progress_total: 0,
       sync_progress_completed: 0,
       sync_progress_percent: 0
     )}
  end

  def handle_info(msg, socket) do
    Logger.info("ConfigLive received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="max-w-lg mx-auto px-4 py-8">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-xl font-semibold text-slate-100">Settings</h1>
        </div>

        <div class="bg-slate-800/50 border border-slate-700 rounded-xl p-6 mb-6">
          <h2 class="text-sm font-medium text-slate-200 mb-1">Active Term</h2>
          <p class="text-xs text-slate-500 mb-4">
            Only syllabi and reports for the selected term are visible. Choose "All terms" to show everything.
          </p>

          <form id="config-form" phx-submit="set_term" class="flex items-center gap-3">
            <select
              name="term_id"
              id="term-select"
              class="flex-1 bg-slate-900 border border-slate-600 text-slate-200 text-sm rounded-lg px-3 py-2 focus:outline-none focus:ring-1 focus:ring-purple-500 focus:border-purple-500"
            >
              <option value="" selected={is_nil(@current_term_id)}>All terms</option>
              <%= for term <- @available_terms do %>
                <option value={term["term_id"]} selected={@current_term_id == term["term_id"]}>
                  {term["term_name"]}
                </option>
              <% end %>
            </select>
            <button
              type="submit"
              id="save-term-btn"
              class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-slate-50 text-sm font-medium rounded-lg transition-colors"
            >
              Save
            </button>
          </form>

          <%= if @saved do %>
            <p id="saved-notice" class="mt-3 text-xs text-green-400">Saved.</p>
          <% end %>
        </div>

        <div class="bg-slate-800/50 border border-slate-700 rounded-xl p-6">
          <h2 class="text-sm font-medium text-slate-200 mb-4">Syllabus Data Sync</h2>
          <p class="text-xs text-slate-500 mb-4">
            Download and cache all syllabi from SimpleSyllabus. Syncs are on-demand only.
          </p>

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
      </div>
    </Layouts.app>
    """
  end

  defp find_term_name(terms, term_id) do
    Enum.find_value(terms, term_id, fn term ->
      if term["term_id"] == term_id, do: term["term_name"]
    end)
  end
end
