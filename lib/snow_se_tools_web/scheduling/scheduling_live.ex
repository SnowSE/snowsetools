defmodule SnowSeToolsWeb.Scheduling.SchedulingLive do
  use SnowSeToolsWeb, :live_view

  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramEditor
  alias SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker
  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramsPanel
  alias SnowSeToolsWeb.Scheduling.ScheduleViewer

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Scheduling")
     |> ScheduleViewer.assign_component(:schedule_viewer)
     |> AcademicProgramEditor.assign_component(:academic_program_editor)
     |> AcademicProgramCoursePicker.assign_component(:academic_program_course_picker,
       editor_key: :academic_program_editor,
       courses: []
     )
     |> AcademicProgramsPanel.assign_component(:academic_programs_panel,
       editor_key: :academic_program_editor,
       picker_key: :academic_program_course_picker
     )
     |> assign(:mode, :viewer)
     |> assign(:modes, viewer: "Schedule Viewer", programs: "Academic Programs")}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :mode, mode_from_params(params))}
  end

  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    {:noreply, push_patch(socket, to: scheduling_path(mode: mode_atom))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="flex h-full min-h-0 flex-col">
        <div class="shrink-0 border-b border-slate-700/60">
          <div class="mx-auto flex w-full max-w-[2000px] items-center gap-1 px-4">
            <%= for {mode_key, label} <- @modes do %>
              <button
                id={"scheduling-tab-#{mode_key}"}
                type="button"
                phx-click="switch_mode"
                phx-value-mode={mode_key}
                class={[
                  "cursor-pointer border-b-2 px-4 py-2.5 text-sm font-medium transition-colors",
                  @mode == mode_key && "border-indigo-400 text-indigo-300",
                  @mode != mode_key &&
                    "border-transparent text-slate-400 hover:border-slate-500 hover:text-slate-200"
                ]}
              >
                {label}
              </button>
            <% end %>
          </div>
        </div>

        <div class="min-h-0 flex-1">
          <%= case @mode do %>
            <% :viewer -> %>
              <ScheduleViewer.render state={@schedule_viewer} />
            <% :programs -> %>
              <AcademicProgramsPanel.render
                programs={@academic_programs}
                state={@academic_programs_panel}
                editor_state={@academic_program_editor}
                picker_state={@academic_program_course_picker}
              />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp mode_from_params(%{"mode" => "programs"}), do: :programs
  defp mode_from_params(_params), do: :viewer

  defp scheduling_path(mode: mode_atom), do: "/scheduling?mode=#{mode_atom}"
end
