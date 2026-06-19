defmodule SnowSeToolsWeb.Scheduling.AcademicProgramListItemComponent do
  use SnowSeToolsWeb, :live_component

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:program, assigns[:program])
      |> assign(:is_selected, assigns[:is_selected])
      |> assign(:on_program_selected, assigns[:on_program_selected])

    {:ok, socket}
  end

  def handle_event("select_program", _params, socket) do
    program = socket.assigns.program
    socket.assigns.on_program_selected.(program)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <button
      id={"academic-program-#{@program["id"]}"}
      type="button"
      phx-click="select_program"
      phx-target={@myself}
      class={[
        "w-full rounded-lg border px-3 py-2 text-left transition",
        if(@is_selected,
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
