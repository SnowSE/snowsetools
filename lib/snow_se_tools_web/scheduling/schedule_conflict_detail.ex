defmodule SnowSeToolsWeb.Scheduling.ScheduleConflictDetail do
  use SnowSeToolsWeb, :html

  @default_event "schedule-change-groups:view_schedule"

  attr :conflict, :map, required: true
  attr :schedule_event, :string, default: @default_event

  def render(assigns) do
    assigns = assign(assigns, :targets, conflict_targets(assigns.conflict))

    ~H"""
    <div class="rounded-md border border-red-500/30 bg-red-950/45 px-2 py-1 text-[11px] text-red-100">
      <div class="flex flex-wrap items-start gap-x-1 gap-y-0.5">
        <span class="font-semibold">{@conflict.title}</span>
        <span class="text-red-200/85">: {@conflict.description}</span>
      </div>

      <div :if={@targets != []} class="mt-2 flex flex-wrap gap-1">
        <.schedule_target_button
          :for={target <- @targets}
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
