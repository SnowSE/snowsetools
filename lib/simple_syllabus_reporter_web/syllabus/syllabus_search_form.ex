defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusSearchForm do
  use SimpleSyllabusReporterWeb, :html

  attr :query, :string, required: true
  attr :loading_search, :boolean, required: true
  attr :departments, :list, default: []
  attr :target, :any, default: nil

  def search_form(assigns) do
    ~H"""
    <form id="syllabus-search-form" phx-submit="search" phx-target={@target} class="flex gap-3 pb-3">
      <datalist id="departments-list">
        <%= for dept <- @departments do %>
          <option value={dept["name"]} />
        <% end %>
      </datalist>
      <input
        id="search-query-input"
        type="text"
        name="query"
        value={@query}
        list="departments-list"
        placeholder="Search by department or division…"
        class="flex-1 bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition"
        autofocus
      />
      <button
        type="submit"
        id="search-submit-btn"
        disabled={@loading_search}
        class="px-5 py-2.5 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-medium rounded-lg transition-colors"
      >
        <%= if @loading_search do %>
          Searching…
        <% else %>
          Search
        <% end %>
      </button>
    </form>
    """
  end
end
