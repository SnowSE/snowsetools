defmodule SnowSeToolsWeb.Scheduling.ScheduleChangeGroupDetails do
  use SnowSeToolsWeb, :html

  alias SnowSeTools.Scheduling.ScheduleUtils
  alias SnowSeToolsWeb.Scheduling.ScheduleChangeGroups
  alias SnowSeToolsWeb.Scheduling.WeekSchedule

  attr :state, :map, required: true
  attr :week_schedules, :map, default: %{}
  attr :academic_programs, :list, default: []

  def render(assigns) do
    ~H"""
    <div
      id="schedule-change-group-details"
      class="min-h-0 border-t border-slate-800/80 pt-3"
    >
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
          <% original_course = original_course_for_change(change, @week_schedules) %>
          <% conflicts = conflicts_for_change(change, @week_schedules) %>
          <% changed_meeting = List.first(Map.get(change, "meet_info", [])) %>
          <% original_meeting = first_matching_meeting(original_course, changed_meeting) %>
          <% affected_semesters =
            affected_semesters_for_change(change, original_course, @academic_programs) %>
          <% related_schedule_targets =
            related_schedule_targets(change, original_course, affected_semesters) %>
          <% professor_change = List.first(changed_professor(change, original_course)) %>
          <% days_change = changed_days(changed_meeting, original_meeting) %>
          <% time_change = changed_time(changed_meeting, original_meeting) %>
          <% room_change = changed_room(changed_meeting, original_meeting) %>
          <div
            id={"schedule-change-#{change["id"]}"}
            class={change_card_class(change, conflicts)}
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

              <div class="flex shrink-0 items-center">
                <button
                  type="button"
                  phx-click="schedule-change-groups:delete_change"
                  phx-value-change-id={change["id"]}
                  aria-label="Delete change"
                  class="rounded p-1 text-slate-500 transition hover:bg-red-950/60 hover:text-red-200"
                >
                  <.icon name="hero-trash" class="h-3.5 w-3.5" />
                </button>
              </div>
            </div>

            <div class="mt-2 space-y-1">
              <div
                :if={change["course_name"] == "__DELETED__"}
                class="rounded-md border border-slate-800/80 bg-slate-900/55 px-2 py-1 text-[11px]"
              >
                <span class="font-semibold text-slate-300">Status</span>
                <span class="text-slate-500"> changed to </span>
                <span class="text-slate-200">removed from schedules</span>
              </div>

              <div
                :if={professor_change}
                class="rounded-md border border-slate-800/80 bg-slate-900/55 px-2 py-1 text-[11px]"
              >
                <span class="font-semibold text-slate-300">Professor</span>
                <span class="text-slate-500"> changed to </span>
                <span class="text-slate-200">{professor_change.value}</span>
              </div>

              <div
                :if={days_change}
                class="rounded-md border border-slate-800/80 bg-slate-900/55 px-2 py-1 text-[11px]"
              >
                <span class="font-semibold text-slate-300">Days</span>
                <span class="text-slate-500"> changed to </span>
                <span class="text-slate-200">{days_change.value}</span>
              </div>

              <div
                :if={time_change}
                class="rounded-md border border-slate-800/80 bg-slate-900/55 px-2 py-1 text-[11px]"
              >
                <span class="font-semibold text-slate-300">Time</span>
                <span class="text-slate-500"> changed to </span>
                <span class="text-slate-200">{time_change.value}</span>
              </div>

              <div
                :if={room_change}
                class="rounded-md border border-slate-800/80 bg-slate-900/55 px-2 py-1 text-[11px]"
              >
                <span class="font-semibold text-slate-300">Room</span>
                <span class="text-slate-500"> changed to </span>
                <span class="text-slate-200">{room_change.value}</span>
              </div>
            </div>

            <div :if={conflicts != []} class="mt-2 space-y-1">
              <div
                :for={conflict <- conflicts}
                class="rounded-md border border-red-500/30 bg-red-950/45 px-2 py-1 text-[11px] text-red-100"
              >
                <span class="font-semibold">{conflict.title}</span>
                <span class="text-red-200/85">: {conflict.description}</span>
              </div>
            </div>

            <div :if={related_schedule_targets != []} class="mt-2 border-t border-slate-800/70 pt-2">
              <div class="mb-1 text-[10px] font-semibold uppercase tracking-wider text-slate-500">
                Related schedules
              </div>
              <div class="flex flex-wrap gap-1">
                <.related_schedule_button
                  :for={target <- related_schedule_targets}
                  key={target.key}
                  label={target.label}
                  kind={target.kind}
                />
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :key, :string, required: true
  attr :label, :string, required: true
  attr :kind, :atom, required: true

  defp related_schedule_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="schedule-change-groups:view_schedule"
      phx-value-key={@key}
      class={[
        "inline-flex max-w-full items-center gap-1 rounded-md border px-1.5 py-0.5 text-[10px] font-medium transition",
        related_schedule_button_class(@kind)
      ]}
    >
      <.icon :if={@kind == :room} name="hero-building-office-2" class="size-3 shrink-0" />
      <.icon
        :if={@kind == :academic_program_semester}
        name="hero-academic-cap"
        class="size-3 shrink-0"
      />
      <span class="truncate">{@label}</span>
    </button>
    """
  end

  defp active_changes(%ScheduleChangeGroups{active_change_group: nil}), do: []

  defp active_changes(%ScheduleChangeGroups{active_change_group: active_change_group}) do
    Map.get(active_change_group, "changes", [])
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

  defp change_card_class(%{"course_name" => "__DELETED__"}, _conflicts) do
    "rounded-lg border border-red-500/30 bg-red-950/20 p-2.5"
  end

  defp change_card_class(_change, conflicts) when conflicts != [] do
    "rounded-lg border border-red-500/45 bg-red-950/25 p-2.5 shadow-sm shadow-red-950/30"
  end

  defp change_card_class(_change, _conflicts) do
    "rounded-lg border border-emerald-500/25 bg-emerald-950/10 p-2.5"
  end

  defp changed_professor(%{"target_professor" => professor}, original_course)
       when is_binary(professor) and professor != "" do
    original_professor = first_professor(original_course)

    if original_professor != professor do
      [%{label: "Professor", value: professor}]
    else
      []
    end
  end

  defp changed_professor(_change, _original_course), do: []

  defp changed_days(%{} = changed_meeting, nil) do
    days = format_days(changed_meeting["days"] || [])
    if days == "", do: nil, else: %{label: "Days", value: days}
  end

  defp changed_days(%{} = changed_meeting, %{} = original_meeting) do
    changed_days = changed_meeting["days"] || []
    original_days = original_meeting["days"] || []

    if MapSet.new(changed_days) != MapSet.new(original_days) do
      %{label: "Days", value: format_days(changed_days)}
    end
  end

  defp changed_days(_changed_meeting, _original_meeting), do: nil

  defp changed_time(%{} = changed_meeting, nil) do
    %{label: "Time", value: format_time_range(changed_meeting)}
  end

  defp changed_time(%{} = changed_meeting, %{} = original_meeting) do
    if normalize_time(changed_meeting["start_time"]) !=
         normalize_time(original_meeting["start_time"]) or
         normalize_time(changed_meeting["end_time"]) !=
           normalize_time(original_meeting["end_time"]) do
      %{label: "Time", value: format_time_range(changed_meeting)}
    end
  end

  defp changed_time(_changed_meeting, _original_meeting), do: nil

  defp changed_room(%{} = changed_meeting, nil) do
    case ScheduleUtils.room_name(meeting: changed_meeting) do
      nil -> nil
      room -> %{label: "Room", value: room}
    end
  end

  defp changed_room(%{} = changed_meeting, %{} = original_meeting) do
    changed_room = ScheduleUtils.room_name(meeting: changed_meeting)
    original_room = ScheduleUtils.room_name(meeting: original_meeting)

    if !blank?(changed_room) and changed_room != original_room do
      %{label: "Room", value: changed_room}
    end
  end

  defp changed_room(_changed_meeting, _original_meeting), do: nil

  defp original_course_for_change(change, week_schedules) do
    all_courses(week_schedules)
    |> Enum.find(&(&1["crn"] == change["crn"]))
  end

  defp conflicts_for_change(%{"course_name" => "__DELETED__"}, _week_schedules), do: []

  defp conflicts_for_change(change, week_schedules) do
    changed_meeting = List.first(Map.get(change, "meet_info", []))

    if is_nil(changed_meeting) do
      []
    else
      courses = all_courses(week_schedules)

      professor_conflicts(change, changed_meeting, courses) ++
        room_conflicts(change, changed_meeting, courses)
    end
  end

  defp affected_semesters_for_change(change, original_course, academic_programs) do
    {subject_code, course_number} = change_course_identity(change, original_course)

    if blank?(subject_code) or blank?(course_number) do
      []
    else
      academic_programs
      |> Enum.flat_map(&affected_program_semesters(&1, subject_code, course_number))
    end
  end

  defp affected_program_semesters(program, subject_code, course_number) do
    program
    |> Map.get("semesters", [])
    |> Enum.with_index()
    |> Enum.filter(fn {semester, _index} ->
      Enum.any?(Map.get(semester, "courses", []), fn course ->
        normalize_course_part(course["subject_code"]) == normalize_course_part(subject_code) and
          normalize_course_part(course["course_number"]) == normalize_course_part(course_number)
      end)
    end)
    |> Enum.map(fn {_semester, index} ->
      %{
        program_name: program["name"] || "Academic program",
        semester_name: semester_label(index),
        key: program_semester_key(program, Enum.at(program["semesters"] || [], index))
      }
    end)
  end

  defp related_schedule_targets(change, original_course, affected_semesters) do
    [
      professor_schedule_target(change, original_course),
      room_schedule_target(change)
      | Enum.map(affected_semesters, &academic_program_schedule_target/1)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.key)
  end

  defp room_schedule_target(change) do
    case room_label(change) do
      room when is_binary(room) and room != "" ->
        %{kind: :room, key: "room:#{room}", label: "Room: #{room}"}

      _other ->
        nil
    end
  end

  defp professor_schedule_target(change, original_course) do
    case professor_name(change, original_course) do
      professor when is_binary(professor) and professor != "" ->
        %{kind: :professor, key: "professor:#{professor}", label: "Professor: #{professor}"}

      _other ->
        nil
    end
  end

  defp academic_program_schedule_target(%{key: key} = semester)
       when is_binary(key) and key != "" do
    %{
      kind: :academic_program_semester,
      key: key,
      label: "#{semester.program_name} · #{semester.semester_name}"
    }
  end

  defp academic_program_schedule_target(_semester), do: nil

  defp program_semester_key(%{"id" => program_id}, %{"id" => semester_id})
       when is_binary(program_id) and is_binary(semester_id) do
    "academic_program_semester:#{program_id}:#{semester_id}"
  end

  defp program_semester_key(_program, _semester), do: nil

  defp change_course_identity(change, original_course) do
    {
      change["subject_code"] || course_value(original_course, "subject_code"),
      change["course_number"] || course_value(original_course, "course_number")
    }
  end

  defp course_value(nil, _key), do: nil
  defp course_value(course, key), do: Map.get(course, key)

  defp professor_conflicts(%{"target_professor" => professor} = change, changed_meeting, courses)
       when is_binary(professor) and professor != "" do
    courses
    |> Enum.reject(&(&1["crn"] == change["crn"]))
    |> Enum.filter(&course_has_professor?(&1, professor))
    |> Enum.flat_map(fn course ->
      course
      |> Map.get("meet_info", [])
      |> Enum.filter(&meetings_overlap?(changed_meeting, &1))
      |> Enum.map(fn meeting ->
        %{
          title: "Professor conflict",
          description:
            "#{professor} already teaches #{course_label(course)} #{format_time_range(meeting)}"
        }
      end)
    end)
  end

  defp professor_conflicts(_change, _changed_meeting, _courses), do: []

  defp room_conflicts(change, changed_meeting, courses) do
    changed_room = ScheduleUtils.room_name(meeting: changed_meeting)

    if blank?(changed_room) do
      []
    else
      courses
      |> Enum.reject(&(&1["crn"] == change["crn"]))
      |> Enum.flat_map(fn course ->
        course
        |> Map.get("meet_info", [])
        |> Enum.filter(fn meeting ->
          ScheduleUtils.room_name(meeting: meeting) == changed_room and
            meetings_overlap?(changed_meeting, meeting)
        end)
        |> Enum.map(fn meeting ->
          %{
            title: "Room conflict",
            description:
              "#{changed_room} is already used by #{course_label(course)} #{format_time_range(meeting)}"
          }
        end)
      end)
    end
  end

  defp all_courses(week_schedules) do
    week_schedules
    |> Map.values()
    |> Enum.flat_map(fn
      %WeekSchedule{week_schedule: %{courses: courses}} when is_list(courses) -> courses
      _other -> []
    end)
    |> Enum.uniq_by(& &1["crn"])
  end

  defp meetings_overlap?(%{} = left, %{} = right) do
    shares_day?(left["days"] || [], right["days"] || []) and
      time_minutes(left["start_time"]) < time_minutes(right["end_time"]) and
      time_minutes(right["start_time"]) < time_minutes(left["end_time"])
  end

  defp meetings_overlap?(_left, _right), do: false

  defp shares_day?(left_days, right_days) do
    !MapSet.disjoint?(MapSet.new(left_days), MapSet.new(right_days))
  end

  defp first_matching_meeting(nil, _changed_meeting), do: nil

  defp first_matching_meeting(original_course, %{} = changed_meeting) do
    original_course
    |> Map.get("meet_info", [])
    |> Enum.find(fn meeting ->
      !MapSet.disjoint?(
        MapSet.new(meeting["days"] || []),
        MapSet.new(changed_meeting["days"] || [])
      )
    end)
    |> case do
      nil -> List.first(Map.get(original_course, "meet_info", []))
      meeting -> meeting
    end
  end

  defp first_matching_meeting(original_course, _changed_meeting) when is_map(original_course) do
    List.first(Map.get(original_course, "meet_info", []))
  end

  defp first_professor(nil), do: nil

  defp first_professor(course) do
    course
    |> Map.get("instructors", [])
    |> List.first()
    |> case do
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _other -> nil
    end
  end

  defp course_has_professor?(course, professor) do
    Enum.any?(Map.get(course, "instructors", []), fn
      %{"name" => ^professor} -> true
      ^professor -> true
      _other -> false
    end)
  end

  defp course_label(course) do
    [course["subject_code"], course["course_number"], course["name"]]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  defp format_days(days) do
    days
    |> Enum.map(&String.slice(&1, 0, 3))
    |> Enum.join("/")
  end

  defp format_time_range(meeting) do
    [normalize_time(meeting["start_time"]), normalize_time(meeting["end_time"])]
    |> Enum.reject(&blank?/1)
    |> Enum.join("-")
  end

  defp normalize_time(time) when is_binary(time) do
    time
    |> String.split(":")
    |> case do
      [hour, minute | _] -> "#{hour}:#{minute}"
      _other -> time
    end
  end

  defp normalize_time(_time), do: nil

  defp normalize_course_part(value) when is_binary(value), do: String.downcase(String.trim(value))
  defp normalize_course_part(_value), do: ""

  defp related_schedule_button_class(:room) do
    "border-cyan-400/25 bg-cyan-500/10 text-cyan-100 hover:border-cyan-300/45 hover:bg-cyan-500/20"
  end

  defp related_schedule_button_class(:professor) do
    "border-emerald-400/25 bg-emerald-500/10 text-emerald-100 hover:border-emerald-300/45 hover:bg-emerald-500/20"
  end

  defp related_schedule_button_class(:academic_program_semester) do
    "border-amber-400/25 bg-amber-500/10 text-amber-100 hover:border-amber-300/45 hover:bg-amber-500/20"
  end

  defp time_minutes(time) when is_binary(time) do
    case String.split(time, ":") do
      [hour, minute | _] ->
        with {h, ""} <- Integer.parse(hour),
             {m, ""} <- Integer.parse(minute) do
          h * 60 + m
        else
          _other -> 0
        end

      _other ->
        0
    end
  end

  defp time_minutes(_time), do: 0

  defp room_label(change) do
    case List.first(Map.get(change, "meet_info", [])) do
      %{} = meeting -> ScheduleUtils.room_name(meeting: meeting)
      _other -> nil
    end
  end

  defp professor_name(%{"target_professor" => professor}, _original_course)
       when is_binary(professor) and professor != "",
       do: professor

  defp professor_name(_change, original_course), do: first_professor(original_course)

  defp blank?(value), do: is_nil(value) or value == ""

  defp semester_label(0), do: "Freshman first semester"
  defp semester_label(1), do: "Freshman second semester"
  defp semester_label(2), do: "Sophomore first semester"
  defp semester_label(3), do: "Sophomore second semester"
  defp semester_label(4), do: "Junior first semester"
  defp semester_label(5), do: "Junior second semester"
  defp semester_label(6), do: "Senior first semester"
  defp semester_label(7), do: "Senior second semester"
  defp semester_label(index), do: "Year #{div(index, 2) + 1} semester #{rem(index, 2) + 1}"
end
