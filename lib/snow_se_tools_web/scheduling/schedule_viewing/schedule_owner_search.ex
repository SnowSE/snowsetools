defmodule SnowSeToolsWeb.Scheduling.ScheduleOwnerSearch do
  use SnowSeToolsWeb, :html

  alias SnowSeTools.Scheduling.ScheduleOwnerMetadata
  alias SnowSeToolsWeb.Scheduling.ScheduleOrder

  attr :state, :map, required: true
  attr :selected_schedule_order, :any, required: true

  def search(assigns) do
    assigns = assign(assigns, :matched_owners, matched_schedule_owners(assigns))

    ~H"""
    <div class="flex shrink-0 flex-col gap-3">
      <!-- Term selector -->
      <.form
        for={to_form(%{})}
        id="scheduling-term-form"
        phx-change="schedule-viewer:set_term"
      >
        <select
          id="scheduling-term-select"
          name="term_code"
          class="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        >
          <%= for term <- @state.terms do %>
            <option
              value={term["term_code"]}
              selected={term["term_code"] == @state.selected_term_code}
            >
              {term["term_name"]}
            </option>
          <% end %>
        </select>
      </.form>

      <!-- Search input + dropdown -->
      <div
        id="schedule-owner-search-container"
        phx-click-away="schedule-viewer:search_blurred"
        class="relative"
      >
        <.form
          for={to_form(%{})}
          id="scheduling-search-form"
          phx-change="schedule-viewer:search"
          phx-feedback-for="query"
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
              value={@state.query}
              phx-hook=".ScheduleOwnerSearchInput"
              autocomplete="off"
              placeholder="Search professor, room, or program semester"
              class="w-full rounded-lg border border-slate-700 bg-slate-900 py-2 pl-9 pr-3 text-sm text-slate-100 placeholder:text-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
            />
          </div>
        </.form>

        <!-- Dropdown results -->
        <div
          :if={@state.query != "" and @state.search_active}
          id="schedule-owner-search-results"
          class="absolute z-50 mt-1 max-h-72 w-full overflow-y-auto rounded-lg border border-slate-700 bg-slate-900 shadow-xl shadow-black/40"
        >
          <div :if={@matched_owners == []} class="px-3 py-4 text-center text-sm text-slate-500">
            No matching schedules.
          </div>

          <%= for schedule_owner <- @matched_owners do %>
            <button
              id={"schedule-owner-search-#{schedule_owner.type}-#{schedule_owner.name}"}
              type="button"
              phx-click="schedule-owner-search:select"
              phx-value-key={schedule_owner.key}
              class={[
                "flex w-full items-center gap-3 px-3 py-2 text-left transition",
                "hover:bg-slate-800/70",
                if(ScheduleOrder.member?(order: @selected_schedule_order, key: schedule_owner.key),
                  do: "bg-indigo-950/40 text-indigo-100",
                  else: "text-slate-200"
                )
              ]}
            >
              <span class="min-w-0">
                <span class="block truncate text-sm font-medium">{schedule_owner.name}</span>
                <span class="block text-xs text-slate-500">{schedule_owner.type}</span>
              </span>
              <.icon
                :if={ScheduleOrder.member?(order: @selected_schedule_order, key: schedule_owner.key)}
                name="hero-check"
                class="size-4 shrink-0 text-indigo-400"
              />
            </button>
          <% end %>
        </div>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ScheduleOwnerSearchInput">
      export default {
        mounted() {
          this.el.addEventListener("focus", () => {
            this.pushEvent("schedule-viewer:search_focused", {});
          });
        }
      }
    </script>
    """
  end

  # -- Filtering helpers --

  defp matched_schedule_owners(assigns) do
    owners =
      assigns.state.schedule_owners_metadata_by_term[assigns.state.selected_term_code] || []

    if assigns.state.query == "" do
      []
    else
      filter_schedule_owners(owners, assigns.state.query)
    end
  end

  defp filter_schedule_owners(schedule_owners, query) do
    query_words =
      query
      |> normalize()
      |> String.split(~r/\s+/, trim: true)

    Enum.filter(schedule_owners, fn
      %ScheduleOwnerMetadata{name: name, type: type} ->
        query_matches_all?(name, query_words) or
          query_matches_all?(Atom.to_string(type), query_words)
    end)
  end

  defp query_matches_all?(search_text, query_words) do
    normalized = normalize(search_text)
    Enum.all?(query_words, &String.contains?(normalized, &1))
  end

  defp normalize(value) when is_binary(value), do: value |> String.downcase() |> String.trim()
  defp normalize(_value), do: ""
end
