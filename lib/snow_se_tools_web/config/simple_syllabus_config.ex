defmodule SnowSeToolsWeb.Config.SimpleSyllabusConfig do
  use SnowSeToolsWeb, :live_view

  require Logger

  alias SnowSeTools.ConfigDB
  alias SnowSeTools.Syllabi.Syncing.SyllabusSyncPubsub

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

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
       saved: false
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

  def handle_info({:simple_syllabus_sync, sink_message}, socket) do
    send_update(SnowSeToolsWeb.Config.SyncStatusComponent,
      id: "sync-status",
      sync_message: sink_message
    )

    {:noreply, socket}
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

          <.live_component
            module={SnowSeToolsWeb.Config.SyncStatusComponent}
            id="sync-status"
            current_term_id={@current_term_id}
            current_term_name={@current_term_name}
          />
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
