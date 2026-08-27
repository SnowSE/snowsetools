defmodule SnowSeToolsWeb.Scheduling.WeekScheduleGrid do
  use SnowSeToolsWeb, :html

  import SnowSeToolsWeb.Components.{Expandable, HoverTooltip}

  attr :schedule_owner, :map, required: true
  attr :owner_key, :string, required: true
  attr :selected_term_code, :string, required: true
  attr :active_change_group, :map, default: nil
  attr :conflicted_course_crns, :any, default: MapSet.new()
  attr :active_conflicted_course_crns, :any, default: MapSet.new()
  attr :minute_scale, :float, default: 1.0

  def schedule_grid(assigns) do
    ~H"""
    <div
      id={schedule_grid_id(@owner_key)}
      class="flex gap-2"
      phx-hook=".WeekScheduleGridDrag"
      data-owner-key={@owner_key}
      data-owner-type={@schedule_owner.type}
      data-owner-name={@schedule_owner.name}
      data-start-minutes={@schedule_owner.start_minutes}
      data-end-minutes={@schedule_owner.end_minutes}
      data-minute-scale={@minute_scale}
    >
      <div class="w-14 pt-[2.05rem]">
        <div
          class="relative"
          style={"height: #{grid_height(start_minutes: @schedule_owner.start_minutes, end_minutes: @schedule_owner.end_minutes, scale: @minute_scale)}px"}
        >
          <%= for label <- time_labels(start_minutes: @schedule_owner.start_minutes, end_minutes: @schedule_owner.end_minutes, scale: @minute_scale) do %>
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
              data-week-schedule-day={day}
              style={"height: #{grid_height(start_minutes: @schedule_owner.start_minutes, end_minutes: @schedule_owner.end_minutes, scale: @minute_scale)}px"}
            >
              <%= for line <- grid_lines(start_minutes: @schedule_owner.start_minutes, end_minutes: @schedule_owner.end_minutes, scale: @minute_scale) do %>
                <div
                  class="absolute left-0 right-0 border-t border-slate-800/55 "
                  style={"top: #{line}px"}
                />
              <% end %>

              <%= for meeting <- positioned_meetings(
                meetings: Map.get(@schedule_owner.meetings_by_day, day, [])
              ) do %>
                <% source = Map.get(meeting, "__source", :base) %>
                <% conflicted? =
                  meeting_conflicted?(
                    meeting: meeting,
                    conflicted_course_crns: @conflicted_course_crns,
                    active_conflicted_course_crns: @active_conflicted_course_crns
                  ) %>
                <% overlay_color = Map.get(meeting, :overlay_color) %>
                <div
                  class={[
                    "absolute z-10 rounded px-1.5 py-1 leading-tight shadow-sm shadow-black cursor-move transition-colors hover:bg-slate-800",
                    conflicted? && "bg-rose-950/40 ring-1 ring-rose-500/50",
                    !conflicted? && source == :added && "bg-emerald-950/60 ring-1 ring-emerald-500/50",
                    !conflicted? && source == :updated && "bg-amber-950/40 ring-1 ring-amber-500/50",
                    !conflicted? && source == :base && is_nil(overlay_color) && "bg-slate-900",
                    !conflicted? && source == :base && overlay_color && overlay_color.block
                  ]}
                  draggable="true"
                  data-week-schedule-course
                  data-week-schedule-conflicted={to_string(conflicted?)}
                  data-owner-key={Map.get(meeting, :overlay_owner_key)}
                  data-owner-type={Map.get(meeting, :overlay_owner_type)}
                  data-owner-name={Map.get(meeting, :overlay_owner_name)}
                  data-course-payload={
                    course_payload_json(
                      meeting: meeting,
                      selected_term_code: @selected_term_code
                    )
                  }
                  style={
                    meeting_style(
                      meeting: meeting,
                      schedule_start_minutes: @schedule_owner.start_minutes,
                      scale: @minute_scale
                    )
                  }
                >
                  <.hover_tooltip id={
                      "hover-tooltip-#{:erlang.phash2({@owner_key, day, meeting.crn, meeting.start_minutes, meeting.end_minutes})}"
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
                        <div
                          :if={Map.get(meeting, :overlay_owner_name)}
                          class="flex items-center gap-1.5 text-[11px] text-slate-300"
                        >
                          <span class={["size-2 rounded-full", overlay_color && overlay_color.dot]} />
                          {Map.get(meeting, :overlay_owner_name)}
                        </div>
                        <div
                          :if={length(grouped_crns(meeting: meeting)) > 1}
                          class="text-[11px] text-slate-300"
                        >
                          {length(grouped_crns(meeting: meeting))} CRNs: {Enum.join(
                            grouped_crns(meeting: meeting),
                            ", "
                          )}
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

    <script :type={Phoenix.LiveView.ColocatedHook} name=".WeekScheduleGridDrag">
      export default {
        mounted() {
          this.dragPayload = null;
          this.hoverIndicator = null;
          this.menu = null;

          this.onDragStart = (event) => {
            const card = event.target.closest("[data-week-schedule-course]");
            if (!card || !this.el.contains(card)) return;

            event.stopPropagation();
            this.dragPayload = { ...this.coursePayload(card), ...this.ownerFor(card) };

            if (event.dataTransfer) {
              event.dataTransfer.effectAllowed = "move";
              event.dataTransfer.setData("application/json", JSON.stringify(this.dragPayload));
              event.dataTransfer.setData("text/plain", "week-schedule-course");
            }
          };

          this.onDragOver = (event) => {
            const payload = this.currentDragPayload(event);
            if (!payload) return;

            const dayColumn = event.target.closest("[data-week-schedule-day]");
            if (!dayColumn || !this.el.contains(dayColumn)) return;

            event.preventDefault();
            event.stopPropagation();

            if (event.dataTransfer) {
              event.dataTransfer.dropEffect = "move";
            }

            const drop = this.dropDetails(event, dayColumn);
            this.showHoverIndicator(dayColumn, drop.top, drop.time);
          };

          this.onDragLeave = (event) => {
            if (!this.el.contains(event.relatedTarget)) {
              this.clearHoverIndicator();
            }
          };

          this.onDrop = (event) => {
            const dayColumn = event.target.closest("[data-week-schedule-day]");
            const payload = this.currentDragPayload(event);
            if (!payload || !dayColumn || !this.el.contains(dayColumn)) return;

            event.preventDefault();
            event.stopPropagation();

            const drop = this.dropDetails(event, dayColumn);

            this.pushEvent("week-schedule-grid:move_course", {
              ...this.ownerFor(null),
              ...payload,
              target_day: dayColumn.dataset.weekScheduleDay,
              target_time: drop.time,
            });

            this.dragPayload = null;
            this.clearHoverIndicator();
          };

          this.onDragEnd = () => {
            this.dragPayload = null;
            this.clearHoverIndicator();
          };

          this.onContextMenu = (event) => {
            const card = event.target.closest("[data-week-schedule-course]");
            if (!card || !this.el.contains(card)) return;

            event.preventDefault();
            event.stopPropagation();
            this.openMenu(event, { ...this.coursePayload(card), ...this.ownerFor(card) });
          };

          this.onDocumentClick = (event) => {
            if (this.menu && !this.menu.contains(event.target)) {
              this.closeMenu();
            }
          };

          this.el.addEventListener("dragstart", this.onDragStart);
          this.el.addEventListener("dragover", this.onDragOver);
          this.el.addEventListener("dragleave", this.onDragLeave);
          this.el.addEventListener("drop", this.onDrop);
          this.el.addEventListener("dragend", this.onDragEnd);
          this.el.addEventListener("contextmenu", this.onContextMenu);
          document.addEventListener("click", this.onDocumentClick);
        },

        destroyed() {
          this.el.removeEventListener("dragstart", this.onDragStart);
          this.el.removeEventListener("dragover", this.onDragOver);
          this.el.removeEventListener("dragleave", this.onDragLeave);
          this.el.removeEventListener("drop", this.onDrop);
          this.el.removeEventListener("dragend", this.onDragEnd);
          this.el.removeEventListener("contextmenu", this.onContextMenu);
          document.removeEventListener("click", this.onDocumentClick);
          this.clearHoverIndicator();
          this.closeMenu();
        },

        coursePayload(card) {
          return JSON.parse(card.dataset.coursePayload);
        },
        ownerFor(card) {
          const source = card && card.dataset.ownerKey ? card.dataset : this.el.dataset;
          return {
            owner_key: source.ownerKey,
            owner_type: source.ownerType,
            owner_name: source.ownerName,
          };
        },

        currentDragPayload(event) {
          if (this.dragPayload) return this.dragPayload;

          if (!event.dataTransfer) return null;

          const json = event.dataTransfer.getData("application/json");
          if (!json) return null;

          try {
            return JSON.parse(json);
          } catch (_error) {
            return null;
          }
        },

        dropDetails(event, dayColumn) {
          const rect = dayColumn.getBoundingClientRect();
          const startMinutes = Number(this.el.dataset.startMinutes);
          const endMinutes = Number(this.el.dataset.endMinutes);
          const totalMinutes = Math.max(endMinutes - startMinutes, 60);
          const rawMinutes = startMinutes + ((event.clientY - rect.top) / rect.height) * totalMinutes;
          const roundedMinutes = Math.max(startMinutes, Math.min(endMinutes, Math.round(rawMinutes / 30) * 30));
          const top = ((roundedMinutes - startMinutes) / totalMinutes) * rect.height;
          return { top, time: this.formatTime(roundedMinutes) };
        },

        formatTime(minutes) {
          const hours = Math.floor(minutes / 60).toString().padStart(2, "0");
          const mins = (minutes % 60).toString().padStart(2, "0");
          return `${hours}:${mins}`;
        },

        showHoverIndicator(dayColumn, top, time) {
          if (!this.hoverIndicator) {
            this.hoverIndicator = document.createElement("div");
            this.hoverIndicator.className = "absolute left-0 right-0 z-50 pointer-events-none";
            this.hoverIndicator.innerHTML =
              '<div class="relative"><div class="absolute left-0 right-0 h-0.5 bg-indigo-300/70"></div><div data-time-label class="absolute left-1 -top-3 rounded bg-indigo-500 px-1.5 py-0.5 text-[10px] font-medium text-white shadow-lg"></div></div>';
          }

          this.hoverIndicator.style.top = `${top}px`;
          this.hoverIndicator.querySelector("[data-time-label]").textContent = time;

          if (this.hoverIndicator.parentElement !== dayColumn) {
            dayColumn.appendChild(this.hoverIndicator);
          }
        },

        clearHoverIndicator() {
          if (this.hoverIndicator) {
            this.hoverIndicator.remove();
          }
        },

        openMenu(event, payload) {
          this.closeMenu();
          this.menu = document.createElement("div");
          this.menu.className = "fixed z-[1000] w-40 overflow-hidden rounded-md border border-slate-700 bg-slate-950 text-xs text-slate-200 shadow-2xl";
          this.menu.style.left = `${event.clientX}px`;
          this.menu.style.top = `${event.clientY}px`;
          this.menu.innerHTML =
            '<button type="button" data-action="edit" class="block w-full px-3 py-2 text-left hover:bg-slate-800">Edit course</button><button type="button" data-action="delete" class="block w-full px-3 py-2 text-left text-red-300 hover:bg-red-950/60">Remove course</button>';

          this.menu.addEventListener("click", (menuEvent) => {
            const action = menuEvent.target.closest("button")?.dataset.action;
            if (action === "edit") this.editCourse(payload);
            if (action === "delete") this.deleteCourse(payload);
            this.closeMenu();
          });

          document.body.appendChild(this.menu);
        },

        closeMenu() {
          if (this.menu) {
            this.menu.remove();
            this.menu = null;
          }
        },

        editCourse(payload) {
          this.pushEvent("week-schedule-grid:open_edit_course", {
            ...this.ownerFor(null),
            ...payload,
          });
        },

        deleteCourse(payload) {
          if (!window.confirm(`Remove ${payload.course_name} from this change group view?`)) return;

          this.pushEvent("week-schedule-grid:delete_course", {
            ...this.ownerFor(null),
            ...payload,
          });
        },
      };
    </script>
    """
  end

  defp time_labels(start_minutes: start_minutes, end_minutes: end_minutes, scale: scale) do
    (start_minutes + 30)
    |> Stream.iterate(&(&1 + 60))
    |> Enum.take_while(&(&1 <= end_minutes))
    |> Enum.map(fn minutes ->
      %{time: format_minutes(minutes), offset: px(minutes - start_minutes, scale)}
    end)
  end

  defp grid_height(start_minutes: start_minutes, end_minutes: end_minutes, scale: scale),
    do: px(max(end_minutes - start_minutes, 60), scale)

  defp grid_lines(start_minutes: start_minutes, end_minutes: end_minutes, scale: scale) do
    start_minutes
    |> Stream.iterate(&(&1 + 30))
    |> Enum.take_while(&(&1 <= end_minutes))
    |> Enum.map(&px(&1 - start_minutes, scale))
  end

  # Vertical pixels per minute default to 1; a card's time scale stretches that.
  defp px(minutes, scale), do: round(minutes * scale)

  defp positioned_meetings(meetings: meetings) do
    meetings
    |> grouped_same_course_meetings()
    |> Enum.with_index()
    |> Enum.sort_by(fn {meeting, index} ->
      {meeting.start_minutes, meeting.end_minutes, index}
    end)
    |> Enum.chunk_while(
      [],
      fn entry, cluster -> collect_overlap_cluster(entry: entry, cluster: cluster) end,
      &emit_overlap_cluster/1
    )
    |> Enum.flat_map(&assign_overlap_columns/1)
    |> Enum.sort_by(& &1.display_index)
  end

  defp grouped_same_course_meetings(meetings) do
    meetings
    |> Enum.with_index()
    |> Enum.group_by(fn {meeting, _index} ->
      {
        meeting.course_name,
        meeting.course_number,
        meeting.start_minutes,
        meeting.end_minutes,
        Map.get(meeting, :overlay_owner_key)
      }
    end)
    |> Enum.map(fn {_key, indexed_meetings} ->
      indexed_meetings
      |> Enum.sort_by(fn {_meeting, index} -> index end)
      |> build_grouped_meeting()
    end)
    |> Enum.sort_by(& &1.display_index)
  end

  defp build_grouped_meeting([{meeting, index}]) do
    meeting
    |> Map.put(:display_index, index)
    |> Map.put(:grouped_crns, [meeting.crn])
  end

  defp build_grouped_meeting([{meeting, index} | _rest] = indexed_meetings) do
    grouped_crns =
      indexed_meetings
      |> Enum.map(fn {grouped_meeting, _index} -> grouped_meeting.crn end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    meeting
    |> Map.put(:display_index, index)
    |> Map.put(:grouped_crns, grouped_crns)
  end

  defp collect_overlap_cluster(entry: {meeting, index}, cluster: []) do
    {:cont,
     [
       %{
         meeting: meeting,
         display_index: Map.get(meeting, :display_index, index),
         max_end_minutes: meeting.end_minutes
       }
     ]}
  end

  defp collect_overlap_cluster(entry: {meeting, index}, cluster: cluster) do
    cluster_end_minutes = cluster |> Enum.map(& &1.max_end_minutes) |> Enum.max()

    if meeting.start_minutes < cluster_end_minutes do
      max_end_minutes = max(meeting.end_minutes, cluster_end_minutes)

      {:cont,
       [
         %{
           meeting: meeting,
           display_index: Map.get(meeting, :display_index, index),
           max_end_minutes: max_end_minutes
         }
         | Enum.map(cluster, &%{&1 | max_end_minutes: max_end_minutes})
       ]}
    else
      {:cont, Enum.reverse(cluster),
       [
         %{
           meeting: meeting,
           display_index: Map.get(meeting, :display_index, index),
           max_end_minutes: meeting.end_minutes
         }
       ]}
    end
  end

  defp emit_overlap_cluster([]), do: {:cont, []}
  defp emit_overlap_cluster(cluster), do: {:cont, Enum.reverse(cluster), []}

  defp assign_overlap_columns(cluster) do
    {positioned_cluster, column_end_minutes} =
      Enum.map_reduce(cluster, [], fn entry, column_end_minutes ->
        column =
          first_available_column(
            column_end_minutes: column_end_minutes,
            start_minutes: entry.meeting.start_minutes
          )

        column_end_minutes =
          put_column_end(
            column_end_minutes: column_end_minutes,
            column: column,
            end_minutes: entry.meeting.end_minutes
          )

        {Map.put(entry, :column, column), column_end_minutes}
      end)

    total_columns = max(length(column_end_minutes), 1)

    Enum.map(positioned_cluster, fn entry ->
      entry.meeting
      |> Map.put(:display_index, entry.display_index)
      |> Map.put(:display_column, entry.column)
      |> Map.put(:display_total_columns, total_columns)
    end)
  end

  defp first_available_column(
         column_end_minutes: column_end_minutes,
         start_minutes: start_minutes
       ) do
    column_end_minutes
    |> Enum.find_index(&(&1 <= start_minutes))
    |> case do
      nil -> length(column_end_minutes)
      column -> column
    end
  end

  defp put_column_end(
         column_end_minutes: column_end_minutes,
         column: column,
         end_minutes: end_minutes
       ) do
    if column == length(column_end_minutes) do
      column_end_minutes ++ [end_minutes]
    else
      List.replace_at(column_end_minutes, column, end_minutes)
    end
  end

  defp meeting_style(
         meeting: meeting,
         schedule_start_minutes: schedule_start_minutes,
         scale: scale
       ) do
    top = px(meeting.start_minutes - schedule_start_minutes, scale)
    height = max(px(meeting.end_minutes - meeting.start_minutes, scale), 24)
    total_columns = Map.get(meeting, :display_total_columns, 1)
    column = Map.get(meeting, :display_column, 0)
    width = 100 / total_columns
    left = width * column
    column_gap = if total_columns == 1, do: 0, else: 2

    "top: #{top}px; height: #{height}px; left: #{percent(left)}%; width: calc(#{percent(width)}% - #{column_gap}px)"
  end

  defp percent(value),
    do:
      :erlang.float_to_binary(value, decimals: 4)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")

  defp grouped_crns(meeting: meeting), do: Map.get(meeting, :grouped_crns, [meeting.crn])

  defp meeting_conflicted?(
         meeting: meeting,
         conflicted_course_crns: conflicted_course_crns,
         active_conflicted_course_crns: active_conflicted_course_crns
       ) do
    meeting_crns = MapSet.new(grouped_crns(meeting: meeting))

    !MapSet.disjoint?(meeting_crns, conflicted_course_crns) or
      !MapSet.disjoint?(meeting_crns, active_conflicted_course_crns)
  end

  defp course_payload_json(meeting: meeting, selected_term_code: selected_term_code) do
    %{
      crn: meeting.crn,
      crns: grouped_crns(meeting: meeting),
      term: meeting_term(meeting.term, selected_term_code),
      course_name: meeting.course_name,
      subject_code: meeting.subject_code,
      course_number: meeting.course_number,
      credit_hours: meeting.credit_hours,
      start_time: meeting.start_time,
      end_time: meeting.end_time,
      instructors: meeting.instructors,
      meeting: meeting.meeting,
      meet_info: meeting.meet_info
    }
    |> Jason.encode!()
  end

  defp schedule_grid_id(owner_key), do: "week-schedule-grid-#{:erlang.phash2(owner_key)}"

  defp meeting_term(term, _selected_term_code) when is_binary(term) and term != "", do: term
  defp meeting_term(_term, selected_term_code), do: selected_term_code

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
