defmodule SnowSeToolsWeb.Scheduling.WeekScheduleGrid do
  use SnowSeToolsWeb, :html

  import SnowSeToolsWeb.Components.Expandable

  attr :schedule_owner, :map, required: true
  attr :owner_key, :string, required: true

  def schedule_grid(assigns) do
    days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

    assigns =
      assigns
      |> assign(:days, days)

    ~H"""
    <div class="flex gap-2">
      <div class="w-14 pt-[2.05rem]">
        <div
          class="relative"
          style={"height: #{grid_height(start_minutes: @schedule_owner.start_minutes, end_minutes: @schedule_owner.end_minutes)}px"}
        >
          <%= for label <- time_labels(
            start_minutes: @schedule_owner.start_minutes,
            end_minutes: @schedule_owner.end_minutes
          ) do %>
            <div
              class="absolute right-1 -translate-y-1/2 text-[11px] text-slate-500 text-end"
              style={"top: #{label.offset}px"}
            >
              {label.time}
            </div>
          <% end %>
        </div>
      </div>
      <div class="grid min-w-0 flex-1 grid-cols-5 gap-px">
        <%= for day <- @days do %>
          <div class="min-w-0">
            <div class="py-2 text-center text-xs tracking-wide text-slate-500">
              {day}
            </div>
            <div
              class="relative bg-slate-950/20"
              style={"height: #{grid_height(start_minutes: @schedule_owner.start_minutes, end_minutes: @schedule_owner.end_minutes)}px"}
            >
              <%= for line <- grid_lines(
                start_minutes: @schedule_owner.start_minutes,
                end_minutes: @schedule_owner.end_minutes
              ) do %>
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

    <.expandable
      :if={@schedule_owner.online_courses != []}
      id={"online-courses-#{@owner_key}"}
      class="mt-3"
    >
      <:title_row>
        <div class="flex items-center justify-between gap-2">
          <div class="text-xs font-medium uppercase tracking-wide text-slate-500">Online</div>
          <div class="text-xs text-slate-600">{length(@schedule_owner.online_courses)}</div>
        </div>
      </:title_row>
      <:body>
        <div class="divide-y divide-slate-800/70 pt-1">
          <%= for course <- @schedule_owner.online_courses do %>
            <div class="grid grid-cols-[5.5rem_1fr] gap-2 py-1.5 text-xs">
              <div class="font-medium text-slate-300">
                {course["subject_code"]} {course["course_number"]}
              </div>
              <div class="min-w-0 truncate text-slate-500">{course["name"]}</div>
            </div>
          <% end %>
        </div>
      </:body>
    </.expandable>
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
