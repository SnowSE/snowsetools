defmodule SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramEditor do
  use SnowSeToolsWeb, :html

  alias Phoenix.LiveView
  alias SnowSeTools.AcademicPrograms.{ProgramAttrs, ProgramDomainManager}
  alias SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker

  defstruct [:key, :editing_id, :editor, :pending_action, :error]

  def assign_component(socket, key, _opts \\ []) do
    socket
    |> assign(
      key,
      socket.assigns[key] ||
        %__MODULE__{
          key: key,
          editing_id: nil,
          editor: blank_program(),
          pending_action: nil,
          error: nil
        }
    )
    |> maybe_attach_hooks()
  end

  def render(assigns) do
    ~H"""
    <section class="min-h-0 overflow-y-auto rounded-lg border border-slate-800 bg-slate-950/45 p-4">
      <div class="mb-4">
        <h2 class="text-base font-semibold text-slate-100">
          {if @state.editing_id, do: "Edit Program", else: "New Program"}
        </h2>
      </div>

      <div
        :if={@state.error}
        id="academic-program-editor-error"
        class="mb-4 rounded-lg border border-red-900/60 bg-red-950/40 px-3 py-2 text-sm text-red-200"
      >
        {@state.error}
      </div>

      <.form
        for={to_form(%{})}
        id="academic-program-editor-form"
        phx-change="academic-programs-editor:update"
      >
        <label for="academic-program-name" class="mb-1 block text-xs font-medium text-slate-400">
          Program name
        </label>
        <input
          id="academic-program-name"
          name="name"
          value={@state.editor["name"]}
          placeholder="Civil Engineering"
          class="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        />

        <div class="mt-5 space-3 grid grid-cols-2 gap-3">
          <div
            :if={@state.editor["semesters"] == []}
            class="rounded-lg border border-dashed border-slate-800 p-6 text-center text-sm text-slate-500"
          >
            Add a semester, then add required courses.
          </div>

          <%= for {semester, semester_index} <- Enum.with_index(@state.editor["semesters"]) do %>
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
                  phx-click="academic-programs-editor:remove-semester"
                  phx-value-index={semester_index}
                  class="rounded p-2 text-slate-500 transition hover:bg-slate-800 hover:text-red-200"
                  aria-label="Remove semester"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>

              <div class="space-y-2">
                <%= for {_course, course_index} <- Enum.with_index(semester["courses"]) do %>
                  <div class="grid grid-cols-[1fr_auto] gap-2">
                    <AcademicProgramCoursePicker.render
                      state={@picker_state}
                      editor={@state}
                      courses={@courses}
                      semester_index={semester_index}
                      course_index={course_index}
                    />
                    <button
                      type="button"
                      phx-click="academic-programs-editor:remove-course"
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
                  phx-click="academic-programs-editor:add-course"
                  phx-value-semester_index={semester_index}
                  class={[
                    "inline-flex items-center gap-1 rounded-md",
                    "px-2 py-1.5 text-slate-400 transition hover:bg-slate-800 hover:text-slate-200"
                  ]}
                >
                  <.icon name="hero-plus" class="size-3.5" /> Course
                </button>
              </div>
            </div>
          <% end %>
          <button
            id="add-program-semester"
            type="button"
            phx-click="academic-programs-editor:add-semester"
            class={[
              "inline-flex items-center justify-center gap-1 rounded-md border border-dashed border-slate-700",
              "p-3 font-medium text-slate-300",
              "transition hover:border-slate-600 hover:bg-slate-900"
            ]}
          >
            <span>
              <.icon name="hero-plus" class="size-3.5" /> Add Semester
            </span>
          </button>
        </div>

        <div class="sticky bottom-0 mt-5 flex items-center justify-between border-t border-slate-800 bg-slate-950/95 pt-3">
          <button
            :if={@state.editing_id}
            type="button"
            phx-click="academic-programs:cancel-edit"
            class="inline-flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-slate-400 transition hover:bg-slate-800 hover:text-slate-200"
          >
            <.icon name="hero-x-mark" class="size-4" /> Cancel
          </button>

          <div :if={!@state.editing_id} />

          <button
            id="save-academic-program"
            type="button"
            phx-click="academic-programs-editor:save"
            disabled={String.trim(@state.editor["name"]) == ""}
            class={[
              "inline-flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition",
              if(String.trim(@state.editor["name"]) == "",
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

  def load_program(state, program) do
    %{
      state
      | editing_id: program["id"],
        editor: editor_from_program(program),
        pending_action: nil,
        error: nil
    }
  end

  def reset(state) do
    %__MODULE__{} = state

    %{
      state
      | editing_id: nil,
        editor: blank_program(),
        pending_action: nil,
        error: nil
    }
  end

  def apply_action_result(state, {:ok, _message, _program}) do
    cleared_error = %{state | error: nil}

    case cleared_error.pending_action do
      action when action in [:create, :delete] ->
        %{reset(cleared_error) | pending_action: nil}

      _ ->
        %{cleared_error | pending_action: nil}
    end
  end

  def apply_action_result(state, {:error, reason}) do
    %{state | pending_action: nil, error: format_error(reason)}
  end

  def maybe_attach_hooks(socket) do
    if Map.get(socket.private, :academic_program_editor_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("academic-programs-editor:event", :handle_event, &hooked_event/3)
      |> put_in([Access.key(:private), :academic_program_editor_hooks_attached?], true)
    end
  end

  def hooked_event("academic-programs-editor:update", %{"name" => name}, socket) do
    {:halt, update_state(socket, &%{&1 | editor: Map.put(&1.editor, "name", name)})}
  end

  def hooked_event("academic-programs-editor:update", _params, socket), do: {:cont, socket}

  def hooked_event("academic-programs-editor:add-semester", _params, socket) do
    {:halt, update_state(socket, &add_semester(&1))}
  end

  def hooked_event("academic-programs-editor:remove-semester", %{"index" => index}, socket) do
    {:halt, update_state(socket, &remove_semester(&1, parse_index(index)))}
  end

  def hooked_event(
        "academic-programs-editor:add-course",
        %{"semester_index" => semester_index},
        socket
      ) do
    {:halt, update_state(socket, &add_course(&1, parse_index(semester_index)))}
  end

  def hooked_event(
        "academic-programs-editor:remove-course",
        %{"semester_index" => semester_index, "course_index" => course_index},
        socket
      ) do
    {:halt,
     update_state(
       socket,
       &remove_course(&1, parse_index(semester_index), parse_index(course_index))
     )}
  end

  def hooked_event("academic-programs-editor:save", _params, socket) do
    state = state(socket)

    case ProgramAttrs.parse(state.editor) do
      {:ok, program} ->
        updated_state = %{
          state
          | pending_action: if(state.editing_id, do: :update, else: :create),
            error: nil
        }

        if updated_state.editing_id do
          ProgramDomainManager.update_program(
            pid: self(),
            id: updated_state.editing_id,
            program: program
          )
        else
          ProgramDomainManager.create_program(pid: self(), program: program)
        end

        {:halt, assign(socket, state_key(socket), updated_state)}

      {:error, reason} ->
        {:halt,
         assign(socket, state_key(socket), %{state | pending_action: nil, error: inspect(reason)})}
    end
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  defp state(socket), do: socket.assigns[state_key(socket)]
  defp state_key(_socket), do: :academic_program_editor

  defp update_state(socket, updater),
    do: assign(socket, state_key(socket), updater.(state(socket)))

  defp add_semester(state) do
    semesters =
      Map.get(state.editor, "semesters", []) ++
        [%{"courses" => [%{"subject_code" => "", "course_number" => ""}]}]

    %{state | editor: Map.put(state.editor, "semesters", semesters)}
  end

  defp remove_semester(state, index) do
    semesters = state.editor |> Map.get("semesters", []) |> List.delete_at(index)
    %{state | editor: Map.put(state.editor, "semesters", semesters)}
  end

  defp add_course(state, semester_index) do
    semesters =
      state.editor
      |> Map.get("semesters", [])
      |> List.update_at(semester_index, fn semester ->
        update_in(semester["courses"], &(&1 ++ [%{"subject_code" => "", "course_number" => ""}]))
      end)

    %{state | editor: Map.put(state.editor, "semesters", semesters)}
  end

  defp remove_course(state, semester_index, course_index) do
    semesters =
      state.editor
      |> Map.get("semesters", [])
      |> List.update_at(semester_index, fn semester ->
        update_in(semester["courses"], &List.delete_at(&1, course_index))
      end)

    %{state | editor: Map.put(state.editor, "semesters", semesters)}
  end

  defp blank_program do
    %{
      "name" => "",
      "semesters" => [
        %{"courses" => [%{"subject_code" => "", "course_number" => ""}]}
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

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} -> index
      _ -> 0
    end
  end

  defp parse_index(value) when is_integer(value), do: value
  defp parse_index(_value), do: 0

  defp semester_label(index) when index == 0, do: "Freshman first semester"
  defp semester_label(index) when index == 1, do: "Freshman second semester"
  defp semester_label(index) when index == 2, do: "Sophomore first semester"
  defp semester_label(index) when index == 3, do: "Sophomore second semester"
  defp semester_label(index) when index == 4, do: "Junior first semester"
  defp semester_label(index) when index == 5, do: "Junior second semester"
  defp semester_label(index) when index == 6, do: "Senior first semester"
  defp semester_label(index) when index == 7, do: "Senior second semester"
  defp semester_label(index), do: "Year #{div(index, 2) + 1} semester #{rem(index, 2) + 1}"
end
