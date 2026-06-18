defmodule SnowSeToolsWeb.Scheduling.AcademicProgramEditorComponent do
  use SnowSeToolsWeb, :live_component

  alias SnowSeTools.AcademicPrograms.ProgramDomainManager
  alias SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker
  alias SnowSeToolsWeb.Scheduling.AcademicProgramCourseSearch

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:courses, Map.get(assigns, :courses, socket.assigns[:courses] || []))
      |> assign_new(:editing_id, fn -> nil end)
      |> assign_new(:editor, fn -> blank_program() end)
      |> assign_new(:pending_action, fn -> nil end)
      |> assign_new(:error, fn -> nil end)

    socket =
      case assigns[:selected_program] do
        nil -> socket
        program -> load_program(socket, program)
      end

    socket =
      case assigns[:update_course] do
        {semester_index, course_index, value} ->
          update(socket, :editor, &update_course(&1, semester_index, course_index, value))

        _ ->
          socket
      end

    socket =
      case assigns[:select_course] do
        {semester_index, course_index, value} ->
          socket =
            update(socket, :editor, &update_course(&1, semester_index, course_index, value))

          push_event(socket, "academic_program_course_selected", %{
            semester_index: semester_index,
            course_index: course_index,
            value: value
          })

        _ ->
          socket
      end

    case assigns[:action_result] do
      nil -> {:ok, socket}
      result -> {:ok, apply_action_result(socket, result)}
    end
  end

  def handle_event("new_program", _params, socket) do
    send(self(), {:academic_program_selected, nil})

    {:noreply,
     assign(socket,
       editing_id: nil,
       editor: blank_program(),
       pending_action: nil,
       error: nil
     )}
  end

  def handle_event("update_editor", %{"_target" => ["name"], "name" => name}, socket) do
    {:noreply, update(socket, :editor, &Map.put(&1, "name", name))}
  end

  def handle_event("add_semester", _params, socket) do
    {:noreply, update(socket, :editor, &add_semester/1)}
  end

  def handle_event(
        "update_editor",
        %{"_target" => ["course", semester_index, course_index]} = params,
        socket
      ) do
    semester_index = parse_index(semester_index)
    course_index = parse_index(course_index)
    course_value = nested_course_value(params, semester_index, course_index)

    {:noreply,
     update(socket, :editor, &update_course(&1, semester_index, course_index, course_value))}
  end

  def handle_event("remove_semester", %{"index" => index}, socket) do
    {:noreply, update(socket, :editor, &remove_semester(&1, parse_index(index)))}
  end

  def handle_event("add_course", %{"semester_index" => semester_index}, socket) do
    {:noreply, update(socket, :editor, &add_course(&1, parse_index(semester_index)))}
  end

  def handle_event(
        "remove_course",
        %{"semester_index" => semester_index, "course_index" => course_index},
        socket
      ) do
    {:noreply,
     update(
       socket,
       :editor,
       &remove_course(&1, parse_index(semester_index), parse_index(course_index))
     )}
  end

  def handle_event("save_program", _params, socket) do
    attrs = socket.assigns.editor

    socket =
      assign(socket,
        pending_action: if(socket.assigns.editing_id, do: :update, else: :create),
        error: nil
      )

    if socket.assigns.editing_id do
      ProgramDomainManager.update_program(
        pid: self(),
        id: socket.assigns.editing_id,
        attrs: attrs
      )
    else
      ProgramDomainManager.create_program(pid: self(), attrs: attrs)
    end

    {:noreply, socket}
  end

  def handle_event("delete_program", _params, socket) do
    if socket.assigns.editing_id do
      socket = assign(socket, pending_action: :delete, error: nil)
      ProgramDomainManager.delete_program(pid: self(), id: socket.assigns.editing_id)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <section class="min-h-0 overflow-y-auto rounded-lg border border-slate-800 bg-slate-950/45 p-4">
      <div class="mb-4 flex items-start justify-between gap-3">
        <div class="min-w-0">
          <h2 class="text-base font-semibold text-slate-100">
            {if @editing_id, do: "Edit Program", else: "New Program"}
          </h2>
          <p class="text-xs text-slate-500">
            Define catalog requirements by planned academic semester.
          </p>
        </div>

        <button
          id="new-academic-program"
          type="button"
          phx-click="new_program"
          phx-target={@myself}
          class="inline-flex items-center gap-1 rounded-md bg-indigo-500/15 px-2.5 py-1.5 text-xs font-medium text-indigo-200 transition hover:bg-indigo-500/25"
        >
          <.icon name="hero-plus" class="size-3.5" /> New
        </button>
      </div>

      <div
        :if={@error}
        id="academic-program-editor-error"
        class="mb-4 rounded-lg border border-red-900/60 bg-red-950/40 px-3 py-2 text-sm text-red-200"
      >
        {@error}
      </div>

      <.form
        for={to_form(%{})}
        id="academic-program-editor-form"
        phx-change="update_editor"
        phx-target={@myself}
      >
        <label for="academic-program-name" class="mb-1 block text-xs font-medium text-slate-400">
          Program name
        </label>
        <input
          id="academic-program-name"
          name="name"
          value={@editor["name"]}
          placeholder="Civil Engineering"
          class="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        />

        <div class="mt-5 space-y-3">
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-sm font-semibold text-slate-200">Semesters</h3>
            <button
              id="add-program-semester"
              type="button"
              phx-click="add_semester"
              phx-target={@myself}
              class="inline-flex items-center gap-1 rounded-md border border-slate-700 px-2.5 py-1.5 text-xs font-medium text-slate-300 transition hover:border-slate-600 hover:bg-slate-900"
            >
              <.icon name="hero-plus" class="size-3.5" /> Semester
            </button>
          </div>

          <div
            :if={@editor["semesters"] == []}
            class="rounded-lg border border-dashed border-slate-800 p-6 text-center text-sm text-slate-500"
          >
            Add a semester, then add required courses.
          </div>

          <%= for {semester, semester_index} <- Enum.with_index(@editor["semesters"]) do %>
            <div class="rounded-lg border border-slate-800 bg-slate-900/35 p-3">
              <div class="mb-3 flex items-start gap-2">
                <div class="min-w-0 flex-1">
                  <span class="block text-sm font-medium text-slate-100">
                    {semester_label(semester_index)}
                  </span>
                  <span class="block text-xs text-slate-500">
                    {length(semester["courses"] || [])} required courses
                  </span>
                </div>
                <button
                  type="button"
                  phx-click="remove_semester"
                  phx-target={@myself}
                  phx-value-index={semester_index}
                  class="rounded p-2 text-slate-500 transition hover:bg-slate-800 hover:text-red-200"
                  aria-label="Remove semester"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>

              <div class="space-y-2">
                <%= for {course, course_index} <- Enum.with_index(semester["courses"]) do %>
                  <div class="grid grid-cols-[1fr_auto] gap-2">
                    <.live_component
                      module={AcademicProgramCoursePicker}
                      id={"course-picker-#{semester_index}-#{course_index}"}
                      semester_index={semester_index}
                      course_index={course_index}
                      course={course}
                      courses={@courses}
                    />
                    <button
                      type="button"
                      phx-click="remove_course"
                      phx-target={@myself}
                      phx-value-semester_index={semester_index}
                      phx-value-course_index={course_index}
                      class="rounded p-1.5 text-slate-500 transition hover:bg-slate-800 hover:text-red-200"
                      aria-label="Remove course"
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </div>
                <% end %>

                <button
                  type="button"
                  phx-click="add_course"
                  phx-target={@myself}
                  phx-value-semester_index={semester_index}
                  class="inline-flex items-center gap-1 rounded-md px-2 py-1.5 text-xs font-medium text-slate-400 transition hover:bg-slate-800 hover:text-slate-200"
                >
                  <.icon name="hero-plus" class="size-3.5" /> Course
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <div class="sticky bottom-0 mt-5 flex justify-end border-t border-slate-800 bg-slate-950/95 pt-3">
          <button
            id="save-academic-program"
            type="button"
            phx-click="save_program"
            phx-target={@myself}
            disabled={String.trim(@editor["name"]) == ""}
            class={[
              "inline-flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition",
              if(String.trim(@editor["name"]) == "",
                do: "cursor-not-allowed bg-slate-800 text-slate-500",
                else: "bg-indigo-500 text-white hover:bg-indigo-400"
              )
            ]}
          >
            <.icon name="hero-check" class="size-4" /> Save Program
          </button>
        </div>
      </.form>
    </section>
    """
  end

  defp load_program(socket, program) do
    assign(socket,
      editing_id: program["id"],
      editor: editor_from_program(program),
      pending_action: nil,
      error: nil
    )
  end

  defp apply_action_result(socket, {:ok, _message, program}) do
    socket = assign(socket, error: nil)

    socket =
      case socket.assigns.pending_action do
        :create -> assign(socket, editing_id: nil, editor: blank_program())
        :delete -> assign(socket, editing_id: nil, editor: blank_program())
        _ -> socket
      end

    if program do
      send(self(), {:academic_program_selected, program["id"]})
    end

    assign(socket, pending_action: nil)
  end

  defp apply_action_result(socket, {:error, reason}) do
    assign(socket, pending_action: nil, error: format_error(reason))
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp blank_program do
    %{
      "name" => "",
      "semesters" => [
        %{
          "courses" => [%{"subject_code" => "", "course_number" => ""}]
        }
      ]
    }
  end

  defp editor_from_program(program) do
    %{
      "name" => program["name"] || "",
      "semesters" =>
        Enum.map(program["semesters"] || [], fn semester ->
          %{
            "courses" =>
              Enum.map(semester["courses"] || [], fn course ->
                %{
                  "subject_code" => course["subject_code"] || "",
                  "course_number" => course["course_number"] || ""
                }
              end)
          }
        end)
    }
  end

  defp add_semester(editor) do
    update_in(editor, ["semesters"], fn semesters ->
      semesters ++
        [%{"courses" => [%{"subject_code" => "", "course_number" => ""}]}]
    end)
  end

  defp remove_semester(editor, index) do
    update_in(editor, ["semesters"], &List.delete_at(&1, index))
  end

  defp add_course(editor, semester_index) do
    update_in(editor, ["semesters"], fn semesters ->
      List.update_at(semesters, semester_index, fn semester ->
        update_in(
          semester,
          ["courses"],
          &(&1 ++ [%{"subject_code" => "", "course_number" => ""}])
        )
      end)
    end)
  end

  defp remove_course(editor, semester_index, course_index) do
    update_in(editor, ["semesters"], fn semesters ->
      List.update_at(semesters, semester_index, fn semester ->
        update_in(semester, ["courses"], &List.delete_at(&1, course_index))
      end)
    end)
  end

  defp update_course(editor, semester_index, course_index, course_value) do
    {subject_code, course_number} = AcademicProgramCourseSearch.parse_course_input(course_value)

    update_in(editor, ["semesters"], fn semesters ->
      List.update_at(semesters, semester_index, fn semester ->
        update_in(semester, ["courses"], fn courses ->
          List.update_at(courses, course_index, fn course ->
            course
            |> Map.put("subject_code", subject_code)
            |> Map.put("course_number", course_number)
          end)
        end)
      end)
    end)
  end

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} -> index
      _ -> 0
    end
  end

  defp parse_index(value) when is_integer(value), do: value
  defp parse_index(_value), do: 0

  defp nested_course_value(params, semester_index, course_index) do
    params
    |> Map.get("course", %{})
    |> Map.get(Integer.to_string(semester_index), %{})
    |> Map.get(Integer.to_string(course_index), "")
  end

  defp semester_label(index) do
    case index do
      0 -> "Freshman first semester"
      1 -> "Freshman second semester"
      2 -> "Sophomore first semester"
      3 -> "Sophomore second semester"
      4 -> "Junior first semester"
      5 -> "Junior second semester"
      6 -> "Senior first semester"
      7 -> "Senior second semester"
      _ -> "Year #{div(index, 2) + 1} semester #{rem(index, 2) + 1}"
    end
  end
end
