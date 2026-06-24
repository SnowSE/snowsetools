defmodule SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramsPanel do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.AcademicPrograms.{AcademicProgramPubSub, ProgramDomainManager}
  alias SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker
  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramEditor

  defstruct [:key, :selected_program_id, :editing?, :editor_key, :picker_key]

  def assign_component(socket, key, opts \\ []) do
    socket
    |> assign_new(:academic_programs, fn -> [] end)
    |> assign(
      key,
      socket.assigns[key] ||
        %__MODULE__{
          key: key,
          selected_program_id: nil,
          editing?: false,
          editor_key: opts[:editor_key] || :academic_program_editor,
          picker_key: opts[:picker_key] || :academic_program_course_picker
        }
    )
    |> initial_setup()
  end

  def render(assigns) do
    assigns = assign(assigns, :selected_program, selected_program(assigns))

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
          phx-click="academic-programs:new"
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

          <.program_list_item
            :for={program <- @programs}
            program={program}
            is_selected={@state.selected_program_id == program["id"]}
          />
        </div>
      </aside>

      <div :if={@state.editing?}>
        <AcademicProgramEditor.render
          state={@editor_state}
          picker_state={@picker_state}
        />
      </div>

      <.program_display :if={!@state.editing?} program={@selected_program} />
    </div>
    """
  end

  def maybe_attach_hooks(socket) do
    if Map.get(socket.private, :academic_programs_panel_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("academic-programs-panel:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("academic-programs-panel:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :academic_programs_panel_hooks_attached?], true)
    end
  end

  defp initial_setup(socket) do
    socket
    |> maybe_attach_hooks()
    |> maybe_request_initial_data()
  end

  defp maybe_request_initial_data(socket) do
    if LiveView.connected?(socket) and
         !Map.get(socket.private, :academic_programs_panel_initial_data_requested?) do
      AcademicProgramPubSub.subscribe()
      ProgramDomainManager.request_programs(pid: self())

      put_in(
        socket,
        [Access.key(:private), :academic_programs_panel_initial_data_requested?],
        true
      )
    else
      socket
    end
  end

  def hooked_info({:academic_programs, {:loaded, {:ok, programs}}}, socket) do
    {:halt, assign(socket, :academic_programs, sort_programs(programs))}
  end

  def hooked_info({:academic_programs, {:loaded, {:error, reason}}}, socket) do
    Logger.error("AcademicProgramsPanel failed to load programs reason=#{inspect(reason)}")
    {:halt, LiveView.put_flash(socket, :error, "Could not load academic programs.")}
  end

  def hooked_info({:academic_programs, {:program_created, program}}, socket) do
    programs =
      socket.assigns.academic_programs
      |> Enum.reject(&(&1["id"] == program["id"]))
      |> Kernel.++([program])
      |> sort_programs()

    {:halt, assign(socket, :academic_programs, programs)}
  end

  def hooked_info({:academic_programs, {:program_updated, program}}, socket) do
    programs =
      socket.assigns.academic_programs
      |> Enum.map(fn existing ->
        if existing["id"] == program["id"], do: program, else: existing
      end)
      |> sort_programs()

    {:halt, assign(socket, :academic_programs, programs)}
  end

  def hooked_info({:academic_programs, {:program_deleted, program_id}}, socket) do
    programs = Enum.reject(socket.assigns.academic_programs, &(&1["id"] == program_id))

    socket =
      socket
      |> assign(:academic_programs, programs)
      |> clear_deleted_selection(program_id: program_id)

    {:halt, socket}
  end

  def hooked_info({:academic_programs, {:action_result, result}}, socket) do
    case result do
      {:error, reason} ->
        Logger.error("Scheduling: academic program action failed reason=#{inspect(reason)}")

      _ ->
        :ok
    end

    {:halt, apply_action_result(socket, result)}
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  def hooked_event("academic-programs:new", _params, socket) do
    panel_state = panel_state(socket)
    editor_key = panel_state.editor_key
    picker_key = panel_state.picker_key

    {:halt,
     socket
     |> assign(panel_key(socket), %{panel_state | selected_program_id: nil, editing?: true})
     |> assign(editor_key, AcademicProgramEditor.reset(socket.assigns[editor_key]))
     |> assign(picker_key, AcademicProgramCoursePicker.reset(socket.assigns[picker_key]))}
  end

  def hooked_event("academic-programs:select", %{"program_id" => program_id}, socket) do
    {:halt,
     assign(socket, panel_key(socket), %{
       panel_state(socket)
       | selected_program_id: program_id,
         editing?: false
     })}
  end

  def hooked_event("academic-programs:edit", _params, socket) do
    panel_state = panel_state(socket)

    selected_program =
      selected_program(socket.assigns.academic_programs, panel_state.selected_program_id)

    case selected_program do
      nil ->
        {:halt, socket}

      program ->
        {:halt,
         socket
         |> assign(panel_key(socket), %{panel_state | editing?: true})
         |> assign(
           panel_state.editor_key,
           AcademicProgramEditor.load_program(socket.assigns[panel_state.editor_key], program)
         )
         |> assign(
           panel_state.picker_key,
           AcademicProgramCoursePicker.reset(socket.assigns[panel_state.picker_key])
         )}
    end
  end

  def hooked_event("academic-programs:cancel-edit", _params, socket) do
    panel_state = panel_state(socket)

    {:halt,
     socket
     |> assign(panel_key(socket), %{panel_state | editing?: false})
     |> assign(
       panel_state.editor_key,
       AcademicProgramEditor.reset(socket.assigns[panel_state.editor_key])
     )
     |> assign(
       panel_state.picker_key,
       AcademicProgramCoursePicker.reset(socket.assigns[panel_state.picker_key])
     )}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def apply_action_result(socket, result) do
    panel_state = panel_state(socket)
    editor_state = socket.assigns[panel_state.editor_key]
    updated_editor = AcademicProgramEditor.apply_action_result(editor_state, result)

    socket =
      socket
      |> assign(panel_state.editor_key, updated_editor)
      |> maybe_select_program_from_result(result)

    case result do
      {:ok, _message, _program} ->
        socket
        |> assign(panel_key(socket), %{panel_state(socket) | editing?: false})
        |> assign(
          panel_state.picker_key,
          AcademicProgramCoursePicker.reset(socket.assigns[panel_state.picker_key])
        )

      _ ->
        socket
    end
  end

  attr :program, :map, required: true
  attr :is_selected, :boolean, default: false

  defp program_list_item(assigns) do
    ~H"""
    <button
      id={"academic-program-#{@program["id"]}"}
      type="button"
      phx-click="academic-programs:select"
      phx-value-program_id={@program["id"]}
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

  attr :program, :map, default: nil

  defp program_display(assigns) do
    ~H"""
    <div>
      <div :if={@program}>
        <div class="min-h-0 overflow-y-auto rounded-lg border border-slate-800 bg-slate-950/45 p-4">
          <div class="mb-4 flex items-start justify-between gap-3">
            <div>
              <h2 id="academic-program-display-name" class="text-base font-semibold text-slate-100">
                {@program["name"]}
              </h2>
              <p class="text-xs text-slate-500">
                {length(@program["semesters"] || [])} semesters · {total_courses(
                  @program["semesters"] || []
                )} required courses
              </p>
            </div>

            <button
              id="edit-academic-program"
              type="button"
              phx-click="academic-programs:edit"
              class="inline-flex items-center gap-1 rounded-md bg-indigo-500/15 px-2.5 py-1.5 text-xs font-medium text-indigo-200 transition hover:bg-indigo-500/25"
            >
              <.icon name="hero-pencil" class="size-3.5" /> Edit
            </button>
          </div>

          <div class="space-y-3 grid grid-cols-2">
            <%= for {semester, semester_index} <- Enum.with_index(@program["semesters"]) do %>
              <div class="rounded-lg border border-slate-800 bg-slate-900/35 p-3">
                <div class="mb-2 flex items-center justify-between">
                  <span
                    id={"academic-program-semester-#{semester_index}-label"}
                    class="text-sm font-medium text-slate-100"
                  >
                    {semester_label(semester_index)}
                  </span>
                  <span class="text-xs text-slate-500">
                    {length(semester["courses"] || [])} courses
                  </span>
                </div>

                <div :if={(semester["courses"] || []) != []} class="flex flex-wrap gap-1.5">
                  <%= for course <- semester["courses"] do %>
                    <span
                      id={"academic-program-semester-#{semester_index}-course-#{course["position"] || 0}"}
                      class="inline-flex items-center rounded-md bg-slate-800 px-2 py-0.5 text-xs text-slate-300"
                    >
                      {course_label(course)}
                    </span>
                  <% end %>
                </div>

                <p :if={(semester["courses"] || []) == []} class="text-xs text-slate-600">
                  No courses required.
                </p>
              </div>
            <% end %>
          </div>

          <div
            :if={(@program["semesters"] || []) == []}
            class="mt-3 rounded-lg border border-dashed border-slate-800 p-4 text-center text-sm text-slate-500"
          >
            No semesters configured.
          </div>
        </div>
      </div>

      <div
        :if={!@program}
        class="min-h-0 flex items-center justify-center rounded-lg border border-dashed border-slate-800 bg-slate-950/45"
      >
        <p class="text-sm text-slate-500">Select a program to view details.</p>
      </div>
    </div>
    """
  end

  defp selected_program(assigns),
    do: selected_program(assigns.programs, assigns.state.selected_program_id)

  defp selected_program(programs, selected_program_id) do
    Enum.find(programs, &(&1["id"] == selected_program_id))
  end

  defp panel_key(_socket), do: :academic_programs_panel
  defp panel_state(socket), do: socket.assigns[panel_key(socket)]

  defp maybe_select_program_from_result(socket, {:ok, _message, %{"id" => program_id}}) do
    assign(socket, panel_key(socket), %{panel_state(socket) | selected_program_id: program_id})
  end

  defp maybe_select_program_from_result(socket, _result), do: socket

  defp clear_deleted_selection(socket, program_id: program_id) do
    panel_state = panel_state(socket)

    if panel_state.selected_program_id == program_id do
      assign(socket, panel_key(socket), %{panel_state | selected_program_id: nil, editing?: false})
    else
      socket
    end
  end

  defp sort_programs(programs), do: Enum.sort_by(programs, &String.downcase(&1["name"] || ""))

  defp course_label(course) do
    subject = Map.get(course, "subject_code", "")
    number = Map.get(course, "course_number", "")

    cond do
      subject && number -> "#{subject} #{number}"
      subject -> subject
      number -> number
      true -> ""
    end
  end

  defp total_courses(semesters) do
    Enum.reduce(semesters, 0, fn semester, acc -> acc + length(semester["courses"] || []) end)
  end

  defp semester_label(0), do: "Freshman first semester"
  defp semester_label(1), do: "Freshman second semester"
  defp semester_label(2), do: "Sophomore first semester"
  defp semester_label(3), do: "Sophomore second semester"
  defp semester_label(4), do: "Junior first semester"
  defp semester_label(5), do: "Junior second semester"
  defp semester_label(6), do: "Senior first semester"
  defp semester_label(7), do: "Senior second semester"
  defp semester_label(index), do: "Year #{div(index, 2) + 1} semester #{rem(index, 2) + 1}"
end
