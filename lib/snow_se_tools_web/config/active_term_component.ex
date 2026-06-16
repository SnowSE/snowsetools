defmodule SnowSeToolsWeb.Config.ActiveTermComponent do
  use SnowSeToolsWeb, :live_component
  require Logger
  alias SnowSeTools.ConfigDB
  alias SnowSeTools.Syllabi.AvailableTermsDb

  def update(assigns, socket) do
    available_terms =
      case AvailableTermsDb.list_active_terms() do
        {:error, error} ->
          Logger.error("Failed to fetch available terms: #{inspect(error)}")
          []

        {:ok, terms} ->
          terms
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:available_terms, available_terms)
     |> assign_new(:saved, fn -> false end)}
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

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save term")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="bg-slate-800/50 border border-slate-700 rounded-xl p-6 mb-6">
      <h2 class="text-sm font-medium text-slate-200 mb-1">Active Term</h2>
      <p class="text-xs text-slate-500 mb-4">
        Only syllabi and reports for the selected term are visible. Choose "All terms" to show everything.
      </p>

      <form
        id="config-form"
        phx-submit="set_term"
        phx-target={@myself}
        class="flex items-center gap-3"
      >
        <select
          name="term_id"
          id="term-select"
          class="flex-1 bg-slate-900 border border-slate-600 text-slate-200 text-sm rounded-lg px-3 py-2 focus:outline-none focus:ring-1 focus:ring-purple-500 focus:border-purple-500"
        >
          <option value="" selected={is_nil(@current_term_id)}>All terms</option>
          <%= for {term_id, term_name} <- @available_terms do %>
            <option value={term_id} selected={@current_term_id == term_id}>
              {term_name}
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
    """
  end

  defp find_term_name(terms, term_id) do
    Enum.find_value(terms, term_id, fn {id, name} ->
      if id == term_id, do: name
    end)
  end
end
