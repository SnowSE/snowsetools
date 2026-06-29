defmodule SnowSeToolsWeb.Scheduling.WeekSchedule do
  use SnowSeToolsWeb, :html

  alias Phoenix.LiveView

  alias SnowSeTools.Scheduling.{
    ScheduleChangeDomainManager,
    ScheduleOwnerDomainManager,
    ScheduleOwnerSchedule,
    ScheduleUtils
  }

  alias SnowSeToolsWeb.Scheduling.{CourseChangeIntent, ScheduleChangeApply}
  import SnowSeToolsWeb.Scheduling.WeekScheduleGrid

  defstruct [
    :selected_term_code,
    :owner_key,
    :course_list,
    :week_schedule,
    :selected_variant_index,
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
      |> LiveView.attach_hook(
        "schedule-owner-week-schedule:event",
        :handle_event,
        &hooked_event/3
      )
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
        selected_variant_index: 0,
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
            selected_variant_index={@state.selected_variant_index || 0}
          />
          <.schedule_grid
            schedule_owner={effective_schedule(@state.week_schedule, @active_change_group)}
            owner_key={@state.owner_key}
            selected_term_code={@state.selected_term_code}
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
  attr :selected_variant_index, :integer, default: 0

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
          <div
            :if={variant_count(@schedule_owner) > 1}
            class="mt-2 flex items-center gap-1.5 text-xs text-slate-400"
          >
            <button
              type="button"
              id={"schedule-variant-previous-#{@owner_key}"}
              phx-click="schedule-owner-week-schedule:change_variant"
              phx-value-owner-key={@owner_key}
              phx-value-direction="previous"
              disabled={@selected_variant_index == 0}
              class="rounded border border-slate-800 bg-slate-900/70 p-1 text-slate-300 transition-colors hover:border-slate-700 hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-35"
              aria-label="Previous schedule option"
            >
              <.icon name="hero-chevron-left" class="size-3.5" />
            </button>
            <span id={"schedule-variant-label-#{@owner_key}"} class="tabular-nums">
              Option {@selected_variant_index + 1} of {variant_count(@schedule_owner)}
            </span>
            <button
              type="button"
              id={"schedule-variant-next-#{@owner_key}"}
              phx-click="schedule-owner-week-schedule:change_variant"
              phx-value-owner-key={@owner_key}
              phx-value-direction="next"
              disabled={@selected_variant_index >= variant_count(@schedule_owner) - 1}
              class="rounded border border-slate-800 bg-slate-900/70 p-1 text-slate-300 transition-colors hover:border-slate-700 hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-35"
              aria-label="Next schedule option"
            >
              <.icon name="hero-chevron-right" class="size-3.5" />
            </button>
          </div>
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

  def hooked_event("week-schedule-grid:move_course", params, socket) do
    persist_course_change(params, &CourseChangeIntent.move_course_attrs/1, socket)
  end

  def hooked_event("week-schedule-grid:edit_course", params, socket) do
    persist_course_change(params, &CourseChangeIntent.edit_course_attrs/1, socket)
  end

  def hooked_event("week-schedule-grid:delete_course", params, socket) do
    persist_course_change(params, &CourseChangeIntent.delete_course_attrs/1, socket)
  end

  def hooked_event(
        "schedule-owner-week-schedule:change_variant",
        %{"owner-key" => owner_key, "direction" => direction},
        socket
      ) do
    {:halt, change_variant(socket, owner_key: owner_key, direction: direction)}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  defp persist_course_change(params, attrs_fun, socket) do
    group_id = socket.assigns.schedule_change_groups_state.active_change_group_id

    cond do
      is_nil(group_id) ->
        {:halt,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           "Select a change group before changing courses."
         )}

      true ->
        case attrs_fun.(params) do
          {:ok, attrs} ->
            ScheduleChangeDomainManager.add_or_update_change(group_id, attrs)
            {:halt, socket}

          {:error, reason} ->
            require Logger
            Logger.error("Invalid week schedule course change payload: #{inspect(reason)}")

            {:halt,
             Phoenix.LiveView.put_flash(
               socket,
               :error,
               "Could not apply that course change. Refresh and try again."
             )}
        end
    end
  end

  defp loaded_state(state, nil) do
    %{state | course_list: nil, week_schedule: nil, loading?: false}
  end

  defp loaded_state(state, []) do
    week_schedule =
      empty_week_schedule(owner_key: state.owner_key)

    %{state | course_list: [], week_schedule: week_schedule, loading?: false}
  end

  defp loaded_state(state, %ScheduleOwnerSchedule{} = course_list) do
    selected_variant_index =
      clamped_variant_index(
        index: state.selected_variant_index || 0,
        course_list: course_list
      )

    courses =
      courses_for_selected_variant(course_list: course_list, index: selected_variant_index)

    week_schedule =
      ScheduleUtils.build_week_schedule(
        type: course_list.type,
        name: course_list.name,
        courses: courses
      )
      |> Map.merge(%{
        program_name: course_list.program_name,
        semester_name: course_list.semester_name,
        schedule_variants: course_list.schedule_variants || []
      })

    %{
      state
      | course_list: course_list,
        week_schedule: week_schedule,
        selected_variant_index: selected_variant_index,
        loading?: false
    }
  end

  defp change_variant(socket, owner_key: owner_key, direction: direction) do
    state = Map.get(socket.assigns.week_schedules, owner_key)

    if is_nil(state) or is_nil(state.course_list) do
      socket
    else
      next_index =
        next_variant_index(
          current_index: state.selected_variant_index || 0,
          direction: direction,
          course_list: state.course_list
        )

      updated_state =
        state
        |> Map.put(:selected_variant_index, next_index)
        |> loaded_state(state.course_list)

      assign(
        socket,
        :week_schedules,
        Map.put(socket.assigns.week_schedules, owner_key, updated_state)
      )
    end
  end

  defp next_variant_index(
         current_index: current_index,
         direction: "previous",
         course_list: course_list
       ) do
    clamped_variant_index(index: current_index - 1, course_list: course_list)
  end

  defp next_variant_index(
         current_index: current_index,
         direction: "next",
         course_list: course_list
       ) do
    clamped_variant_index(index: current_index + 1, course_list: course_list)
  end

  defp next_variant_index(
         current_index: current_index,
         direction: _direction,
         course_list: course_list
       ) do
    clamped_variant_index(index: current_index, course_list: course_list)
  end

  defp courses_for_selected_variant(course_list: course_list, index: index) do
    case Enum.at(course_list.schedule_variants || [], index) do
      %{courses: courses} -> courses
      _variant -> course_list.courses
    end
  end

  defp clamped_variant_index(index: index, course_list: course_list) do
    variant_count = length(course_list.schedule_variants || [])

    cond do
      variant_count <= 1 -> 0
      index < 0 -> 0
      index >= variant_count -> variant_count - 1
      true -> index
    end
  end

  defp variant_count(%{schedule_variants: variants}) when is_list(variants), do: length(variants)
  defp variant_count(_schedule_owner), do: 0

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
