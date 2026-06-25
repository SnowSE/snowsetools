defmodule SnowSeToolsWeb.Scheduling.SchedulingLive do
  use SnowSeToolsWeb, :live_view

  alias SnowSeTools.Scheduling.{ScheduleChangeDomainManager, ScheduleChangePubSub}
  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramEditor
  alias SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker
  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramsPanel
  alias SnowSeToolsWeb.Scheduling.ScheduleChangeGroups
  alias SnowSeToolsWeb.Scheduling.ScheduleDetailsOrder
  alias SnowSeToolsWeb.Scheduling.ScheduleViewer
  alias SnowSeToolsWeb.Scheduling.WeekSchedule

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        ScheduleChangePubSub.subscribe()
        ScheduleChangeDomainManager.list_groups(pid: self())
        socket
      else
        socket
      end

    {:ok,
     socket
     |> assign(:page_title, "Scheduling")
     |> ScheduleViewer.assign_component()
     |> ScheduleDetailsOrder.assign_component()
     |> AcademicProgramEditor.assign_component(:academic_program_editor)
     |> AcademicProgramCoursePicker.assign_component(:academic_program_course_picker,
       editor_key: :academic_program_editor
     )
     |> AcademicProgramsPanel.assign_component(:academic_programs_panel,
       editor_key: :academic_program_editor,
       picker_key: :academic_program_course_picker
     )
     |> ScheduleChangeGroups.assign_component()
     |> WeekSchedule.assign_component()
     |> assign(:mode, :viewer)
     |> assign(:modes, viewer: "Schedule Viewer", programs: "Academic Programs")}
  end

  def handle_params(params, _uri, socket) do
    mode = mode_from_params(params)
    term_code = Map.get(params, "term")

    socket =
      socket
      |> assign(:mode, mode)
      |> sync_schedule_viewer_term(term_code: term_code)

    {:noreply, socket}
  end

  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)

    {:noreply,
     push_patch(socket,
       to:
         scheduling_path(
           mode: mode_atom,
           term: socket.assigns.schedule_viewer_state.selected_term_code
         )
     )}
  end

  def handle_info({:schedule_change_groups, groups}, socket) do
    {:noreply, ScheduleChangeGroups.sync_groups(socket, groups)}
  end

  def handle_info({:schedule_changes, _event}, socket) do
    ScheduleChangeDomainManager.list_groups(pid: self())
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

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
              <ScheduleViewer.render
                state={@schedule_viewer_state}
                schedule_details_order={@schedule_details_order}
                week_schedules={@week_schedules}
                schedule_change_groups_state={@schedule_change_groups_state}
              />
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

  defp sync_schedule_viewer_term(socket, term_code: term_code) do
    state = socket.assigns.schedule_viewer_state

    selected_term_code =
      ScheduleViewer.resolve_selected_term_code(
        terms: state.terms,
        selected_term_code: term_code
      )

    socket =
      if is_binary(selected_term_code) do
        socket
        |> ScheduleViewer.sync_selected_term(term_code: selected_term_code)
        |> ScheduleDetailsOrder.sync_selected_term(term_code: selected_term_code)
      else
        socket
        |> ScheduleDetailsOrder.sync_selected_term(term_code: nil)
      end

    socket
  end

  defp scheduling_path(mode: mode_atom, term: nil), do: "/scheduling?mode=#{mode_atom}"

  defp scheduling_path(mode: mode_atom, term: term_code) when is_binary(term_code) do
    "/scheduling?mode=#{mode_atom}&term=#{term_code}"
  end
end
