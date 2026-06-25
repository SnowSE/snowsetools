defmodule SnowSeToolsWeb.Scheduling.WeekScheduleGrid do
  use SnowSeToolsWeb, :html

  import SnowSeToolsWeb.Components.{Expandable, HoverTooltip}

  attr :schedule_owner, :map, required: true
  attr :owner_key, :string, required: true

  def schedule_grid(assigns) do
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
              class="absolute right-1  text-[11px] text-slate-500 text-end"
              style={"top: #{label.offset}px"}
            >
              {label.time}
            </div>
          <% end %>
        </div>
      </div>
      <div class="grid min-w-0 flex-1 grid-cols-5 gap-1">
        <%= for day <- ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"] do %>
          <div class="min-w-0">
            <div class="py-2 text-center tracking-wide text-slate-500">
              {String.slice(day, 0, 3)}
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
                  class="absolute left-0 right-0 border-t border-slate-800/55 "
                  style={"top: #{line}px"}
                />
              <% end %>

              <div class="flex flex-col gap-1">
                <%= for meeting <- Map.get(@schedule_owner.meetings_by_day, day, []) do %>
                  <div class="rounded  bg-slate-900 px-1.5 py-1  leading-tight  shadow-sm shadow-black z-10">
                    <.hover_tooltip id={
                        "hover-tooltip-#{:erlang.phash2({@owner_key, meeting.crn, meeting.start_minutes, meeting.end_minutes})}"
                      }>
                      <:label>
                        <div class="overflow-hidden cursor-default">
                          <div class="truncate text-slate-300">{meeting.course_name}</div>
                          <div class="truncate text-slate-400 text-xs">
                            {meeting.subject_code} {meeting.course_number}
                          </div>
                        </div>
                      </:label>
                      <:body>
                        <div class="space-y-1.5">
                          <div class="text-xs font-semibold text-slate-100 truncate">
                            {meeting.course_name}
                          </div>
                          <div class="text-[11px] text-slate-300">
                            {meeting.subject_code} {meeting.course_number}
                          </div>
                          <div class="text-[11px] text-slate-400">
                            {format_minutes(meeting.start_minutes)} – {format_minutes(
                              meeting.end_minutes
                            )}
                          </div>
                          <div :if={meeting.room} class="text-[11px] text-slate-400">
                            {meeting.room}
                          </div>
                          <div :if={meeting.instructors != []} class="text-[11px] text-slate-500">
                            {Enum.join(meeting.instructors, ", ")}
                          </div>
                        </div>
                      </:body>
                    </.hover_tooltip>
                  </div>
                <% end %>
              </div>
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
          <div class="text-xs text-slate-600">{length(@schedule_owner.online_courses)} credits</div>
        </div>
      </:title_row>
      <:body>
        <div class="divide-y divide-slate-800/70 pt-1 max-h-[250px] overflow-auto">
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
