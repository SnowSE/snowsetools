defmodule SnowSeToolsWeb.Scheduling.AcademicProgramsComponent do
  use SnowSeToolsWeb, :live_component

  alias SnowSeTools.AcademicPrograms.ProgramDomainManager

  def update(assigns, socket) do
    socket =
      socket
      |> assign(:programs, assigns[:programs] || [])
      |> assign_new(:editing_id, fn -> nil end)
      |> assign_new(:editor, fn -> blank_program() end)

    {:ok, socket}
  end

  def handle_event("new_program", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, editor: blank_program())}
  end

  def handle_event("select_program", %{"id" => id}, socket) do
    editor =
      socket.assigns.programs
      |> Enum.find(&(&1["id"] == id))
      |> case do
        nil -> blank_program()
        program -> editor_from_program(program)
      end

    {:noreply, assign(socket, editing_id: id, editor: editor)}
  end

  def handle_event("update_program_name", %{"name" => name}, socket) do
    {:noreply, update(socket, :editor, &Map.put(&1, "name", name))}
  end

  def handle_event("add_semester", _params, socket) do
    {:noreply, update(socket, :editor, &add_semester/1)}
  end

  def handle_event("remove_semester", %{"index" => index}, socket) do
    {:noreply, update(socket, :editor, &remove_semester(&1, parse_index(index)))}
  end

  def handle_event("update_semester_name", %{"index" => index, "name" => name}, socket) do
    {:noreply, update(socket, :editor, &update_semester_name(&1, parse_index(index), name))}
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

  def handle_event(
        "update_course",
        %{
          "semester_index" => semester_index,
          "course_index" => course_index,
          "subject_code" => subject_code,
          "course_number" => course_number
        },
        socket
      ) do
    {:noreply,
     update(
       socket,
       :editor,
       &update_course(
         &1,
         parse_index(semester_index),
         parse_index(course_index),
         subject_code,
         course_number
       )
     )}
  end

  def handle_event("save_program", _params, socket) do
    attrs = socket.assigns.editor

    if socket.assigns.editing_id do
      ProgramDomainManager.update_program(pid: self(), id: socket.assigns.editing_id, attrs: attrs)
    else
      ProgramDomainManager.create_program(pid: self(), attrs: attrs)
    end

    {:noreply, socket}
  end

  def handle_event("delete_program", _params, socket) do
    if socket.assigns.editing_id do
      ProgramDomainManager.delete_program(pid: self(), id: socket.assigns.editing_id)
    end

    {:noreply, assign(socket, editing_id: nil, editor: blank_program())}
  end

  def render(assigns) do
    ~H"""
    <div id="academic-programs-panel" class="mx-auto grid h-full min-h-0 w-full max-w-[1600px] grid-cols-[22rem_1fr] gap-4 p-4">
      <aside class="flex min-h-0 flex-col gap-3">
        <div class="flex items-center justify-between gap-2">
          <div>
            <h2 class="text-sm font-semibold text-slate-100">Academic Programs</h2>
            <p class="text-xs text-slate-500">Program semesters appear in schedule search.</p>
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

        <div id="academic-program-list" class="min-h-0 flex-1 space-y-2 overflow-y-auto pe-2">
          <div :if={@programs == []} class="rounded-lg border border-dashed border-slate-800 p-6 text-center text-sm text-slate-500">
            No programs yet.
          </div>

          <%= for program <- @programs do %>
            <button
              id={"academic-program-#{program["id"]}"}
              type="button"
              phx-click="select_program"
              phx-target={@myself}
              phx-value-id={program["id"]}
              class={[
                "w-full rounded-lg border px-3 py-2 text-left transition",
                if(@editing_id == program["id"],
                  do: "border-indigo-500/50 bg-indigo-950/50 text-indigo-100",
                  else:
                    "border-slate-800 bg-slate-900/45 text-slate-200 hover:border-slate-700 hover:bg-slate-900"
                )
              ]}
            >
              <span class="block truncate text-sm font-medium">{program["name"]}</span>
              <span class="mt-0.5 block text-xs text-slate-500">
                {length(program["semesters"] || [])} semesters
              </span>
            </button>
          <% end %>
        </div>
      </aside>

      <section class="min-h-0 overflow-y-auto rounded-lg border border-slate-800 bg-slate-950/45 p-4">
        <div class="mb-4 flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h2 class="text-base font-semibold text-slate-100">
              <%= if @editing_id, do: "Edit Program", else: "New Program" %>
            </h2>
            <p class="text-xs text-slate-500">
              Define catalog requirements by planned academic semester.
            </p>
          </div>

          <button
            :if={@editing_id}
            id="delete-academic-program"
            type="button"
            phx-click="delete_program"
            phx-target={@myself}
            data-confirm="Delete this academic program?"
            class="inline-flex items-center gap-1 rounded-md bg-red-950/45 px-2.5 py-1.5 text-xs font-medium text-red-200 transition hover:bg-red-900/60"
          >
            <.icon name="hero-trash" class="size-3.5" /> Delete
          </button>
        </div>

        <.form
          for={to_form(%{})}
          id="academic-program-name-form"
          phx-change="update_program_name"
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
        </.form>

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

          <div :if={@editor["semesters"] == []} class="rounded-lg border border-dashed border-slate-800 p-6 text-center text-sm text-slate-500">
            Add a semester, then add required courses.
          </div>

          <%= for {semester, semester_index} <- Enum.with_index(@editor["semesters"]) do %>
            <div class="rounded-lg border border-slate-800 bg-slate-900/35 p-3">
              <div class="mb-3 flex items-start gap-2">
                <.form
                  for={to_form(%{})}
                  id={"program-semester-name-form-#{semester_index}"}
                  phx-change="update_semester_name"
                  phx-target={@myself}
                  phx-value-index={semester_index}
                  class="min-w-0 flex-1"
                >
                  <label for={"program-semester-name-#{semester_index}"} class="sr-only">
                    Semester name
                  </label>
                  <input
                    id={"program-semester-name-#{semester_index}"}
                    name="name"
                    value={semester["name"]}
                    placeholder="Freshman first semester"
                    class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
                  />
                </.form>
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
                  <.form
                    for={to_form(%{})}
                    id={"program-course-form-#{semester_index}-#{course_index}"}
                    phx-change="update_course"
                    phx-target={@myself}
                    phx-value-semester_index={semester_index}
                    phx-value-course_index={course_index}
                    class="grid grid-cols-[7rem_1fr_auto] gap-2"
                  >
                    <input
                      id={"program-course-subject-#{semester_index}-#{course_index}"}
                      name="subject_code"
                      value={course["subject_code"]}
                      placeholder="CE"
                      class="rounded-md border border-slate-700 bg-slate-950/70 px-2 py-1.5 text-sm uppercase text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
                    />
                    <input
                      id={"program-course-number-#{semester_index}-#{course_index}"}
                      name="course_number"
                      value={course["course_number"]}
                      placeholder="1010"
                      class="rounded-md border border-slate-700 bg-slate-950/70 px-2 py-1.5 text-sm text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
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
                  </.form>
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
      </section>
    </div>
    """
  end

  defp blank_program do
    %{
      "name" => "",
      "semesters" => [
        %{"name" => "Freshman first semester", "courses" => [%{"subject_code" => "", "course_number" => ""}]}
      ]
    }
  end

  defp editor_from_program(program) do
    %{
      "name" => program["name"] || "",
      "semesters" =>
        Enum.map(program["semesters"] || [], fn semester ->
          %{
            "name" => semester["name"] || "",
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
      semesters ++ [%{"name" => "", "courses" => [%{"subject_code" => "", "course_number" => ""}]}]
    end)
  end

  defp remove_semester(editor, index) do
    update_in(editor, ["semesters"], &List.delete_at(&1, index))
  end

  defp update_semester_name(editor, index, name) do
    update_in(editor, ["semesters"], fn semesters ->
      List.update_at(semesters, index, &Map.put(&1, "name", name))
    end)
  end

  defp add_course(editor, semester_index) do
    update_in(editor, ["semesters"], fn semesters ->
      List.update_at(semesters, semester_index, fn semester ->
        update_in(semester, ["courses"], &(&1 ++ [%{"subject_code" => "", "course_number" => ""}]))
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

  defp update_course(editor, semester_index, course_index, subject_code, course_number) do
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
end
