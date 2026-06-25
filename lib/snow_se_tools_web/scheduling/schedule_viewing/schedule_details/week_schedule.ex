defmodule SnowSeToolsWeb.Scheduling.WeekSchedule do
  use SnowSeToolsWeb, :html

  alias Phoenix.LiveView
  alias SnowSeTools.Scheduling.{ScheduleOwnerDomainManager, ScheduleOwnerSchedule, ScheduleUtils}
  alias SnowSeToolsWeb.Scheduling.ScheduleChangeApply
  import SnowSeToolsWeb.Scheduling.WeekScheduleGrid

  defstruct [
    :selected_term_code,
    :owner_key,
    :course_list,
    :week_schedule,
    :loading?
  ]

  attr :active_change_group, :map, default: nil

  def assign_component(socket) do
    socket
    |> assign(:week_schedules, %{})
    |> maybe_attach_hooks()
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :week_schedule_hooks_attached) do
      socket
    else
      socket
      |> LiveView.attach_hook("schedule-owner-week-schedule:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :week_schedule_hooks_attached], true)
    end
  end

  def assign_owner(socket, owner_key: owner_key, selected_term_code: selected_term_code)
      when is_binary(owner_key) do
    existing = Map.get(socket.assigns.week_schedules, owner_key)

    if match?(%__MODULE__{selected_term_code: ^selected_term_code, loading?: false}, existing) do
      socket
    else
      if is_binary(selected_term_code) do
        ScheduleOwnerDomainManager.request_schedule_owner_course_list(
          pid: self(),
          term_code: selected_term_code,
          owner_key: owner_key
        )
      end

      state = %__MODULE__{
        owner_key: owner_key,
        selected_term_code: selected_term_code,
        course_list: nil,
        week_schedule: nil,
        loading?: true
      }

      assign(socket, :week_schedules, Map.put(socket.assigns.week_schedules, owner_key, state))
    end
  end

  def remove_owner(socket, owner_key: owner_key) when is_binary(owner_key) do
    assign(socket, :week_schedules, Map.delete(socket.assigns.week_schedules, owner_key))
  end

  def clear_owners(socket) do
    assign(socket, :week_schedules, %{})
  end

  def render(assigns) do
    if is_nil(assigns.state.week_schedule) and !assigns.state.loading? do
      ScheduleOwnerDomainManager.request_schedule_owner_course_list(
        pid: self(),
        term_code: assigns.state.selected_term_code,
        owner_key: assigns.state.owner_key
      )
    end

    ~H"""
    <section
      id={"selected-schedule-#{@state.owner_key}"}
      data-schedule-card
      data-schedule-key={@state.owner_key}
      draggable="true"
      tabindex="0"
      class={[
        "relative w-[700px] p-3",
        "select-none cursor-grab motion-safe:transition-[transform,opacity,box-shadow,border-color,background-color] motion-safe:duration-200 motion-safe:ease-out active:cursor-grabbing",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-400/60 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950"
      ]}
    >
      <div class="rounded-lg border border-slate-800/80 bg-slate-950/55 p-3 shadow-sm shadow-slate-950/20 h-full">
        <%= if @state.loading? or is_nil(@state.week_schedule) do %>
          <div class="flex h-40 items-center justify-center text-sm text-slate-500">
            <.icon name="hero-arrow-path" class="size-4 animate-spin" />
            <span class="ml-2">Loading schedule...</span>
          </div>
        <% else %>
          <.schedule_header
            schedule_owner={@state.week_schedule}
            owner_key={@state.owner_key}
            position={@position}
            total_count={@total_count}
          />
          <.schedule_grid
            schedule_owner={effective_schedule(@state.week_schedule, @active_change_group)}
            owner_key={@state.owner_key}
            active_change_group={@active_change_group}
          />
        <% end %>
      </div>
    </section>
    """
  end

  attr :schedule_owner, :map, required: true
  attr :owner_key, :string, required: true
  attr :position, :integer, required: true
  attr :total_count, :integer, required: true

  defp schedule_header(assigns) do
    ~H"""
    <div class="mb-2 grid grid-cols-[1fr_auto] items-start gap-3">
      <div>
        <%= if @schedule_owner.type == :academic_program_semester do %>
          <h2 class="truncate text-base font-semibold leading-tight text-slate-100">
            {@schedule_owner.program_name}
            <span class="ml-1 text-xs font-medium text-slate-500">{@schedule_owner.credit_count} cr.</span>
          </h2>
          <p class="text-xs text-slate-500">{@schedule_owner.semester_name}</p>
        <% else %>
          <h2 class="truncate text-base font-semibold leading-tight text-slate-100">
            {@schedule_owner.name}
            <span class="ml-1 text-xs font-medium text-slate-500">{@schedule_owner.credit_count} cr.</span>
          </h2>
          <p class="text-xs text-slate-500">{@schedule_owner.type_label}</p>
        <% end %>
      </div>
      <div class="flex items-center gap-1">
        <button
          type="button"
          phx-click="schedule-details-order:move_schedule"
          phx-value-key={@owner_key}
          phx-value-direction="up"
          disabled={@position == 0}
          class="rounded p-1 text-slate-500 transition-colors disabled:cursor-not-allowed disabled:opacity-30"
          aria-label="Move schedule up"
        >
          <.icon name="hero-chevron-up" class="size-4" />
        </button>
        <button
          type="button"
          phx-click="schedule-details-order:move_schedule"
          phx-value-key={@owner_key}
          phx-value-direction="down"
          disabled={@position == @total_count - 1}
          class="rounded p-1 text-slate-500 transition-colors disabled:cursor-not-allowed disabled:opacity-30"
          aria-label="Move schedule down"
        >
          <.icon name="hero-chevron-down" class="size-4" />
        </button>
        <button
          type="button"
          phx-click="schedule-details-order:close_schedule"
          phx-value-key={@owner_key}
          class="rounded p-1 text-slate-500 transition-colors disabled:cursor-not-allowed disabled:opacity-30"
          aria-label="Remove schedule"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  def hooked_info(
        {:schedule_owner_course_list,
         %{term_code: term_code, owner_key: owner_key, course_list: course_list}},
        socket
      ) do
    state = Map.get(socket.assigns.week_schedules, owner_key)

    if state != nil and state.owner_key == owner_key and state.selected_term_code == term_code do
      {:halt,
       assign(
         socket,
         :week_schedules,
         Map.put(socket.assigns.week_schedules, owner_key, loaded_state(state, course_list))
       )}
    else
      {:cont, socket}
    end
  end

  def hooked_info(
        {:schedule_owners,
         {:schedule_owner_detail_changed,
          %{term_code: term_code, owner_key: owner_key, detail: course_list}}},
        socket
      ) do
    state = Map.get(socket.assigns.week_schedules, owner_key)

    if state != nil and state.owner_key == owner_key and state.selected_term_code == term_code do
      {:cont,
       assign(
         socket,
         :week_schedules,
         Map.put(socket.assigns.week_schedules, owner_key, loaded_state(state, course_list))
       )}
    else
      {:cont, socket}
    end
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  defp loaded_state(state, nil) do
    %{state | course_list: nil, week_schedule: nil, loading?: false}
  end

  defp loaded_state(state, []) do
    week_schedule =
      empty_week_schedule(owner_key: state.owner_key)

    %{state | course_list: [], week_schedule: week_schedule, loading?: false}
  end

  defp loaded_state(state, %ScheduleOwnerSchedule{} = course_list) do
    week_schedule =
      ScheduleUtils.build_week_schedule(
        type: course_list.type,
        name: course_list.name,
        courses: course_list.courses
      )
      |> Map.merge(%{
        program_name: course_list.program_name,
        semester_name: course_list.semester_name
      })

    %{state | course_list: course_list, week_schedule: week_schedule, loading?: false}
  end

  defp empty_week_schedule(owner_key: owner_key) when is_binary(owner_key) do
    {type, name} = empty_week_schedule_type(owner_key)
    ScheduleUtils.build_week_schedule(type: type, name: name, courses: [])
  end

  defp empty_week_schedule_type("professor:" <> name), do: {:professor, name}
  defp empty_week_schedule_type("room:" <> name), do: {:room, name}

  defp empty_week_schedule_type("academic_program_semester:" <> name),
    do: {:academic_program_semester, name}

  defp empty_week_schedule_type(owner_key), do: {:room, owner_key}

  defp effective_schedule(schedule_owner, nil), do: schedule_owner

  defp effective_schedule(schedule_owner, active_change_group) do
    ScheduleChangeApply.effective_schedule(schedule_owner, active_change_group)
  end
end
