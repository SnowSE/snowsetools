defmodule SnowSeToolsWeb.Scheduling.AcademicProgramsComponent do
  use SnowSeToolsWeb, :live_component

  import SnowSeToolsWeb.Scheduling.AcademicProgramListItemComponent, only: [program_item: 1]

  alias SnowSeToolsWeb.Scheduling.AcademicProgramEditorComponent

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:courses, assigns[:courses] || [])
      |> assign(:programs, assigns[:programs] || [])
      |> assign(:selected_program_id, assigns[:selected_program_id] || nil)

    {:ok, socket}
  end

  def handle_event("select_program", %{"id" => id}, socket) do
    program = Enum.find(socket.assigns.programs, &(&1["id"] == id))

    send_update(AcademicProgramEditorComponent,
      id: "academic-program-editor",
      selected_program: program
    )

    {:noreply, assign(socket, :selected_program_id, id)}
  end

  def handle_info({:academic_program_selected, id}, socket) do
    {:noreply, assign(socket, :selected_program_id, id)}
  end

  def handle_info({:academic_programs, {:action_result, result}}, socket) do
    send_update(AcademicProgramEditorComponent,
      id: "academic-program-editor",
      action_result: result
    )

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div
      id="academic-programs-panel"
      class="mx-auto grid h-full min-h-0 w-full max-w-[1600px] grid-cols-[22rem_1fr] gap-4 p-4"
    >
      <aside class="flex min-h-0 flex-col gap-3">
        <div class="flex items-center justify-between gap-2">
          <div>
            <h2 class="text-sm font-semibold text-slate-100">Academic Programs</h2>
            <p class="text-xs text-slate-500">Program semesters appear in schedule search.</p>
          </div>
        </div>

        <div id="academic-program-list" class="min-h-0 flex-1 space-y-2 overflow-y-auto pe-2">
          <div
            :if={@programs == []}
            class="rounded-lg border border-dashed border-slate-800 p-6 text-center text-sm text-slate-500"
          >
            No programs yet.
          </div>

          <%= for program <- @programs do %>
            <.program_item
              program={program}
              selected={@selected_program_id == program["id"]}
              target={@myself}
            />
          <% end %>
        </div>
      </aside>

      <.live_component
        module={AcademicProgramEditorComponent}
        id="academic-program-editor"
        courses={@courses}
      />
    </div>
    """
  end
end
