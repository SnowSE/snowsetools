defmodule SnowSeToolsWeb.Scheduling.OverlayGroup do
  @moduledoc """
  A card that draws several same-kind schedules on one week grid, each member
  in its own color. Members can be popped back out to solo cards.
  """
  use SnowSeToolsWeb, :html

  alias SnowSeToolsWeb.Scheduling.{OverlayControls, ScheduleOverlays, WeekSchedule}
  import SnowSeToolsWeb.Scheduling.WeekScheduleGrid

  @days ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  attr :group_key, :string, required: true
  attr :member_keys, :list, required: true
  attr :week_schedules, :map, required: true
  attr :position, :integer, required: true
  attr :total_count, :integer, required: true
  attr :active_change_group, :map, default: nil
  attr :conflicted_course_crns, :any, default: MapSet.new()
  attr :active_conflicted_course_crns, :any, default: MapSet.new()
  attr :overlay_targets, :list, default: []
  attr :overlay_menu_open?, :boolean, default: false

  def render(assigns) do
    members =
      members(
        member_keys: assigns.member_keys,
        week_schedules: assigns.week_schedules,
        active_change_group: assigns.active_change_group
      )

    type = group_type(members)

    assigns =
      assigns
      |> assign(:members, members)
      |> assign(:type, type)
      |> assign(:merged_schedule, merged_schedule(members: members, type: type))
      |> assign(:selected_term_code, selected_term_code(members))

    ~H"""
    <section
      id={"selected-schedule-#{@group_key}"}
      data-schedule-card
      data-schedule-key={@group_key}
      draggable="true"
      tabindex="0"
      class={[
        "relative w-[700px] p-3",
        "select-none cursor-grab motion-safe:transition-[transform,opacity,box-shadow,border-color,background-color] motion-safe:duration-200 motion-safe:ease-out active:cursor-grabbing",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-400/60 focus-visible:ring-offset-2 focus-visible:ring-offset-slate-950"
      ]}
    >
      <div class="rounded-lg border border-slate-800/80 bg-slate-950/55 p-3 shadow-sm shadow-slate-950/20 h-full">
        <div class="mb-2 grid grid-cols-[1fr_auto] items-start gap-3">
          <div class="min-w-0">
            <h2 class="truncate text-base font-semibold leading-tight text-slate-100">
              {Enum.map_join(@members, ", ", & &1.name)}
            </h2>
            <p class="text-xs text-slate-500">
              Overlay · {length(@members)} {ScheduleOverlays.kind_label(
                type: @type,
                count: length(@members)
              )}
            </p>
          </div>
          <div class="flex items-center gap-1">
            <OverlayControls.overlay_with_menu
              :if={@overlay_targets != []}
              id={"overlay-menu-#{@group_key}"}
              entry_key={@group_key}
              owner_type={@type}
              targets={@overlay_targets}
              open?={@overlay_menu_open?}
              label="Add"
            />
            <button
              type="button"
              id={"overlay-separate-#{@group_key}"}
              phx-click="schedule-details-order:separate_all"
              phx-value-group={@group_key}
              class="inline-flex items-center gap-1.5 rounded-md border border-slate-700 px-2.5 py-1 text-xs font-medium text-slate-300 transition-colors hover:bg-slate-800 hover:text-slate-100"
            >
              <.icon name="hero-arrows-pointing-out" class="size-3.5" /> Separate
            </button>
            <button
              type="button"
              phx-click="schedule-details-order:move_schedule"
              phx-value-key={@group_key}
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
              phx-value-key={@group_key}
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
              phx-value-key={@group_key}
              class="rounded p-1 text-slate-500 transition-colors"
              aria-label="Close all schedules in this overlay"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
        </div>

        <div class="mb-2 flex flex-wrap gap-1.5">
          <%= for member <- @members do %>
            <span
              id={"overlay-member-#{:erlang.phash2({@group_key, member.key})}"}
              class="inline-flex items-center gap-1.5 rounded-full border border-slate-700 bg-slate-900 py-0.5 pl-1.5 pr-1 text-xs text-slate-200"
            >
              <span class={["size-2.5 rounded-full", member.color.dot]} />
              {member.name}
              <span :if={member.loading?} class="text-slate-500">…</span>
              <button
                type="button"
                phx-click="schedule-details-order:pop_out"
                phx-value-group={@group_key}
                phx-value-key={member.key}
                class="rounded-full p-0.5 text-slate-500 transition-colors hover:bg-slate-800 hover:text-slate-200"
                aria-label={"Pop #{member.name} out of this overlay"}
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </span>
          <% end %>
        </div>

        <.schedule_grid
          schedule_owner={@merged_schedule}
          owner_key={@group_key}
          selected_term_code={@selected_term_code}
          active_change_group={@active_change_group}
          conflicted_course_crns={@conflicted_course_crns}
          active_conflicted_course_crns={@active_conflicted_course_crns}
        />
      </div>
    </section>
    """
  end

  @doc """
  Merges the members' week schedules into one grid-ready map. Each meeting is
  tagged with its member's color and owner so the grid can color it and so
  drag/edit still target the right schedule.
  """
  def merged_schedule(members: members, type: type) do
    loaded = Enum.filter(members, &(&1.schedule != nil))

    meetings_by_day =
      Map.new(@days, fn day ->
        meetings =
          loaded
          |> Enum.flat_map(fn member ->
            member.schedule.meetings_by_day
            |> Map.get(day, [])
            |> Enum.map(
              &Map.merge(&1, %{
                overlay_color: member.color,
                overlay_owner_key: member.key,
                overlay_owner_type: member.schedule.type,
                overlay_owner_name: member.name
              })
            )
          end)
          |> Enum.sort_by(& &1.start_minutes)

        {day, meetings}
      end)

    {start_minutes, end_minutes} =
      case loaded do
        [] ->
          {8 * 60, 17 * 60}

        _ ->
          {Enum.min_by(loaded, & &1.schedule.start_minutes).schedule.start_minutes,
           Enum.max_by(loaded, & &1.schedule.end_minutes).schedule.end_minutes}
      end

    %{
      type: type,
      name: Enum.map_join(members, ", ", & &1.name),
      start_minutes: start_minutes,
      end_minutes: end_minutes,
      meetings_by_day: meetings_by_day,
      online_courses: []
    }
  end

  defp members(
         member_keys: member_keys,
         week_schedules: week_schedules,
         active_change_group: group
       ) do
    member_keys
    |> Enum.with_index()
    |> Enum.map(fn {key, index} ->
      state = Map.get(week_schedules, key)

      schedule =
        case state do
          %WeekSchedule{week_schedule: %{} = schedule} ->
            WeekSchedule.effective_schedule(schedule, group)

          _ ->
            nil
        end

      %{
        key: key,
        color: ScheduleOverlays.member_color(index),
        name: member_name(key, schedule),
        schedule: schedule,
        loading?: is_nil(schedule),
        selected_term_code: state && state.selected_term_code
      }
    end)
  end

  defp member_name(_key, %{type: :academic_program_semester} = schedule),
    do: "#{schedule.program_name} · #{schedule.semester_name}"

  defp member_name(_key, %{name: name}) when is_binary(name), do: name
  defp member_name(key, _schedule), do: key |> String.split(":", parts: 2) |> List.last()

  defp group_type(members) do
    Enum.find_value(members, :room, fn
      %{schedule: %{type: type}} -> type
      %{key: "professor:" <> _} -> :professor
      %{key: "room:" <> _} -> :room
      %{key: "academic_program_semester:" <> _} -> :academic_program_semester
      _ -> nil
    end)
  end

  defp selected_term_code(members),
    do: Enum.find_value(members, & &1.selected_term_code)
end
