defmodule SnowSeToolsWeb.Scheduling.ScheduleConflictDetail do
  use SnowSeToolsWeb, :html

  @default_event "schedule-change-groups:view_schedule"

  attr :conflict, :map, required: true
  attr :schedule_event, :string, default: @default_event

  def render(assigns) do
    ~H"""
    <div class="rounded-md border border-red-500/30 bg-red-950/45 px-2 py-1 text-[11px] text-red-100">
      <div class="flex flex-wrap items-start gap-x-1 gap-y-0.5">
        <span class="font-semibold">{@conflict.title}</span>
        <span class="text-red-200/85">: {build_description(assigns.conflict)}</span>
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

  def schedule_targets(conflict) when is_map(conflict) do
    conflict_targets(conflict)
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

  defp conflict_targets(conflict) do
    conflict
    |> Map.get(:schedule_targets, Map.get(conflict, "schedule_targets", []))
    |> Enum.uniq_by(& &1.key)
  end

  defp build_description(%{type: :room, entries: entries, resource_label: room}) do
    [room, "is shared by", course_labels_from_entries(entries), first_time_range(entries)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp build_description(%{type: :professor, entries: entries, resource_label: professor}) do
    [professor, "teaches", course_labels_from_entries(entries), first_time_range(entries)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp build_description(_conflict), do: ""

  defp course_labels_from_entries(entries) do
    labels = Enum.map(entries, & &1.course_label)

    case length(labels) do
      1 ->
        hd(labels)

      2 ->
        "#{Enum.at(labels, 0)} and #{Enum.at(labels, 1)}"

      n when n > 2 ->
        last = List.last(labels)
        all_but_last = Enum.drop(labels, -1) |> Enum.join(", ")
        "#{all_but_last}, and #{last}"
    end
  end

  defp first_time_range(entries) do
    case List.first(entries) do
      %{time_range: range} when is_binary(range) and range != "" -> "at #{range}"
      _ -> nil
    end
  end

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
