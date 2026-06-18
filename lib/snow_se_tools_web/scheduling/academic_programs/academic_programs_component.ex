defmodule SnowSeToolsWeb.Scheduling.AcademicProgramsComponent do
  use SnowSeToolsWeb, :live_component
  require Logger

  import SnowSeToolsWeb.Scheduling.AcademicProgramListItemComponent, only: [program_item: 1]

  alias SnowSeToolsWeb.Scheduling.AcademicProgramDisplayComponent
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
    {:noreply, assign(socket, :selected_program_id, id)}
  end

  def handle_event("new_program_from_list", _params, socket) do
    send_update(AcademicProgramDisplayComponent,
      id: "academic-program-display",
      editing?: true,
      program: nil,
      courses: socket.assigns.courses
    )

    {:noreply, assign(socket, :selected_program_id, nil)}
  end

  def handle_info({:academic_program_selected, id}, socket) do
    {:noreply, assign(socket, :selected_program_id, id)}
  end

  def handle_info({:academic_programs, {:action_result, result}}, socket) do
    send_update(AcademicProgramEditorComponent,
      id: "academic-program-editor",
      action_result: result
    )

    case result do
      {:ok, _message, program} ->
        if program do
          send_update(AcademicProgramDisplayComponent,
            id: "academic-program-display",
            program: program
          )

          {:noreply, assign(socket, :program_view_mode, :display)}
        else
          {:noreply, socket}
        end

      {:error, reason} ->
        Logger.error("AcademicPrograms: action result error #{inspect(reason)}")
        {:noreply, socket}
    end
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

        <button
          id="new-program-from-list"
          type="button"
          phx-click="new_program_from_list"
          phx-target={@myself}
          class="inline-flex items-center gap-1 rounded-md bg-indigo-500/15 px-2.5 py-1.5 text-xs font-medium text-indigo-200 transition hover:bg-indigo-500/25"
        >
          <.icon name="hero-plus" class="size-3.5" /> New Program
        </button>

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
        module={AcademicProgramDisplayComponent}
        id="academic-program-display"
        program={Enum.find(@programs, &(&1["id"] == @selected_program_id))}
        courses={@courses}
      />
    </div>
    """
  end
end
