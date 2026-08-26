defmodule SnowSeToolsWeb.Scheduling.WeekSchedule do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView

  alias SnowSeTools.Scheduling.{
    ScheduleChangeDomainManager,
    ScheduleOwnerDomainManager,
    ScheduleOwnerSchedule,
    ScheduleUtils
  }

  alias SnowSeToolsWeb.Scheduling.{CourseChangeIntent, OverlayControls, ScheduleChangeApply}
  import SnowSeToolsWeb.Scheduling.WeekScheduleGrid

  defstruct [
    :selected_term_code,
    :owner_key,
    :course_list,
    :week_schedule,
    :selected_variant_index,
    :loading?
  ]

  def assign_component(socket) do
    socket
    |> assign(:week_schedules, %{})
    |> assign(:week_schedule_edit_course_modal, nil)
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

  attr :state, __MODULE__, required: true
  attr :position, :integer, required: true
  attr :total_count, :integer, required: true
  attr :active_change_group, :map, default: nil
  attr :conflicted_course_crns, :any, default: MapSet.new()
  attr :active_conflicted_course_crns, :any, default: MapSet.new()
  attr :schedule_owners_metadata, :list, default: []
  attr :edit_course_modal, :map, default: nil
  attr :overlay_targets, :list, default: []
  attr :overlay_menu_open?, :boolean, default: false

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
            overlay_targets={@overlay_targets}
            overlay_menu_open?={@overlay_menu_open?}
          />
          <.schedule_grid
            schedule_owner={effective_schedule(@state.week_schedule, @active_change_group)}
            owner_key={@state.owner_key}
            selected_term_code={@state.selected_term_code}
            active_change_group={@active_change_group}
            conflicted_course_crns={@conflicted_course_crns}
            active_conflicted_course_crns={@active_conflicted_course_crns}
          />
        <% end %>
      </div>
    </section>

    <.edit_course_modal
      :if={edit_course_modal_for_owner?(@edit_course_modal, @state.owner_key)}
      modal={@edit_course_modal}
      professor_options={schedule_owner_names(@schedule_owners_metadata, :professor)}
      room_options={schedule_owner_names(@schedule_owners_metadata, :room)}
    />
    """
  end

  attr :modal, :map, required: true
  attr :professor_options, :list, default: []
  attr :room_options, :list, default: []

  defp edit_course_modal(assigns) do
    ~H"""
    <.modal
      id="week-schedule-edit-course-modal"
      on_close="week-schedule-grid:close_edit_course"
      panel_class="relative w-full max-w-xl rounded-xl border border-slate-700 bg-slate-900 p-5 shadow-2xl shadow-slate-950/60"
    >
      <div class="mb-4 flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h3 class="truncate text-base font-semibold text-slate-100">Edit course</h3>
          <p class="mt-1 truncate text-xs text-slate-500">
            {@modal.payload["subject_code"]} {@modal.payload["course_number"]} · {@modal.payload[
              "course_name"
            ]}
          </p>
        </div>
        <button
          type="button"
          id="week-schedule-edit-course-close"
          phx-click="week-schedule-grid:close_edit_course"
          class="rounded-md p-1 text-slate-500 transition-colors hover:bg-slate-800 hover:text-slate-200"
          aria-label="Close edit course modal"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <.form
        for={to_form(%{}, as: :course)}
        id="week-schedule-edit-course-form"
        phx-submit="week-schedule-grid:save_edit_course"
        class="space-y-4"
      >
        <div>
          <div class="mb-2 text-xs font-medium uppercase tracking-wide text-slate-500">
            Meeting days
          </div>
          <div id="week-schedule-edit-course-days" class="grid grid-cols-5 gap-1.5">
            <%= for day <- week_days() do %>
              <label class="group relative">
                <input
                  type="checkbox"
                  name="course[days][]"
                  value={day}
                  checked={day in @modal.days}
                  class="peer sr-only"
                />
                <span class={[
                  "block rounded-md border px-2 py-2 text-center text-xs font-medium transition-colors",
                  "border-slate-700 bg-slate-950/80 text-slate-400 group-hover:border-slate-500 group-hover:text-slate-200",
                  "peer-checked:border-indigo-400 peer-checked:bg-indigo-500/15 peer-checked:text-indigo-200"
                ]}>
                  {String.slice(day, 0, 3)}
                </span>
              </label>
            <% end %>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-3">
          <label class="block">
            <span class="mb-1 block text-xs font-medium text-slate-400">Start time</span>
            <input
              id="week-schedule-edit-course-start-time"
              type="time"
              name="course[start_time]"
              value={@modal.start_time}
              required
              class="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
            />
          </label>
          <label class="block">
            <span class="mb-1 block text-xs font-medium text-slate-400">End time</span>
            <input
              id="week-schedule-edit-course-end-time"
              type="time"
              name="course[end_time]"
              value={@modal.end_time}
              required
              class="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
            />
          </label>
        </div>

        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <label class="block">
            <span class="mb-1 block text-xs font-medium text-slate-400">Professor</span>
            <input
              id="week-schedule-edit-course-professor"
              type="search"
              name="course[target_professor]"
              value={@modal.target_professor}
              list="week-schedule-edit-course-professor-options"
              autocomplete="off"
              class="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
            />
            <datalist id="week-schedule-edit-course-professor-options">
              <%= for professor <- @professor_options do %>
                <option value={professor}></option>
              <% end %>
            </datalist>
          </label>
          <label class="block">
            <span class="mb-1 block text-xs font-medium text-slate-400">Room</span>
            <input
              id="week-schedule-edit-course-room"
              type="search"
              name="course[target_room]"
              value={@modal.target_room}
              list="week-schedule-edit-course-room-options"
              autocomplete="off"
              class="w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
            />
            <datalist id="week-schedule-edit-course-room-options">
              <%= for room <- @room_options do %>
                <option value={room}></option>
              <% end %>
            </datalist>
          </label>
        </div>

        <div
          :if={@modal.error}
          class="rounded-lg border border-red-500/40 bg-red-950/40 px-3 py-2 text-sm text-red-200"
        >
          {@modal.error}
        </div>

        <div class="flex justify-end gap-2 pt-1">
          <button
            type="button"
            id="week-schedule-edit-course-cancel"
            phx-click="week-schedule-grid:close_edit_course"
            class="rounded-lg border border-slate-700 px-3 py-2 text-sm font-medium text-slate-300 transition-colors hover:bg-slate-800 hover:text-slate-100"
          >
            Cancel
          </button>
          <button
            type="submit"
            id="week-schedule-edit-course-save"
            class="rounded-lg bg-indigo-500 px-3 py-2 text-sm font-semibold text-white transition-colors hover:bg-indigo-400"
          >
            Save course
          </button>
        </div>
      </.form>
    </.modal>
    """
  end

  attr :schedule_owner, :map, required: true
  attr :owner_key, :string, required: true
  attr :position, :integer, required: true
  attr :total_count, :integer, required: true
  attr :selected_variant_index, :integer, default: 0
  attr :overlay_targets, :list, default: []
  attr :overlay_menu_open?, :boolean, default: false

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
        <OverlayControls.overlay_with_menu
          :if={@overlay_targets != []}
          id={"overlay-menu-#{@owner_key}"}
          entry_key={@owner_key}
          owner_type={@schedule_owner.type}
          targets={@overlay_targets}
          open?={@overlay_menu_open?}
        />
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

  def hooked_event("week-schedule-grid:open_edit_course", params, socket) do
    {:halt, open_edit_course_modal(socket, params)}
  end

  def hooked_event("week-schedule-grid:close_edit_course", _params, socket) do
    {:halt, assign(socket, :week_schedule_edit_course_modal, nil)}
  end

  def hooked_event("week-schedule-grid:save_edit_course", %{"course" => course_params}, socket) do
    save_edit_course_modal(socket, course_params)
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

  defp open_edit_course_modal(socket, params) do
    group_id = socket.assigns.schedule_change_groups_state.active_change_group_id

    if is_nil(group_id) do
      Phoenix.LiveView.put_flash(
        socket,
        :error,
        "Select a change group before changing courses."
      )
    else
      case edit_modal_from_payload(params) do
        {:ok, modal} ->
          assign(socket, :week_schedule_edit_course_modal, modal)

        {:error, reason} ->
          Logger.error("Invalid week schedule edit course payload: #{inspect(reason)}")

          Phoenix.LiveView.put_flash(
            socket,
            :error,
            "Could not open that course editor. Refresh and try again."
          )
      end
    end
  end

  defp save_edit_course_modal(socket, course_params) do
    modal = socket.assigns.week_schedule_edit_course_modal
    group_id = socket.assigns.schedule_change_groups_state.active_change_group_id

    cond do
      is_nil(modal) ->
        Logger.warning("Ignored edit course save with no open modal")
        {:halt, socket}

      is_nil(group_id) ->
        {:halt, update_edit_course_modal_error(socket, "Select a change group before saving.")}

      true ->
        with {:ok, params} <- edit_course_params(modal, course_params),
             {:ok, attrs} <- CourseChangeIntent.edit_course_attrs(params) do
          ScheduleChangeDomainManager.add_or_update_change(group_id, attrs)
          {:halt, assign(socket, :week_schedule_edit_course_modal, nil)}
        else
          {:error, reason} ->
            Logger.error("Invalid week schedule edit course form: #{inspect(reason)}")
            {:halt, update_edit_course_modal_error(socket, edit_course_error_message(reason))}
        end
    end
  end

  defp edit_modal_from_payload(params) do
    with {:ok, owner_key} <- fetch_string(params, "owner_key"),
         {:ok, _crn} <- fetch_string(params, "crn"),
         {:ok, meeting} <- modal_meeting(params) do
      days = Map.get(meeting, "days", []) |> Enum.filter(&is_binary/1)

      {:ok,
       %{
         owner_key: owner_key,
         payload: params,
         days: days,
         start_time:
           normalize_time(Map.get(meeting, "start_time") || Map.get(params, "start_time")),
         end_time: normalize_time(Map.get(meeting, "end_time") || Map.get(params, "end_time")),
         target_professor: first_instructor(params),
         target_room: ScheduleUtils.room_name(meeting: meeting) || "",
         error: nil
       }}
    end
  end

  defp modal_meeting(%{"meeting" => %{} = meeting}), do: {:ok, meeting}
  defp modal_meeting(_params), do: {:error, :missing_meeting}

  defp edit_course_params(modal, course_params) do
    days = Map.get(course_params, "days", []) |> List.wrap() |> Enum.filter(&(&1 in week_days()))
    start_time = Map.get(course_params, "start_time", "")
    end_time = Map.get(course_params, "end_time", "")

    cond do
      days == [] ->
        {:error, :missing_days}

      start_time == "" or end_time == "" ->
        {:error, :missing_time}

      time_minutes(start_time) >= time_minutes(end_time) ->
        {:error, :invalid_time_range}

      true ->
        {:ok,
         Map.merge(modal.payload, %{
           "days" => days,
           "start_time" => start_time,
           "end_time" => end_time,
           "target_professor" => Map.get(course_params, "target_professor", ""),
           "target_room" => Map.get(course_params, "target_room", "")
         })}
    end
  end

  defp update_edit_course_modal_error(socket, message) do
    update(socket, :week_schedule_edit_course_modal, fn
      nil -> nil
      modal -> %{modal | error: message}
    end)
  end

  defp edit_course_error_message(:missing_days), do: "Select at least one meeting day."
  defp edit_course_error_message(:missing_time), do: "Enter a start and end time."
  defp edit_course_error_message(:invalid_time_range), do: "End time must be after start time."

  defp edit_course_error_message(_reason),
    do: "Could not save this course. Check the form and try again."

  defp edit_course_modal_for_owner?(%{owner_key: owner_key}, owner_key), do: true
  defp edit_course_modal_for_owner?(_modal, _owner_key), do: false

  defp schedule_owner_names(schedule_owners_metadata, type) do
    schedule_owners_metadata
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.name)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp first_instructor(params) do
    params
    |> Map.get("instructors", [])
    |> List.wrap()
    |> Enum.find("", &is_binary/1)
  end

  defp normalize_time(<<hour::binary-size(2), ":", minute::binary-size(2), _rest::binary>>),
    do: "#{hour}:#{minute}"

  defp normalize_time(_time), do: ""

  defp fetch_string(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_string, key}}
    end
  end

  defp time_minutes(<<hour::binary-size(2), ":", minute::binary-size(2), _rest::binary>>) do
    with {hour, ""} <- Integer.parse(hour),
         {minute, ""} <- Integer.parse(minute) do
      hour * 60 + minute
    else
      _other -> 0
    end
  end

  defp time_minutes(_time), do: 0

  defp week_days, do: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

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

  def effective_schedule(schedule_owner, nil), do: schedule_owner

  def effective_schedule(schedule_owner, active_change_group) do
    ScheduleChangeApply.effective_schedule(schedule_owner, active_change_group)
  end
end
