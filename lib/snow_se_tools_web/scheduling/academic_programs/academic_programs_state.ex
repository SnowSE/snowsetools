defmodule SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramsState do
  @moduledoc false

  alias SnowSeToolsWeb.Scheduling.AcademicProgramCourseSearch

  def new_editor_state do
    %{
      editing_id: nil,
      editor: blank_program(),
      pending_action: nil,
      error: nil,
      course_focus_request: nil,
      course_focus_token: 0,
      picker_open: %{},
      picker_active_indexes: %{}
    }
  end

  def load_program(editor_state, program) do
    %{
      editor_state
      | editing_id: program["id"],
        editor: editor_from_program(program),
        pending_action: nil,
        error: nil,
        course_focus_request: nil,
        picker_open: %{},
        picker_active_indexes: %{}
    }
  end

  def update_editor_from_form(editor_state, params) do
    %{editor_state | editor: update_form_editor(editor_state.editor, params)}
  end

  def picker_update(editor_state, semester_index, course_index, course_value) do
    editor_state
    |> update_course(semester_index, course_index, course_value)
    |> put_picker_active_index(semester_index, course_index, -1)
    |> put_picker_open(semester_index, course_index, String.trim(course_value) != "")
  end

  def picker_focus(editor_state, semester_index, course_index) do
    put_picker_open(editor_state, semester_index, course_index, true)
  end

  def picker_blur(editor_state, semester_index, course_index) do
    put_picker_open(editor_state, semester_index, course_index, false)
  end

  def picker_keydown(editor_state, courses, semester_index, course_index, key) do
    suggestions = picker_suggestions(editor_state, courses, semester_index, course_index)
    active_index = picker_active_index(editor_state, semester_index, course_index)

    case key do
      "ArrowDown" ->
        next_index =
          if suggestions == [] do
            -1
          else
            min(active_index + 1, length(suggestions) - 1)
          end

        editor_state
        |> put_picker_open(semester_index, course_index, true)
        |> put_picker_active_index(semester_index, course_index, next_index)

      "ArrowUp" ->
        next_index =
          if suggestions == [] do
            -1
          else
            max(active_index - 1, 0)
          end

        editor_state
        |> put_picker_open(semester_index, course_index, true)
        |> put_picker_active_index(semester_index, course_index, next_index)

      "Enter" ->
        case Enum.at(suggestions, max(active_index, 0)) do
          nil ->
            editor_state

          suggestion ->
            select_course(editor_state, semester_index, course_index, suggestion.value)
        end

      "Escape" ->
        editor_state
        |> put_picker_open(semester_index, course_index, false)
        |> put_picker_active_index(semester_index, course_index, -1)

      _ ->
        editor_state
    end
  end

  def add_semester(editor_state) do
    semesters =
      Map.get(editor_state.editor, "semesters", []) ++
        [%{"courses" => [%{"subject_code" => "", "course_number" => ""}]}]

    %{editor_state | editor: Map.put(editor_state.editor, "semesters", semesters)}
  end

  def remove_semester(editor_state, index) do
    semesters =
      editor_state.editor
      |> Map.get("semesters", [])
      |> List.delete_at(index)

    %{editor_state | editor: Map.put(editor_state.editor, "semesters", semesters)}
  end

  def add_course(editor_state, semester_index) do
    semesters =
      editor_state.editor
      |> Map.get("semesters", [])
      |> List.update_at(semester_index, fn semester ->
        update_in(semester["courses"], &(&1 ++ [%{"subject_code" => "", "course_number" => ""}]))
      end)

    %{editor_state | editor: Map.put(editor_state.editor, "semesters", semesters)}
  end

  def remove_course(editor_state, semester_index, course_index) do
    semesters =
      editor_state.editor
      |> Map.get("semesters", [])
      |> List.update_at(semester_index, fn semester ->
        update_in(semester["courses"], &List.delete_at(&1, course_index))
      end)

    %{editor_state | editor: Map.put(editor_state.editor, "semesters", semesters)}
  end

  def update_course(editor_state, semester_index, course_index, course_value) do
    {subject_code, course_number} = AcademicProgramCourseSearch.parse_course_input(course_value)

    semesters =
      editor_state.editor
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

    %{editor_state | editor: Map.put(editor_state.editor, "semesters", semesters)}
  end

  def select_course(editor_state, semester_index, course_index, value) do
    updated_state = update_course(editor_state, semester_index, course_index, value)
    semesters = Map.get(updated_state.editor, "semesters", [])
    courses = semesters |> Enum.at(semester_index, %{}) |> Map.get("courses", [])

    next_state =
      if course_index == length(courses) - 1 do
        add_course(updated_state, semester_index)
      else
        updated_state
      end

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

  def start_save(editor_state) do
    %{
      editor_state
      | pending_action: if(editor_state.editing_id, do: :update, else: :create),
        error: nil
    }
  end

  def start_delete(editor_state) do
    %{editor_state | pending_action: :delete, error: nil}
  end

  def apply_action_result(editor_state, {:ok, _message, _program}) do
    cleared_error = %{editor_state | error: nil}

    case cleared_error.pending_action do
      :create ->
        %{new_editor_state() | course_focus_token: cleared_error.course_focus_token}

      :delete ->
        %{new_editor_state() | course_focus_token: cleared_error.course_focus_token}

      _ ->
        %{cleared_error | pending_action: nil}
    end
  end

  def apply_action_result(editor_state, {:error, reason}) do
    %{editor_state | pending_action: nil, error: format_error(reason)}
  end

  def reset_editor(editor_state) do
    %{new_editor_state() | course_focus_token: editor_state.course_focus_token}
  end

  def parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} -> index
      _ -> 0
    end
  end

  def parse_index(value) when is_integer(value), do: value
  def parse_index(_value), do: 0

  def course_focus_token(course_focus_request, semester_index, course_index) do
    case course_focus_request do
      %{semester_index: ^semester_index, course_index: ^course_index, token: token} -> token
      _ -> nil
    end
  end

  def picker_course_value(editor_state, semester_index, course_index) do
    editor_state.editor
    |> Map.get("semesters", [])
    |> Enum.at(semester_index, %{})
    |> Map.get("courses", [])
    |> Enum.at(course_index, %{})
    |> AcademicProgramCourseSearch.course_input_value()
  end

  def picker_suggestions(editor_state, courses, semester_index, course_index) do
    course_value = picker_course_value(editor_state, semester_index, course_index)

    AcademicProgramCourseSearch.course_suggestions(courses, course_value)
  end

  def picker_matched_course_label(editor_state, courses, semester_index, course_index) do
    course_value = picker_course_value(editor_state, semester_index, course_index)

    if course_value != "" do
      Enum.find_value(courses, fn course ->
        case AcademicProgramCourseSearch.course_input_value(course) do
          ^course_value -> Map.get(course, "name", "")
          _ -> nil
        end
      end)
    end
  end

  def picker_active_index(editor_state, semester_index, course_index) do
    Map.get(editor_state.picker_active_indexes, picker_key(semester_index, course_index), -1)
  end

  def picker_open?(editor_state, semester_index, course_index) do
    Map.get(editor_state.picker_open, picker_key(semester_index, course_index), false)
  end

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
        temp_state = %{new_editor_state() | editor: nested_editor}

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

  defp put_picker_open(editor_state, semester_index, course_index, open?) do
    %{
      editor_state
      | picker_open:
          Map.put(editor_state.picker_open, picker_key(semester_index, course_index), open?)
    }
  end

  defp put_picker_active_index(editor_state, semester_index, course_index, index) do
    %{
      editor_state
      | picker_active_indexes:
          Map.put(
            editor_state.picker_active_indexes,
            picker_key(semester_index, course_index),
            index
          )
    }
  end

  defp picker_key(semester_index, course_index), do: {semester_index, course_index}
end
