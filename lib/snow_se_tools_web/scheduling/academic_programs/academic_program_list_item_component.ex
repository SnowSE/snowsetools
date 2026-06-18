defmodule SnowSeToolsWeb.Scheduling.AcademicProgramListItemComponent do
  use SnowSeToolsWeb, :html

  attr :program, :map, required: true
  attr :selected, :boolean, default: false
  attr :target, :any, required: true

  def program_item(assigns) do
    ~H"""
    <button
      id={"academic-program-#{@program["id"]}"}
      type="button"
      phx-click="select_program"
      phx-target={@target}
      phx-value-id={@program["id"]}
      class={[
        "w-full rounded-lg border px-3 py-2 text-left transition",
        if(@selected,
          do: "border-indigo-500/50 bg-indigo-950/50 text-indigo-100",
          else:
            "border-slate-800 bg-slate-900/45 text-slate-200 hover:border-slate-700 hover:bg-slate-900"
        )
      ]}
    >
      <span class="block truncate text-sm font-medium">{@program["name"]}</span>
      <span class="mt-0.5 block text-xs text-slate-500">
        {length(@program["semesters"] || [])} semesters
      </span>
    </button>
    """
  end
end
