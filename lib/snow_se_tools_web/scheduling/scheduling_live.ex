defmodule SnowSeToolsWeb.Scheduling.SchedulingLive do
  use SnowSeToolsWeb, :live_view
  require Logger

  alias SnowSeTools.AcademicPrograms.{AcademicProgramPubSub, ProgramDomainManager}
  alias SnowSeTools.Snow.SnowCourseCacheDb
  alias SnowSeToolsWeb.Scheduling.AcademicProgramsComponent
  alias SnowSeToolsWeb.Scheduling.AcademicProgramEditorComponent
  alias SnowSeToolsWeb.Scheduling.AcademicProgramStateUtils
  alias SnowSeToolsWeb.Scheduling.ScheduleViewerComponent

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      AcademicProgramPubSub.subscribe()
      ProgramDomainManager.request_programs(pid: self())
    end

    terms = list_terms()
    selected_term_code = default_selected_term_code(terms)
    courses = load_courses(selected_term_code)

    {:ok,
     socket
     |> assign(:page_title, "Scheduling")
     |> assign(:courses, courses)
     |> assign(:academic_programs, [])
     |> assign(:selected_program_id, nil)
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

  def handle_info({:academic_programs, {:action_result, result}}, socket) do
    send_update(AcademicProgramEditorComponent,
      id: "academic-program-editor",
      action_result: result
    )

    case result do
      {:ok, _message, _program} ->
        send_update(AcademicProgramsComponent,
          id: "academic-programs",
          cancel_edit: true
        )

      {:error, reason} ->
        Logger.error("Scheduling: action result error #{inspect(reason)}")
    end

    {:noreply, new_socket} =
      AcademicProgramStateUtils.handle_message({:action_result, result}, socket)

    {:noreply, new_socket}
  end

  def handle_info({:academic_programs, message}, socket) do
    {:noreply, new_socket} = AcademicProgramStateUtils.handle_message(message, socket)

    send_update(ScheduleViewerComponent,
      id: "schedule-viewer",
      academic_programs: Map.get(new_socket.assigns, :academic_programs, [])
    )

    {:noreply, new_socket}
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
              <.live_component
                module={ScheduleViewerComponent}
                id="schedule-viewer"
                academic_programs={@academic_programs}
              />
            <% :programs -> %>
              <.live_component
                module={AcademicProgramsComponent}
                id="academic-programs"
                courses={@courses}
                programs={@academic_programs}
                selected_program_id={@selected_program_id}
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

  defp list_terms do
    case SnowCourseCacheDb.list_terms_with_courses() do
      {:error, reason} ->
        Logger.error("SchedulingLive: failed to list terms: #{inspect(reason)}")
        []

      terms ->
        terms
    end
  end

  defp default_selected_term_code([]), do: nil
  defp default_selected_term_code([term | _]), do: term["term_code"]

  defp load_courses(nil), do: []

  defp load_courses(term_code) do
    case SnowCourseCacheDb.list_course_data_for_term(term_code: term_code) do
      {:ok, courses} ->
        courses

      {:error, reason} ->
        Logger.error(
          "SchedulingLive: failed to load courses for term=#{term_code}: #{inspect(reason)}"
        )

        []
    end
  end
end
