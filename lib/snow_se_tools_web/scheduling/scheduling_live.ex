defmodule SnowSeToolsWeb.Scheduling.SchedulingLive do
  use SnowSeToolsWeb, :live_view
  require Logger

  alias SnowSeTools.AcademicPrograms.{AcademicProgramPubSub, ProgramAttrs, ProgramDomainManager}
  alias SnowSeTools.Snow.SnowCourseCacheDb
  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramsPanel
  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramsState
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
     |> assign(:academic_programs_selected_program_id, nil)
     |> assign(:academic_programs_editing?, false)
     |> assign(:academic_programs_editor_state, AcademicProgramsState.new_editor_state())
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

  def handle_event("academic-programs:new", _params, socket) do
    {:noreply,
     socket
     |> assign(:academic_programs_selected_program_id, nil)
     |> assign(:academic_programs_editing?, true)
     |> assign(:academic_programs_editor_state, AcademicProgramsState.new_editor_state())}
  end

  def handle_event("academic-programs:select", %{"program_id" => program_id}, socket) do
    {:noreply,
     socket
     |> assign(:academic_programs_selected_program_id, program_id)
     |> assign(:academic_programs_editing?, false)}
  end

  def handle_event("academic-programs:edit", _params, socket) do
    selected_program = selected_program(socket)

    case selected_program do
      nil ->
        Logger.error("SchedulingLive: edit requested without a selected academic program")
        {:noreply, socket}

      program ->
        {:noreply,
         socket
         |> assign(:academic_programs_editing?, true)
         |> assign(
           :academic_programs_editor_state,
           AcademicProgramsState.load_program(
             socket.assigns.academic_programs_editor_state,
             program
           )
         )}
    end
  end

  def handle_event("academic-programs:cancel-edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:academic_programs_editing?, false)
     |> assign(
       :academic_programs_editor_state,
       AcademicProgramsState.reset_editor(socket.assigns.academic_programs_editor_state)
     )}
  end

  def handle_event("academic-programs-editor:update", params, socket) when is_map(params) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.update_editor_from_form(
         socket.assigns.academic_programs_editor_state,
         params
       )
     )}
  end

  def handle_event(
        "academic-programs-picker:update",
        %{"semester_index" => semester_index, "course_index" => course_index, "value" => value},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.picker_update(
         socket.assigns.academic_programs_editor_state,
         AcademicProgramsState.parse_index(semester_index),
         AcademicProgramsState.parse_index(course_index),
         value
       )
     )}
  end

  def handle_event(
        "academic-programs-picker:update",
        %{
          "_target" => ["course", semester_index, course_index]
        } = params,
        socket
      ) do
    value =
      params
      |> Map.get("course", %{})
      |> Map.get(semester_index, %{})
      |> Map.get(course_index, "")

    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.picker_update(
         socket.assigns.academic_programs_editor_state,
         AcademicProgramsState.parse_index(semester_index),
         AcademicProgramsState.parse_index(course_index),
         value
       )
     )}
  end

  def handle_event(
        "academic-programs-picker:update",
        %{"course" => course_params, "value" => value},
        socket
      )
      when is_map(course_params) do
    {semester_index, course_index} = first_course_param_indexes(course_params)

    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.picker_update(
         socket.assigns.academic_programs_editor_state,
         semester_index,
         course_index,
         value
       )
     )}
  end

  def handle_event(
        "academic-programs-picker:focus",
        %{"semester_index" => semester_index, "course_index" => course_index},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.picker_focus(
         socket.assigns.academic_programs_editor_state,
         AcademicProgramsState.parse_index(semester_index),
         AcademicProgramsState.parse_index(course_index)
       )
     )}
  end

  def handle_event(
        "academic-programs-picker:blur",
        %{"semester_index" => semester_index, "course_index" => course_index},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.picker_blur(
         socket.assigns.academic_programs_editor_state,
         AcademicProgramsState.parse_index(semester_index),
         AcademicProgramsState.parse_index(course_index)
       )
     )}
  end

  def handle_event(
        "academic-programs-picker:keydown",
        %{"semester_index" => semester_index, "course_index" => course_index, "key" => key},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.picker_keydown(
         socket.assigns.academic_programs_editor_state,
         socket.assigns.courses,
         AcademicProgramsState.parse_index(semester_index),
         AcademicProgramsState.parse_index(course_index),
         key
       )
     )}
  end

  def handle_event(
        "academic-programs-picker:select",
        %{
          "semester_index" => semester_index,
          "course_index" => course_index,
          "selected" => value
        },
        socket
      ) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.select_course(
         socket.assigns.academic_programs_editor_state,
         AcademicProgramsState.parse_index(semester_index),
         AcademicProgramsState.parse_index(course_index),
         value
       )
     )}
  end

  def handle_event("academic-programs-editor:add-semester", _params, socket) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.add_semester(socket.assigns.academic_programs_editor_state)
     )}
  end

  def handle_event("academic-programs-editor:remove-semester", %{"index" => index}, socket) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.remove_semester(
         socket.assigns.academic_programs_editor_state,
         AcademicProgramsState.parse_index(index)
       )
     )}
  end

  def handle_event(
        "academic-programs-editor:add-course",
        %{"semester_index" => semester_index},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.add_course(
         socket.assigns.academic_programs_editor_state,
         AcademicProgramsState.parse_index(semester_index)
       )
     )}
  end

  def handle_event(
        "academic-programs-editor:remove-course",
        %{"semester_index" => semester_index, "course_index" => course_index},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       :academic_programs_editor_state,
       AcademicProgramsState.remove_course(
         socket.assigns.academic_programs_editor_state,
         AcademicProgramsState.parse_index(semester_index),
         AcademicProgramsState.parse_index(course_index)
       )
     )}
  end

  def handle_event("academic-programs-editor:save", _params, socket) do
    editor_state = socket.assigns.academic_programs_editor_state

    case ProgramAttrs.parse(editor_state.editor) do
      {:ok, program} ->
        updated_editor_state = AcademicProgramsState.start_save(editor_state)

        if updated_editor_state.editing_id do
          ProgramDomainManager.update_program(
            pid: self(),
            id: updated_editor_state.editing_id,
            program: program
          )
        else
          ProgramDomainManager.create_program(pid: self(), program: program)
        end

        {:noreply, assign(socket, :academic_programs_editor_state, updated_editor_state)}

      {:error, reason} ->
        {:noreply,
         assign(
           socket,
           :academic_programs_editor_state,
           %{editor_state | pending_action: nil, error: inspect(reason)}
         )}
    end
  end

  def handle_info({:academic_programs, {:action_result, result}}, socket) do
    updated_socket =
      socket
      |> assign(
        :academic_programs_editor_state,
        AcademicProgramsState.apply_action_result(
          socket.assigns.academic_programs_editor_state,
          result
        )
      )
      |> handle_action_result_socket(result)

    updated_socket =
      case result do
        {:ok, _message, _program} ->
          assign(updated_socket, :academic_programs_editing?, false)

        {:error, reason} ->
          Logger.error("Scheduling: action result error #{inspect(reason)}")
          updated_socket
      end

    {:noreply, new_socket} =
      AcademicProgramStateUtils.handle_message({:action_result, result}, updated_socket)

    {:noreply, new_socket}
  end

  def handle_info({:academic_programs, message}, socket) do
    {:noreply, new_socket} = AcademicProgramStateUtils.handle_message(message, socket)

    if socket.assigns.mode == :viewer do
      send_update(ScheduleViewerComponent,
        id: "schedule-viewer",
        academic_programs: Map.get(new_socket.assigns, :academic_programs, [])
      )
    end

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
              <AcademicProgramsPanel.render
                courses={@courses}
                programs={@academic_programs}
                selected_program_id={@academic_programs_selected_program_id}
                editing?={@academic_programs_editing?}
                editor_state={@academic_programs_editor_state}
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

  defp selected_program(socket) do
    Enum.find(
      socket.assigns.academic_programs,
      &(&1["id"] == socket.assigns.academic_programs_selected_program_id)
    )
  end

  defp first_course_param_indexes(course_params) do
    case Enum.at(course_params, 0) do
      {semester_index, nested_courses} when is_map(nested_courses) ->
        case Enum.at(nested_courses, 0) do
          {course_index, _value} ->
            {
              AcademicProgramsState.parse_index(semester_index),
              AcademicProgramsState.parse_index(course_index)
            }

          _ ->
            {0, 0}
        end

      _ ->
        {0, 0}
    end
  end

  defp handle_action_result_socket(socket, {:ok, _message, program}) do
    case program do
      %{"id" => program_id} ->
        assign(socket, :academic_programs_selected_program_id, program_id)

      _ ->
        socket
    end
  end

  defp handle_action_result_socket(socket, _result), do: socket
end
