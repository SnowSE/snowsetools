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
       current_term_name: current_term_name
     )}
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
    <div class="max-w-lg mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-xl font-semibold text-slate-100">Settings</h1>
      </div>

      <.live_component
        module={SnowSeToolsWeb.Config.ActiveTermComponent}
        id="active-term"
        current_term_id={@current_term_id}
      />

      <.live_component
        module={SnowSeToolsWeb.Config.SyncStatusComponent}
        id="sync-status"
        current_term_id={@current_term_id}
        current_term_name={@current_term_name}
      />
    </div>
    """
  end

  defp find_term_name(terms, term_id) do
    Enum.find_value(terms, term_id, fn term ->
      if term["term_id"] == term_id, do: term["term_name"]
    end)
  end
end
