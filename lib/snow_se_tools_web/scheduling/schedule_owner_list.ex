defmodule SnowSeToolsWeb.Scheduling.ScheduleOwnerList do
  use SnowSeToolsWeb, :live_component

  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerData

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:courses, assigns[:courses] || [])
     |> assign(:query, assigns[:query] || "")
     |> assign(:selected_schedule_owner_keys, assigns[:selected_schedule_owner_keys] || [])}
  end

  def handle_event("toggle_schedule_owner", %{"key" => key}, socket) do
    selected = socket.assigns.selected_schedule_owner_keys

    updated =
      if key in selected do
        Enum.reject(selected, &(&1 == key))
      else
        selected ++ [key]
      end

    send(self(), {:selection_updated, updated})
    {:noreply, socket}
  end

  def handle_event("clear_selected", _params, socket) do
    send(self(), {:selection_updated, []})
    {:noreply, socket}
  end

  def render(assigns) do
    assigns =
      assign_new(assigns, :schedule_owners, fn ->
        ScheduleOwnerData.build_schedule_owners(assigns.courses, assigns.query)
      end)

    ~H"""
    <div id="schedule-owner-list" class="min-h-0 flex-1 space-y-2 overflow-y-auto pe-2">
      <.empty_state :if={@schedule_owners == []} />

      <%= for schedule_owner <- @schedule_owners do %>
        <.schedule_owner_button
          schedule_owner={schedule_owner}
          is_selected={schedule_owner.key in @selected_schedule_owner_keys}
          myself={@myself}
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

  attr :myself, :any, required: true
  attr :schedule_owner, :map, required: true
  attr :is_selected, :boolean, default: false

  defp schedule_owner_button(assigns) do
    ~H"""
    <button
      id={"schedule-owner-#{@schedule_owner.dom_id}"}
      type="button"
      phx-click="toggle_schedule_owner"
      phx-target={@myself}
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
        <span class="block text-xs text-slate-500">{@schedule_owner.type_label}</span>
      </span>
      <span class="shrink-0 text-xs text-slate-400">{@schedule_owner.credit_count} cr.</span>
    </button>
    """
  end
end
