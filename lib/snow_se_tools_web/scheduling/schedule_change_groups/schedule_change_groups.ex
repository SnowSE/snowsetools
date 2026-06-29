defmodule SnowSeToolsWeb.Scheduling.ScheduleChangeGroups do
  use SnowSeToolsWeb, :html

  alias Phoenix.LiveView
  alias SnowSeTools.Scheduling.ScheduleChangeDomainManager
  alias SnowSeToolsWeb.Scheduling.ScheduleChangeGroupDetails
  alias SnowSeToolsWeb.Scheduling.ScheduleChangeGroupSelector
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

  attr :week_schedules, :map, default: %{}

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
    <div id="schedule-change-groups" class="flex min-h-0 flex-col gap-4">
      <ScheduleChangeGroupSelector.render state={@state} />
      <ScheduleChangeGroupDetails.render
        state={@state}
        week_schedules={@week_schedules}
      />
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

  defp parse_coordinate(value) when is_integer(value), do: value

  defp parse_coordinate(value) when is_binary(value) do
    case Integer.parse(value) do
      {coordinate, ""} -> coordinate
      _other -> 0
    end
  end

  defp parse_coordinate(_value), do: 0
end
