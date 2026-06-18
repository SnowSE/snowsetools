defmodule SnowSeToolsWeb.Scheduling.ScheduleOwnerSearch do
  use SnowSeToolsWeb, :live_component

  alias SnowSeTools.Snow.SnowCourseCacheDb

  def mount(socket) do
    terms =
      case SnowCourseCacheDb.list_terms_with_courses() do
        {:error, _reason} -> []
        terms -> terms
      end

    {:ok,
     socket
     |> assign(:terms, terms)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:query, assigns[:query] || "")
     |> assign(:selected_term_code, assigns[:selected_term_code])}
  end

  def handle_event("set_term", %{"term_code" => term_code}, socket) do
    query = socket.assigns.query
    send(self(), {:search_updated, %{term_code: term_code, query: query}})

    {:noreply, assign(socket, :selected_term_code, term_code)}
  end

  def handle_event("search", %{"query" => query}, socket) do
    selected_term_code = socket.assigns.selected_term_code

    send(
      self(),
      {:search_updated, %{term_code: selected_term_code, query: query}}
    )

    {:noreply, assign(socket, :query, query)}
  end

  def render(assigns) do
    ~H"""
    <div class="flex shrink-0 flex-col gap-3">
      <.form
        for={to_form(%{})}
        id="scheduling-term-form"
        phx-change="set_term"
        phx-target={@myself}
      >
        <select
          id="scheduling-term-select"
          name="term_code"
          class="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        >
          <%= for term <- @terms do %>
            <option value={term["term_code"]} selected={term["term_code"] == @selected_term_code}>
              {term["term_name"]}
            </option>
          <% end %>
        </select>
      </.form>

      <.form
        for={to_form(%{})}
        id="scheduling-search-form"
        phx-change="search"
        phx-target={@myself}
      >
        <div class="relative">
          <.icon
            name="hero-magnifying-glass"
            class="pointer-events-none absolute left-3 top-2.5 size-4 text-slate-500"
          />
          <input
            id="scheduling-search-input"
            type="search"
            name="query"
            value={@query}
            autocomplete="off"
            placeholder="Search professor, room, or program semester"
            class="w-full rounded-lg border border-slate-700 bg-slate-900 py-2 pl-9 pr-3 text-sm text-slate-100 placeholder:text-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
          />
        </div>
      </.form>
    </div>
    """
  end
end
