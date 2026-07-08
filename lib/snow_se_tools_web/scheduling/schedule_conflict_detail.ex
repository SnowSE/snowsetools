defmodule SnowSeToolsWeb.Scheduling.ScheduleConflictDetail do
  use SnowSeToolsWeb, :html

  @default_event "schedule-change-groups:view_schedule"

  attr :conflict, :map, required: true
  attr :schedule_event, :string, default: @default_event

  def render(assigns) do
    ~H"""
    <div class="rounded-md px-2 py-2  text-red-100">
      <div class="flex flex-wrap items-center gap-x-1.5 gap-y-1">
        <span class="flex flex-wrap items-center gap-1 text-red-50">
          <span :for={label <- course_labels(@conflict)} class="rounded px-1.5 py-0.5">
            {label}
          </span>
        </span>
        <span class="text-red-200/75">overlap</span>
        <span class="rounded  px-1.5 py-0.5  text-red-50">
          {overlap_when(@conflict)}
        </span>
        <span class="text-red-200/60">in</span>
        <span class="rounded  px-1.5 py-0.5  text-red-50">
          {building_summary(@conflict)}
        </span>
      </div>

      <div :if={conflict_targets(assigns.conflict) != []} class="mt-2 flex flex-wrap gap-1">
        <.schedule_target_button
          :for={target <- conflict_targets(assigns.conflict)}
          key={target.key}
          label={target.label}
          kind={target.kind}
          schedule_event={@schedule_event}
        />
      </div>
    </div>
    """
  end

  attr :key, :string, required: true
  attr :label, :string, required: true
  attr :kind, :atom, required: true
  attr :schedule_event, :string, required: true

  defp schedule_target_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@schedule_event}
      phx-value-key={@key}
      class={[
        "inline-flex max-w-full items-center gap-1 rounded-md border px-1.5 py-0.5 text-[10px] font-medium transition",
        schedule_target_button_class(@kind)
      ]}
    >
      <.icon :if={@kind == :room} name="hero-building-office-2" class="size-3 shrink-0" />
      <.icon :if={@kind == :professor} name="hero-user" class="size-3 shrink-0" />
      <.icon
        :if={@kind == :academic_program_semester}
        name="hero-academic-cap"
        class="size-3 shrink-0"
      />
      <span class="truncate">{@label}</span>
    </button>
    """
  end

  def schedule_targets(conflict) when is_map(conflict) do
    conflict_targets(conflict)
  end

  defp conflict_targets(conflict) do
    conflict
    |> Map.get(:schedule_targets, Map.get(conflict, "schedule_targets", []))
    |> Enum.uniq_by(& &1.key)
  end

  defp course_labels(conflict) do
    entries = conflict_entries(conflict)

    labels =
      entries
      |> Enum.map(&entry_value(entry: &1, key: :course_label))
      |> Enum.reject(&blank?/1)
      |> Enum.uniq()

    if labels == [] do
      ["Classes"]
    else
      labels
    end
  end

  defp conflict_entries(conflict) do
    conflict
    |> then(&conflict_value(conflict: &1, key: :entries))
    |> List.wrap()
  end

  defp conflict_value(conflict: conflict, key: key),
    do: Map.get(conflict, key, Map.get(conflict, Atom.to_string(key)))

  defp entry_value(entry: entry, key: key),
    do: Map.get(entry, key, Map.get(entry, Atom.to_string(key)))

  defp building_summary(conflict) do
    conflict
    |> conflict_entries()
    |> Enum.map(&entry_building/1)
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> readable_list()
    |> case do
      "" -> "Unknown"
      summary -> summary
    end
  end

  defp entry_building(entry) do
    case {
      entry_value(entry: entry, key: :building),
      entry_value(entry: entry, key: :building_code)
    } do
      {building, _code} when is_binary(building) and building != "" -> building
      {_building, code} when is_binary(code) and code != "" -> code
      _other -> ""
    end
  end

  defp overlap_when(conflict) do
    entries = conflict_entries(conflict)

    [days_summary(entries), overlap_time_range(entries)]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> "Unknown"
      value -> value
    end
  end

  defp days_summary(entries) do
    entries
    |> Enum.map(&MapSet.new(List.wrap(entry_value(entry: &1, key: :days))))
    |> Enum.reject(&(MapSet.size(&1) == 0))
    |> shared_days()
    |> Enum.map(&short_day/1)
    |> Enum.join("/")
  end

  defp shared_days([]), do: []

  defp shared_days([first | rest]) do
    rest
    |> Enum.reduce(first, &MapSet.intersection/2)
    |> MapSet.to_list()
    |> Enum.sort_by(&day_sort/1)
  end

  defp overlap_time_range(entries) do
    starts =
      entries |> Enum.map(&entry_value(entry: &1, key: :start_time)) |> Enum.reject(&blank?/1)

    ends = entries |> Enum.map(&entry_value(entry: &1, key: :end_time)) |> Enum.reject(&blank?/1)

    if starts == [] or ends == [] do
      nil
    else
      "#{Enum.max_by(starts, &time_minutes/1)}-#{Enum.min_by(ends, &time_minutes/1)}"
    end
  end

  defp readable_list([]), do: ""
  defp readable_list([value]), do: value
  defp readable_list([first, second]), do: "#{first} and #{second}"

  defp readable_list(values) do
    last = List.last(values)
    all_but_last = values |> Enum.drop(-1) |> Enum.join(", ")
    "#{all_but_last}, and #{last}"
  end

  defp short_day("Monday"), do: "Mon"
  defp short_day("Tuesday"), do: "Tue"
  defp short_day("Wednesday"), do: "Wed"
  defp short_day("Thursday"), do: "Thu"
  defp short_day("Friday"), do: "Fri"
  defp short_day("Saturday"), do: "Sat"
  defp short_day("Sunday"), do: "Sun"
  defp short_day(day), do: day

  defp day_sort("Monday"), do: 1
  defp day_sort("Tuesday"), do: 2
  defp day_sort("Wednesday"), do: 3
  defp day_sort("Thursday"), do: 4
  defp day_sort("Friday"), do: 5
  defp day_sort("Saturday"), do: 6
  defp day_sort("Sunday"), do: 7
  defp day_sort(_day), do: 8

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

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp schedule_target_button_class(:room) do
    "border-cyan-400/25 bg-cyan-500/10 text-cyan-100 hover:border-cyan-300/45 hover:bg-cyan-500/20"
  end

  defp schedule_target_button_class(:professor) do
    "border-emerald-400/25 bg-emerald-500/10 text-emerald-100 hover:border-emerald-300/45 hover:bg-emerald-500/20"
  end

  defp schedule_target_button_class(:academic_program_semester) do
    "border-amber-400/25 bg-amber-500/10 text-amber-100 hover:border-amber-300/45 hover:bg-amber-500/20"
  end
end
