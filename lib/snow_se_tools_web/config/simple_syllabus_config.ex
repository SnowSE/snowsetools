defmodule SnowSeToolsWeb.Config.SimpleSyllabusConfig do
  use SnowSeToolsWeb, :live_view

  require Logger

  alias SnowSeTools.Syllabi.AvailableTermsDb
  alias SnowSeTools.Syllabi.Syncing.SyllabusScraperAgent
  alias SnowSeTools.Syllabi.Syncing.SyllabusSyncPubsub

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      SyllabusSyncPubsub.subscribe_to_sync_events()
    end

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:sync_status, SyllabusScraperAgent.status())
     |> load_terms()}
  end

  def handle_info({:simple_syllabus_sync, sink_message}, socket) do
    socket =
      socket
      |> assign(:sync_status, SyllabusScraperAgent.status())
      |> maybe_reload_terms(sink_message)

    send_update(SnowSeToolsWeb.Config.SyncStatusComponent,
      id: "sync-status",
      sync_message: sink_message,
      terms: socket.assigns.terms,
      sync_status: socket.assigns.sync_status
    )

    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.info("ConfigLive received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-xl font-semibold text-slate-100">Settings</h1>
      </div>

      <.live_component
        module={SnowSeToolsWeb.Config.SyncStatusComponent}
        id="sync-status"
        terms={@terms}
        sync_status={@sync_status}
      />
    </div>
    """
  end

  defp load_terms(socket) do
    terms =
      case AvailableTermsDb.list_terms_with_sync_status() do
        {:ok, terms} ->
          terms

        {:error, reason} ->
          Logger.error("Settings failed to load terms: #{inspect(reason)}")
          []
      end

    assign(socket, :terms, terms)
  end

  defp maybe_reload_terms(socket, {:sync_complete, _sync_id}), do: load_terms(socket)
  defp maybe_reload_terms(socket, _message), do: socket
end
