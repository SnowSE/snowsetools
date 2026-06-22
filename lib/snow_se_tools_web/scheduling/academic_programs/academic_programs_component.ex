defmodule SnowSeToolsWeb.Scheduling.AcademicProgramsComponent do
  use SnowSeToolsWeb, :live_component

  alias SnowSeToolsWeb.Scheduling.AcademicProgramDisplayComponent
  alias SnowSeToolsWeb.Scheduling.AcademicProgramEditorComponent
  alias SnowSeToolsWeb.Scheduling.AcademicProgramListItemComponent

  def update(%{cancel_edit: true}, socket) do
    {:ok, socket |> assign(:editing?, false)}
  end

  def update(%{edit_program: program_id}, socket) do
    {:ok,
     socket
     |> assign(:selected_program_id, program_id)
     |> assign(:editing?, true)}
  end

  def update(%{select_program: program}, socket) do
    {:ok, socket |> assign(:selected_program_id, program["id"]) |> assign(:editing?, false)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:courses, assigns[:courses] || [])
      |> assign(:programs, assigns[:programs] || [])
      |> assign(:selected_program_id, Map.get(assigns, :selected_program_id))
      |> assign_new(:editing?, fn -> false end)

    {:ok, socket}
  end

  def handle_event("new_program_from_list", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_program_id, nil)
     |> assign(:editing?, true)}
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
            <.live_component
              module={AcademicProgramListItemComponent}
              id={"academic-program-item-#{program["id"]}"}
              program={program}
              is_selected={@selected_program_id == program["id"]}
              on_program_selected={fn program -> send_update(@myself, select_program: program) end}
            />
          <% end %>
        </div>
      </aside>

      <div :if={@editing?}>
        <.live_component
          module={AcademicProgramEditorComponent}
          id="academic-program-editor"
          courses={@courses}
          selected_program={Enum.find(@programs, &(&1["id"] == @selected_program_id))}
          on_cancel_edit={fn -> send_update(@myself, cancel_edit: true) end}
        />
      </div>

      <div :if={!@editing?}>
        <.live_component
          module={AcademicProgramDisplayComponent}
          id="academic-program-display"
          program={Enum.find(@programs, &(&1["id"] == @selected_program_id))}
          courses={@courses}
          on_edit_program={fn -> send_update(@myself, edit_program: @selected_program_id) end}
        />
      </div>
    </div>
    """
  end
end
