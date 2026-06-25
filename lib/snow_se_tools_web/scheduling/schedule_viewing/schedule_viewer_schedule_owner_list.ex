defmodule SnowSeToolsWeb.Scheduling.ScheduleViewerScheduleOwnerList do
  use SnowSeToolsWeb, :html

  alias SnowSeTools.Scheduling.ScheduleOwnerMetadata

  attr :state, :any, required: true
  attr :selected_schedule_keys, :any, required: true

  def schedule_owner_list(assigns) do
    ~H"""
    <div id="schedule-owner-list" class="min-h-0 flex-1 space-y-2 overflow-y-auto pe-2">
      <.empty_state :if={@state.schedule_owners_metadata_by_term[@state.selected_term_code] == []} />

      <%= for schedule_owner <- filter_schedule_owners(@state.schedule_owners_metadata_by_term[@state.selected_term_code] || [], @state.query) do %>
        <.schedule_owner_button
          schedule_owner={schedule_owner}
          is_selected={MapSet.member?(@selected_schedule_keys, schedule_owner.key)}
        />
      <% end %>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div id="schedule-owner-empty" class="px-2 py-8 text-center text-sm text-slate-500">
      No matching schedules.
    </div>
    """
  end

  attr :schedule_owner, ScheduleOwnerMetadata, required: true
  attr :is_selected, :boolean, default: false

  defp schedule_owner_button(assigns) do
    ~H"""
    <button
      id={"schedule-owner-#{@schedule_owner.type}-#{@schedule_owner.name}"}
      type="button"
      phx-click="schedule-viewer:toggle"
      phx-value-key={@schedule_owner.key}
      class={[
        "flex w-full items-center justify-between gap-3 rounded-lg border px-3 py-2 text-left transition",
        if(@is_selected,
          do: "border-indigo-500/50 bg-indigo-950/50 text-indigo-100",
          else:
            "border-slate-800 bg-slate-900/50 text-slate-200 hover:border-slate-700 hover:bg-slate-800/70"
        )
      ]}
    >
      <span class="min-w-0">
        <span class="block truncate text-sm font-medium">{@schedule_owner.name}</span>
        <span class="block text-xs text-slate-500">{@schedule_owner.type}</span>
      </span>
    </button>
    """
  end

  defp filter_schedule_owners(schedule_owners, "") do
    schedule_owners
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
