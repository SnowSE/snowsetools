defmodule SnowSeToolsWeb.Scheduling.ScheduleChangeGroups do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Scheduling.ScheduleChangeDomainManager

  defstruct [
    :groups,
    :active_change_group_id,
    :active_change_group,
    :creating
  ]

  @key :schedule_change_groups_state

  def assign_component(socket) do
    socket
    |> assign(@key, %__MODULE__{
      groups: [],
      active_change_group_id: nil,
      active_change_group: nil,
      creating: false
    })
    |> maybe_attach_hooks()
  end

  def render(assigns) do
    ~H"""
    <div id="schedule-change-groups" class="flex flex-col gap-2">
      <div class="flex items-center justify-between">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400">
          Change Groups
        </h3>
        <button
          type="button"
          phx-click="schedule-change-groups:new_group"
          class="rounded px-2 py-0.5 text-xs text-indigo-400 transition-colors hover:bg-indigo-950/50 hover:text-indigo-300"
        >
          + New
        </button>
      </div>

      <%= if @state.creating do %>
        <form phx-submit="schedule-change-groups:save_new" class="flex gap-1">
          <input
            type="text"
            name="name"
            placeholder="Group name"
            class="flex-1 rounded border border-slate-600 bg-slate-800 px-2 py-1 text-xs text-slate-200 placeholder-slate-500 outline-none focus:border-indigo-500"
            autofocus
          />
          <button
            type="submit"
            class="rounded bg-indigo-600 px-2 py-1 text-xs text-white hover:bg-indigo-500"
          >
            Save
          </button>
          <button
            type="button"
            phx-click="schedule-change-groups:cancel_new"
            class="rounded px-2 py-1 text-xs text-slate-400 hover:bg-slate-800"
          >
            Cancel
          </button>
        </form>
      <% end %>

      <div class="flex flex-col gap-1">
        <%= for group <- Enum.sort_by(@state.groups, & &1["created_at"], :desc) do %>
          <button
            type="button"
            phx-click="schedule-change-groups:select_group"
            phx-value-group-id={group["id"]}
            class={[
              "group flex w-full items-center justify-between rounded-md px-2.5 py-1.5 text-left text-sm transition-colors",
              @state.active_change_group_id == group["id"] &&
                "bg-indigo-950/60 text-indigo-200 ring-1 ring-indigo-500/40",
              @state.active_change_group_id != group["id"] &&
                "text-slate-300 hover:bg-slate-800/60"
            ]}
          >
            <span class="truncate">{group["name"]}</span>
            <span class="ml-2 shrink-0 text-[10px] text-slate-500">
              {length(Map.get(group, "changes", []))} changes
            </span>
          </button>
        <% end %>
      </div>

      <%= if @state.groups == [] do %>
        <div class="rounded-md border border-dashed border-slate-700/60 px-3 py-4 text-center text-xs text-slate-500">
          No change groups yet. Click "New" to create one.
        </div>
      <% end %>
    </div>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :schedule_change_groups_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("schedule-change-groups:event", :handle_event, &hooked_event/3)
      |> put_in([Access.key(:private), :schedule_change_groups_hooks_attached?], true)
    end
  end

  def hooked_event("schedule-change-groups:new_group", _params, socket) do
    state = socket.assigns[@key]
    {:halt, assign(socket, @key, %{state | creating: true})}
  end

  def hooked_event("schedule-change-groups:save_new", %{"name" => name}, socket) do
    state = socket.assigns[@key]
    name = String.trim(name)

    if name != "" do
      ScheduleChangeDomainManager.create_group(name)
    end

    {:halt, assign(socket, @key, %{state | creating: false})}
  end

  def hooked_event("schedule-change-groups:cancel_new", _params, socket) do
    state = socket.assigns[@key]
    {:halt, assign(socket, @key, %{state | creating: false})}
  end

  def hooked_event("schedule-change-groups:select_group", %{"group-id" => group_id}, socket) do
    state = socket.assigns[@key]

    new_active_id =
      if state.active_change_group_id == group_id,
        do: nil,
        else: group_id

    active_group =
      if new_active_id, do: Enum.find(state.groups, &(&1["id"] == new_active_id)), else: nil

    {:halt,
     assign(socket, @key, %{
       state
       | active_change_group_id: new_active_id,
         active_change_group: active_group
     })}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def sync_groups(socket, groups) do
    state = socket.assigns[@key]

    {active_id, active_group} =
      if state.active_change_group_id do
        group = Enum.find(groups, &(&1["id"] == state.active_change_group_id))
        {state.active_change_group_id, group}
      else
        case Enum.sort_by(groups, & &1["created_at"], :desc) do
          [newest | _] -> {newest["id"], newest}
          [] -> {nil, nil}
        end
      end

    assign(socket, @key, %{
      state
      | groups: groups,
        active_change_group_id: active_id,
        active_change_group: active_group
    })
  end

  def active_change_group(state) do
    state.active_change_group
  end
end
