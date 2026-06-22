defmodule SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramEditor do
  use SnowSeToolsWeb, :html

  alias Phoenix.LiveView
  alias SnowSeTools.AcademicPrograms.{ProgramAttrs, ProgramDomainManager}
  alias SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker
  alias SnowSeToolsWeb.Scheduling.AcademicProgramCourseSearch

  defstruct [
    :key,
    :editing_id,
    :editor,
    :pending_action,
    :error,
    :course_focus_request,
    :course_focus_token,
    :picker_open,
    :picker_active_indexes
  ]

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
          error: nil,
          course_focus_request: nil,
          course_focus_token: 0,
          picker_open: %{},
          picker_active_indexes: %{}
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
                      semester_index={semester_index}
                      course_index={course_index}
                      course_value={picker_course_value(@state, semester_index, course_index)}
                      suggestions={picker_suggestions(@state, @courses, semester_index, course_index)}
                      matched_course_label={
                        picker_matched_course_label(@state, @courses, semester_index, course_index)
                      }
                      focus_token={
                        course_focus_token(@state.course_focus_request, semester_index, course_index)
                      }
                      open?={picker_open?(@state, semester_index, course_index)}
                      active_suggestion_index={
                        picker_active_index(@state, semester_index, course_index)
                      }
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
        error: nil,
        course_focus_request: nil,
        picker_open: %{},
        picker_active_indexes: %{}
    }
  end

  def reset(state) do
    %__MODULE__{} = state

    %{
      state
      | editing_id: nil,
        editor: blank_program(),
        pending_action: nil,
        error: nil,
        course_focus_request: nil,
        course_focus_token: state.course_focus_token,
        picker_open: %{},
        picker_active_indexes: %{}
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

  def hooked_event("academic-programs-editor:update", params, socket) when is_map(params) do
    {:halt, update_state(socket, &%{&1 | editor: update_form_editor(&1.editor, params)})}
  end

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

  def hooked_event(
        "academic-programs-picker:update",
        %{"semester_index" => semester_index, "course_index" => course_index, "value" => value},
        socket
      ) do
    {:halt,
     update_state(
       socket,
       &picker_update(&1, parse_index(semester_index), parse_index(course_index), value)
     )}
  end

  def hooked_event(
        "academic-programs-picker:update",
        %{"_target" => ["course", semester_index, course_index]} = params,
        socket
      ) do
    value =
      params
      |> Map.get("course", %{})
      |> Map.get(semester_index, %{})
      |> Map.get(course_index, "")

    {:halt,
     update_state(
       socket,
       &picker_update(&1, parse_index(semester_index), parse_index(course_index), value)
     )}
  end

  def hooked_event(
        "academic-programs-picker:update",
        %{"course" => course_params, "value" => value},
        socket
      )
      when is_map(course_params) do
    {semester_index, course_index} = first_course_param_indexes(course_params)

    {:halt, update_state(socket, &picker_update(&1, semester_index, course_index, value))}
  end

  def hooked_event(
        "academic-programs-picker:focus",
        %{"semester_index" => semester_index, "course_index" => course_index},
        socket
      ) do
    {:halt,
     update_state(
       socket,
       &picker_focus(&1, parse_index(semester_index), parse_index(course_index))
     )}
  end

  def hooked_event(
        "academic-programs-picker:blur",
        %{"semester_index" => semester_index, "course_index" => course_index},
        socket
      ) do
    {:halt,
     update_state(
       socket,
       &picker_blur(&1, parse_index(semester_index), parse_index(course_index))
     )}
  end

  def hooked_event(
        "academic-programs-picker:keydown",
        %{"semester_index" => semester_index, "course_index" => course_index, "key" => key},
        socket
      ) do
    {:halt,
     update_state(
       socket,
       &picker_keydown(
         &1,
         socket.assigns.courses,
         parse_index(semester_index),
         parse_index(course_index),
         key
       )
     )}
  end

  def hooked_event(
        "academic-programs-picker:select",
        %{
          "semester_index" => semester_index,
          "course_index" => course_index,
          "selected" => value
        },
        socket
      ) do
    {:halt,
     update_state(
       socket,
       &select_course(&1, parse_index(semester_index), parse_index(course_index), value)
     )}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  defp state(socket), do: socket.assigns[state_key(socket)]
  defp state_key(_socket), do: :academic_program_editor

  defp update_state(socket, updater),
    do: assign(socket, state_key(socket), updater.(state(socket)))

  defp picker_update(state, semester_index, course_index, course_value) do
    state
    |> update_course(semester_index, course_index, course_value)
    |> put_picker_active_index(semester_index, course_index, -1)
    |> put_picker_open(semester_index, course_index, String.trim(course_value) != "")
  end

  defp picker_focus(state, semester_index, course_index),
    do: put_picker_open(state, semester_index, course_index, true)

  defp picker_blur(state, semester_index, course_index),
    do: put_picker_open(state, semester_index, course_index, false)

  defp picker_keydown(state, courses, semester_index, course_index, key) do
    suggestions = picker_suggestions(state, courses, semester_index, course_index)
    active_index = picker_active_index(state, semester_index, course_index)

    case key do
      "ArrowDown" ->
        next_index =
          if suggestions == [], do: -1, else: min(active_index + 1, length(suggestions) - 1)

        state
        |> put_picker_open(semester_index, course_index, true)
        |> put_picker_active_index(semester_index, course_index, next_index)

      "ArrowUp" ->
        next_index = if suggestions == [], do: -1, else: max(active_index - 1, 0)

        state
        |> put_picker_open(semester_index, course_index, true)
        |> put_picker_active_index(semester_index, course_index, next_index)

      "Enter" ->
        case Enum.at(suggestions, max(active_index, 0)) do
          nil -> state
          suggestion -> select_course(state, semester_index, course_index, suggestion.value)
        end

      "Escape" ->
        state
        |> put_picker_open(semester_index, course_index, false)
        |> put_picker_active_index(semester_index, course_index, -1)

      _ ->
        state
    end
  end

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

  defp update_course(state, semester_index, course_index, course_value) do
    {subject_code, course_number} = AcademicProgramCourseSearch.parse_course_input(course_value)

    semesters =
      state.editor
      |> Map.get("semesters", [])
      |> List.update_at(semester_index, fn semester ->
        update_in(semester["courses"], fn courses ->
          List.update_at(courses, course_index, fn course ->
            course
            |> Map.put("subject_code", subject_code)
            |> Map.put("course_number", course_number)
          end)
        end)
      end)

    %{state | editor: Map.put(state.editor, "semesters", semesters)}
  end

  defp select_course(state, semester_index, course_index, value) do
    updated_state = update_course(state, semester_index, course_index, value)
    semesters = Map.get(updated_state.editor, "semesters", [])
    courses = semesters |> Enum.at(semester_index, %{}) |> Map.get("courses", [])

    next_state =
      if course_index == length(courses) - 1,
        do: add_course(updated_state, semester_index),
        else: updated_state

    token = next_state.course_focus_token + 1

    %{
      next_state
      | course_focus_token: token,
        course_focus_request: %{
          semester_index: semester_index,
          course_index: course_index + 1,
          token: token
        },
        picker_open:
          Map.put(next_state.picker_open, picker_key(semester_index, course_index), false),
        picker_active_indexes:
          Map.put(next_state.picker_active_indexes, picker_key(semester_index, course_index), -1)
    }
  end

  defp picker_course_value(state, semester_index, course_index) do
    state.editor
    |> Map.get("semesters", [])
    |> Enum.at(semester_index, %{})
    |> Map.get("courses", [])
    |> Enum.at(course_index, %{})
    |> AcademicProgramCourseSearch.course_input_value()
  end

  defp picker_suggestions(state, courses, semester_index, course_index) do
    AcademicProgramCourseSearch.course_suggestions(
      courses,
      picker_course_value(state, semester_index, course_index)
    )
  end

  defp picker_matched_course_label(state, courses, semester_index, course_index) do
    course_value = picker_course_value(state, semester_index, course_index)

    if course_value != "" do
      Enum.find_value(courses, fn course ->
        case AcademicProgramCourseSearch.course_input_value(course) do
          ^course_value -> Map.get(course, "name", "")
          _ -> nil
        end
      end)
    end
  end

  defp picker_active_index(state, semester_index, course_index) do
    Map.get(state.picker_active_indexes, picker_key(semester_index, course_index), -1)
  end

  defp picker_open?(state, semester_index, course_index) do
    Map.get(state.picker_open, picker_key(semester_index, course_index), false)
  end

  defp course_focus_token(course_focus_request, semester_index, course_index) do
    case course_focus_request do
      %{semester_index: ^semester_index, course_index: ^course_index, token: token} -> token
      _ -> nil
    end
  end

  defp put_picker_open(state, semester_index, course_index, open?) do
    %{
      state
      | picker_open: Map.put(state.picker_open, picker_key(semester_index, course_index), open?)
    }
  end

  defp put_picker_active_index(state, semester_index, course_index, index) do
    %{
      state
      | picker_active_indexes:
          Map.put(state.picker_active_indexes, picker_key(semester_index, course_index), index)
    }
  end

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} -> index
      _ -> 0
    end
  end

  defp parse_index(value) when is_integer(value), do: value
  defp parse_index(_value), do: 0

  defp first_course_param_indexes(course_params) do
    case Enum.at(course_params, 0) do
      {semester_index, nested_courses} when is_map(nested_courses) ->
        case Enum.at(nested_courses, 0) do
          {course_index, _value} -> {parse_index(semester_index), parse_index(course_index)}
          _ -> {0, 0}
        end

      _ ->
        {0, 0}
    end
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

  defp update_form_editor(editor, params) do
    editor
    |> maybe_update_name(params)
    |> update_courses_from_form(params)
  end

  defp maybe_update_name(editor, %{"name" => name}), do: Map.put(editor, "name", name)
  defp maybe_update_name(editor, _params), do: editor

  defp update_courses_from_form(editor, %{"course" => course_params})
       when is_map(course_params) do
    Enum.reduce(course_params, editor, fn {semester_index, courses}, current_editor ->
      Enum.reduce(courses || %{}, current_editor, fn {course_index, course_value},
                                                     nested_editor ->
        temp_state = %__MODULE__{
          key: :temp,
          editor: nested_editor,
          picker_open: %{},
          picker_active_indexes: %{}
        }

        update_course(
          temp_state,
          parse_index(semester_index),
          parse_index(course_index),
          course_value
        ).editor
      end)
    end)
  end

  defp update_courses_from_form(editor, _params), do: editor

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
  defp semester_label(index) when index == 0, do: "Freshman first semester"
  defp semester_label(index) when index == 1, do: "Freshman second semester"
  defp semester_label(index) when index == 2, do: "Sophomore first semester"
  defp semester_label(index) when index == 3, do: "Sophomore second semester"
  defp semester_label(index) when index == 4, do: "Junior first semester"
  defp semester_label(index) when index == 5, do: "Junior second semester"
  defp semester_label(index) when index == 6, do: "Senior first semester"
  defp semester_label(index) when index == 7, do: "Senior second semester"
  defp semester_label(index), do: "Year #{div(index, 2) + 1} semester #{rem(index, 2) + 1}"
  defp picker_key(semester_index, course_index), do: {semester_index, course_index}
end
