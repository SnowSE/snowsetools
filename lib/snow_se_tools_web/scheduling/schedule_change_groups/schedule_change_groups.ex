defmodule SnowSeToolsWeb.Scheduling.ScheduleChangeGroups do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Scheduling.ScheduleChangeDomainManager
  alias SnowSeTools.Scheduling.ScheduleUtils
  alias SnowSeToolsWeb.Scheduling.ScheduleOrder
  alias SnowSeToolsWeb.Scheduling.WeekSchedule

  defstruct [
    :groups,
    :active_change_group_id,
    :active_change_group,
    :creating,
    :open_change_menu
  ]

  @key :schedule_change_groups_state

  attr :schedule_owners, :list, default: []

  def assign_component(socket) do
    socket
    |> assign(@key, %__MODULE__{
      groups: [],
      active_change_group_id: nil,
      active_change_group: nil,
      creating: false,
      open_change_menu: nil
    })
    |> maybe_attach_hooks()
  end

  def render(assigns) do
    ~H"""
    <div
      id="schedule-change-groups"
      class="flex min-h-0 flex-col gap-4"
      phx-hook=".ScheduleChangeGroupsMenu"
    >
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

      <div class="min-h-0 border-t border-slate-800/80 pt-3">
        <div class="mb-2 flex items-center justify-between gap-2">
          <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400">
            Changes
          </h3>
          <span class="text-[10px] text-slate-500">
            {length(active_changes(@state))}
          </span>
        </div>

        <div
          :if={is_nil(@state.active_change_group)}
          class="rounded-md border border-dashed border-slate-700/60 px-3 py-4 text-center text-xs text-slate-500"
        >
          Select a change group to view changes.
        </div>

        <div
          :if={@state.active_change_group && active_changes(@state) == []}
          class="rounded-md border border-dashed border-slate-700/60 px-3 py-4 text-center text-xs text-slate-500"
        >
          No changes in this group yet.
        </div>

        <div class="flex min-h-0 flex-col gap-2 overflow-y-auto pr-1">
          <%= for change <- active_changes(@state) do %>
            <div
              id={"schedule-change-#{change["id"]}"}
              class="rounded-lg border border-slate-800 bg-slate-950/55 p-2.5"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="min-w-0">
                  <div class="truncate text-sm font-medium text-slate-200">
                    {change_title(change)}
                  </div>
                  <div class="mt-0.5 text-[11px] text-slate-500">
                    {change_summary(change)}
                  </div>
                </div>

                <button
                  type="button"
                  data-change-menu-button
                  data-change-id={change["id"]}
                  class="shrink-0 rounded px-1.5 py-0.5 text-xs text-slate-400 transition hover:bg-slate-800 hover:text-slate-200"
                >
                  View
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <.modal
          :if={open_change_menu_change(@state)}
          id="schedule-change-menu-modal"
          on_close="schedule-change-groups:close_change_menu"
          x={@state.open_change_menu.x}
          y={@state.open_change_menu.y}
          panel_class="fixed w-60 overflow-hidden rounded-md border border-slate-700 bg-slate-950 py-1 text-xs shadow-2xl shadow-slate-950/60"
        >
          <% change = open_change_menu_change(@state) %>
          <div class="border-b border-slate-800 px-2 py-2">
            <div class="truncate text-sm font-medium text-slate-200">{change_title(change)}</div>
            <div class="mt-0.5 text-[11px] text-slate-500">{change_summary(change)}</div>
          </div>
          <.change_target_button
            :if={professor_key(change)}
            key={professor_key(change)}
            label={"Professor: #{change["target_professor"]}"}
          />
          <.change_target_button
            :if={room_key(change)}
            key={room_key(change)}
            label={"Room: #{room_label(change)}"}
          />
          <div class="border-t border-slate-800/80 my-1"></div>
          <div class="px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-slate-500">
            Academic Schedules
          </div>
          <div class="max-h-52 overflow-y-auto">
            <.change_target_button
              :for={owner <- academic_schedule_owners(@schedule_owners)}
              key={owner.key}
              label={owner.name}
            />
            <div
              :if={academic_schedule_owners(@schedule_owners) == []}
              class="px-2 py-2 text-slate-500"
            >
              No academic schedules.
            </div>
          </div>
          <div class="border-t border-slate-800/80 my-1"></div>
          <button
            type="button"
            phx-click="schedule-change-groups:delete_change"
            phx-value-change-id={change["id"]}
            class="block w-full px-2 py-1.5 text-left text-red-300 transition hover:bg-red-950/60 hover:text-red-100"
          >
            Delete change
          </button>
        </.modal>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ScheduleChangeGroupsMenu">
      export default {
        mounted() {
          this.onClick = (event) => {
            const button = event.target.closest("[data-change-menu-button]");
            if (!button || !this.el.contains(button)) return;

            const rect = button.getBoundingClientRect();
            this.pushEvent("schedule-change-groups:open_change_menu", {
              change_id: button.dataset.changeId,
              x: Math.round(Math.min(rect.left, window.innerWidth - 260)),
              y: Math.round(rect.bottom + 4),
            });
          };

          this.el.addEventListener("click", this.onClick);
        },

        destroyed() {
          this.el.removeEventListener("click", this.onClick);
        },
      };
    </script>
    """
  end

  attr :key, :string, required: true
  attr :label, :string, required: true

  defp change_target_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="schedule-change-groups:view_schedule"
      phx-value-key={@key}
      class="block w-full truncate px-2 py-1.5 text-left text-slate-300 transition hover:bg-slate-800 hover:text-slate-100"
    >
      {@label}
    </button>
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
         active_change_group: active_group,
         open_change_menu: nil
     })}
  end

  def hooked_event(
        "schedule-change-groups:open_change_menu",
        %{"change_id" => change_id, "x" => x, "y" => y},
        socket
      ) do
    state = socket.assigns[@key]

    {:halt,
     assign(socket, @key, %{
       state
       | open_change_menu: %{
           change_id: change_id,
           x: parse_coordinate(x),
           y: parse_coordinate(y)
         }
     })}
  end

  def hooked_event("schedule-change-groups:close_change_menu", _params, socket) do
    state = socket.assigns[@key]
    {:halt, assign(socket, @key, %{state | open_change_menu: nil})}
  end

  def hooked_event("schedule-change-groups:view_schedule", %{"key" => key}, socket) do
    selected_term_code = socket.assigns.schedule_viewer_state.selected_term_code

    socket =
      if is_binary(selected_term_code) and
           !ScheduleOrder.member?(
             order: socket.assigns.schedule_details_order.selected_schedule_order,
             key: key
           ) do
        socket
        |> WeekSchedule.assign_owner(owner_key: key, selected_term_code: selected_term_code)
        |> assign(:schedule_details_order, %{
          socket.assigns.schedule_details_order
          | selected_schedule_order:
              ScheduleOrder.put(
                order: socket.assigns.schedule_details_order.selected_schedule_order,
                key: key
              )
        })
      else
        socket
      end

    state = socket.assigns[@key]
    {:halt, assign(socket, @key, %{state | open_change_menu: nil})}
  end

  def hooked_event("schedule-change-groups:delete_change", %{"change-id" => change_id}, socket) do
    ScheduleChangeDomainManager.remove_change(change_id)
    state = socket.assigns[@key]
    {:halt, assign(socket, @key, %{state | open_change_menu: nil})}
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

  defp active_changes(%__MODULE__{active_change_group: nil}), do: []

  defp active_changes(%__MODULE__{active_change_group: active_change_group}) do
    Map.get(active_change_group, "changes", [])
  end

  defp open_change_menu_change(%__MODULE__{open_change_menu: nil}), do: nil

  defp open_change_menu_change(%__MODULE__{open_change_menu: %{change_id: change_id}} = state) do
    Enum.find(active_changes(state), &(&1["id"] == change_id))
  end

  defp change_title(%{"course_name" => "__DELETED__"} = change),
    do: "Removed CRN #{change["crn"]}"

  defp change_title(%{"course_name" => name}) when is_binary(name) and name != "", do: name
  defp change_title(change), do: "CRN #{change["crn"]}"

  defp change_summary(change) do
    [
      String.upcase(change["operation"] || "update"),
      change["crn"] && "CRN #{change["crn"]}",
      first_meeting_label(change)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp first_meeting_label(change) do
    case List.first(Map.get(change, "meet_info", [])) do
      %{} = meeting ->
        days =
          meeting
          |> Map.get("days", [])
          |> Enum.map(&String.slice(&1, 0, 3))
          |> Enum.join("/")

        [days, meeting["start_time"], room_label(change)]
        |> Enum.reject(&blank?/1)
        |> Enum.join(" ")

      _other ->
        nil
    end
  end

  defp professor_key(%{"target_professor" => professor})
       when is_binary(professor) and professor != "",
       do: "professor:#{professor}"

  defp professor_key(_change), do: nil

  defp room_key(change) do
    case room_label(change) do
      nil -> nil
      room -> "room:#{room}"
    end
  end

  defp room_label(change) do
    case List.first(Map.get(change, "meet_info", [])) do
      %{} = meeting -> ScheduleUtils.room_name(meeting: meeting)
      _other -> nil
    end
  end

  defp academic_schedule_owners(schedule_owners) do
    schedule_owners
    |> Enum.filter(&(&1.type == :academic_program_semester))
    |> Enum.sort_by(& &1.name)
  end

  defp blank?(value), do: is_nil(value) or value == ""

  defp parse_coordinate(value) when is_integer(value), do: value

  defp parse_coordinate(value) when is_binary(value) do
    case Integer.parse(value) do
      {coordinate, ""} -> coordinate
      _other -> 0
    end
  end

  defp parse_coordinate(_value), do: 0
end
