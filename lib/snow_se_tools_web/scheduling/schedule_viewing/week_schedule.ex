defmodule SnowSeToolsWeb.Scheduling.WeekSchedule do
  use SnowSeToolsWeb, :html

  @days ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  attr :schedule_owner, :map, required: true

  def render(assigns) do
    assigns =
      assigns
      |> assign(:days, @days)
      |> assign(
        :time_labels,
        time_labels(
          start_minutes: assigns.schedule_owner.start_minutes,
          end_minutes: assigns.schedule_owner.end_minutes
        )
      )

    ~H"""
    <section
      id={"selected-schedule-#{@schedule_owner.dom_id}"}
      class="w-[700px] rounded-lg border border-slate-800/80 bg-slate-950/55 px-3 pb-3 pt-2.5 shadow-sm shadow-slate-950/20"
    >
      <div class="mb-2 grid grid-cols-[1fr_auto] items-start gap-3">
        <div class="min-w-0 text-center">
          <h2 class="truncate text-base font-semibold leading-tight text-slate-100">
            {@schedule_owner.name}
            <span class="ml-1 text-xs font-medium text-slate-500">{@schedule_owner.credit_count}</span>
          </h2>
          <p class="sr-only">
            {@schedule_owner.type_label} schedule
          </p>
        </div>
        <button
          type="button"
          phx-click="schedule-viewer:close_schedule"
          phx-value-key={@schedule_owner.key}
          class="rounded p-1 text-slate-500 transition hover:bg-slate-900 hover:text-slate-200"
          aria-label="Remove schedule"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>

      <.schedule_grid schedule_owner={@schedule_owner} />
    </section>
    """
  end

  attr :schedule_owner, :map, required: true

  def schedule_grid(assigns) do
    assigns =
      assigns
      |> assign(:days, @days)
      |> assign(
        :time_labels,
        time_labels(
          start_minutes: assigns.schedule_owner.start_minutes,
          end_minutes: assigns.schedule_owner.end_minutes
        )
      )
      |> assign(
        :grid_lines,
        grid_lines(
          start_minutes: assigns.schedule_owner.start_minutes,
          end_minutes: assigns.schedule_owner.end_minutes
        )
      )

    ~H"""
    <div class="flex gap-2">
      <div class="w-14 pt-[2.05rem]">
        <div
          class="relative"
          style={"height: #{grid_height(start_minutes: @schedule_owner.start_minutes, end_minutes: @schedule_owner.end_minutes)}px"}
        >
          <%= for label <- @time_labels do %>
            <div
              class="absolute right-1 -translate-y-1/2 text-[11px] text-slate-500  text-end"
              style={"top: #{label.offset}px"}
            >
              {label.time}
            </div>
          <% end %>
        </div>
      </div>
      <div class="grid min-w-0 flex-1 grid-cols-5 gap-px ">
        <%= for day <- @days do %>
          <div class="min-w-0">
            <div class=" py-2 text-center text-xs tracking-wide text-slate-500">
              {day}
            </div>
            <div
              class="relative bg-slate-950/20"
              style={"height: #{grid_height(start_minutes: @schedule_owner.start_minutes, end_minutes: @schedule_owner.end_minutes)}px"}
            >
              <%= for line <- @grid_lines do %>
                <div
                  class="absolute left-0 right-0 border-t border-slate-800/55"
                  style={"top: #{line}px"}
                />
              <% end %>

              <%= for meeting <- Map.get(@schedule_owner.meetings_by_day, day, []) do %>
                <div
                  class="absolute left-1 right-1 overflow-hidden rounded border border-slate-600/80 bg-slate-800/95 px-1.5 py-1 text-xs leading-tight text-slate-100 shadow-sm shadow-slate-950/25"
                  style={
                    meeting_style(meeting: meeting, day_start_minutes: @schedule_owner.start_minutes)
                  }
                  title={meeting_title(meeting)}
                >
                  <div class="truncate font-medium">{meeting.course_name}</div>
                  <div class="truncate text-[11px] text-slate-400">
                    {meeting.subject_code} {meeting.course_number}
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>

    <div
      :if={@schedule_owner.online_courses != []}
      class="mt-3 border-t border-slate-800/80 pt-2"
    >
      <div class="mb-1.5 flex items-center justify-between gap-2">
        <div class="text-xs font-medium uppercase tracking-wide text-slate-500">Online</div>
        <div class="text-xs text-slate-600">{length(@schedule_owner.online_courses)}</div>
      </div>
      <div class="divide-y divide-slate-800/70">
        <%= for course <- @schedule_owner.online_courses do %>
          <div class="grid grid-cols-[5.5rem_1fr] gap-2 py-1.5 text-xs">
            <div class="font-medium text-slate-300">
              {course["subject_code"]} {course["course_number"]}
            </div>
            <div class="min-w-0 truncate text-slate-500">{course["name"]}</div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp time_labels(start_minutes: start_minutes, end_minutes: end_minutes) do
    start_minutes
    |> Stream.iterate(&(&1 + 60))
    |> Enum.take_while(&(&1 <= end_minutes))
    |> Enum.map(fn minutes ->
      %{time: format_minutes(minutes), offset: minutes - start_minutes}
    end)
  end

  defp grid_height(start_minutes: start_minutes, end_minutes: end_minutes),
    do: max(end_minutes - start_minutes, 60)

  defp grid_lines(start_minutes: start_minutes, end_minutes: end_minutes) do
    start_minutes
    |> Stream.iterate(&(&1 + 30))
    |> Enum.take_while(&(&1 <= end_minutes))
    |> Enum.map(&(&1 - start_minutes))
  end

  defp meeting_style(meeting: meeting, day_start_minutes: day_start_minutes) do
    top = meeting.start_minutes - day_start_minutes
    height = max(meeting.end_minutes - meeting.start_minutes, 24)
    "top: #{top}px; height: #{height}px"
  end

  defp meeting_title(meeting) do
    [
      "#{meeting.subject_code} #{meeting.course_number}",
      meeting.course_name,
      meeting.room,
      Enum.join(meeting.instructors, ", ")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp format_minutes(minutes) do
    minutes
    |> then(fn value ->
      hour = div(value, 60)
      minute = rem(value, 60)

      "#{String.pad_leading(to_string(hour), 2, "0")}:#{String.pad_leading(to_string(minute), 2, "0")}"
    end)
    |> format_clock()
  end

  defp format_clock(<<hour::binary-size(2), ":", minute::binary-size(2)>>) do
    {hour, ""} = Integer.parse(hour)
    period = if hour >= 12, do: "PM", else: "AM"
    display_hour = hour |> rem(12) |> then(&if(&1 == 0, do: 12, else: &1))
    "#{display_hour}:#{minute} #{period}"
  end

  defp format_clock(time), do: time
end
