defmodule SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker do
  use SnowSeToolsWeb, :html

  import Phoenix.LiveView
  require Logger

  alias SnowSeToolsWeb.Scheduling.AcademicProgramCourseSearch

  defstruct [
    :key,
    :editor_key,
    :editor,
    :course_catalog,
    :course_label_by_value,
    :course_focus_request,
    :course_focus_token,
    :picker_open,
    :picker_active_indexes
  ]

  def assign_component(socket, key, opts \\ []) do
    courses = opts[:courses] || []

    socket
    |> assign(
      key,
      socket.assigns[key] ||
        %__MODULE__{
          key: key,
          editor_key: opts[:editor_key] || :academic_program_editor,
          editor: nil,
          course_catalog: build_course_catalog(courses),
          course_label_by_value: build_course_label_map(courses),
          course_focus_request: nil,
          course_focus_token: 0,
          picker_open: %{},
          picker_active_indexes: %{}
        }
    )
    |> maybe_attach_hooks()
  end

  def reset(state) do
    %__MODULE__{} = state

    %{
      state
      | course_focus_request: nil,
        picker_open: %{},
        picker_active_indexes: %{}
    }
  end

  def render_assigns(state, editor_state, semester_index, course_index) do
    %{
      course_value: picker_course_value(editor_state, semester_index, course_index),
      suggestions: picker_suggestions(state, editor_state, semester_index, course_index),
      matched_course_label:
        picker_matched_course_label(state, editor_state, semester_index, course_index),
      focus_token: course_focus_token(state.course_focus_request, semester_index, course_index),
      open?: picker_open?(state, semester_index, course_index),
      active_suggestion_index: picker_active_index(state, semester_index, course_index)
    }
  end

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :render_state,
        render_assigns(
          assigns.state,
          assigns.editor,
          assigns.semester_index,
          assigns.course_index
        )
      )

    ~H"""
    <div class="relative min-w-0">
      <label>
        <span class="flex justify-between">
          <span class="text-sm text-slate-400">
            Course
          </span>
          <span
            :if={@render_state.matched_course_label != nil}
            id={"program-course-matched-label-#{@semester_index}-#{@course_index}"}
            class="text-sm text-indigo-200/70"
          >
            {@render_state.matched_course_label}
          </span>
        </span>
        <input
          id={"program-course-input-#{@semester_index}-#{@course_index}"}
          name={"course[#{@semester_index}][#{@course_index}]"}
          value={@render_state.course_value}
          placeholder="MATH 1010"
          autocomplete="off"
          phx-hook=".CourseSuggestionInput"
          data-semester-index={@semester_index}
          data-course-index={@course_index}
          data-autofocus-token={@render_state.focus_token}
          phx-keydown="academic-programs-picker:keydown"
          phx-change="academic-programs-picker:update"
          phx-focus="academic-programs-picker:focus"
          phx-blur="academic-programs-picker:blur"
          phx-value-semester_index={@semester_index}
          phx-value-course_index={@course_index}
          class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-2 py-1.5 text-sm uppercase text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        />
      </label>

      <div
        :if={
          @render_state.open? and @render_state.course_value != "" and @render_state.suggestions != []
        }
        id={"program-course-suggestions-#{@semester_index}-#{@course_index}"}
        class="absolute left-0 right-0 top-full z-20 mt-1 max-h-56 overflow-y-auto overflow-hidden rounded-md border border-slate-700 bg-slate-950 shadow-xl"
      >
        <%= for {suggestion, suggestion_index} <- Enum.with_index(@render_state.suggestions) do %>
          <button
            id={"program-course-suggestion-#{@semester_index}-#{@course_index}-#{suggestion_index}"}
            type="button"
            phx-hook=".CourseSuggestionOption"
            phx-click="academic-programs-picker:select"
            phx-value-semester_index={@semester_index}
            phx-value-course_index={@course_index}
            phx-value-selected={suggestion.value}
            class={[
              "flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm transition hover:bg-slate-900",
              @render_state.active_suggestion_index == suggestion_index && "bg-slate-900"
            ]}
          >
            <span class="min-w-0 truncate font-medium text-slate-100">
              {suggestion.value}
            </span>
            <span class="min-w-0 truncate text-xs text-slate-500">
              {suggestion.label}
            </span>
          </button>
        <% end %>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CourseSuggestionInput">
        export default {
          mounted() {
            this.focusWhenRequested();

            this.el.addEventListener("keydown", (event) => {
              if (["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
                event.preventDefault();
              }
            });
          },

          updated() {
            this.focusWhenRequested();
          },

          focusWhenRequested() {
            const token = this.el.dataset.autofocusToken;

            if (!token || token === this.lastAutofocusToken) {
              return;
            }

            this.lastAutofocusToken = token;

            requestAnimationFrame(() => {
              this.el.focus();
              this.el.select();
            });
          },
        };
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CourseSuggestionOption">
        export default {
          mounted() {
            this.el.addEventListener("mousedown", (event) => {
              event.preventDefault();
              const input = this.el.closest(".relative").querySelector("input");
              if (input) {
                input.value = this.el.dataset.phxValueSelected;
              }
            });
          },
        };
      </script>
    </div>
    """
  end

  def hooked_event(
        "academic-programs-picker:update",
        %{"semester_index" => semester_index, "course_index" => course_index, "value" => value},
        socket
      ) do
    semester_index = parse_index(semester_index)
    course_index = parse_index(course_index)

    {:halt,
     update_socket(socket, fn state, editor ->
       {picker_update(state, semester_index, course_index, value),
        update_course(editor, semester_index, course_index, value)}
     end)}
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

    semester_index = parse_index(semester_index)
    course_index = parse_index(course_index)

    {:halt,
     update_socket(socket, fn state, editor ->
       {picker_update(state, semester_index, course_index, value),
        update_course(editor, semester_index, course_index, value)}
     end)}
  end

  def hooked_event(
        "academic-programs-picker:update",
        %{"course" => course_params, "value" => value},
        socket
      )
      when is_map(course_params) do
    {semester_index, course_index} = first_course_param_indexes(course_params)

    {:halt,
     update_socket(socket, fn state, editor ->
       {picker_update(state, semester_index, course_index, value),
        update_course(editor, semester_index, course_index, value)}
     end)}
  end

  def hooked_event(
        "academic-programs-picker:focus",
        %{"semester_index" => semester_index, "course_index" => course_index},
        socket
      ) do
    {:halt,
     update_socket(socket, fn state, editor ->
       {picker_focus(state, parse_index(semester_index), parse_index(course_index)), editor}
     end)}
  end

  def hooked_event(
        "academic-programs-picker:blur",
        %{"semester_index" => semester_index, "course_index" => course_index},
        socket
      ) do
    {:halt,
     update_socket(socket, fn state, editor ->
       {picker_blur(state, parse_index(semester_index), parse_index(course_index)), editor}
     end)}
  end

  def hooked_event(
        "academic-programs-picker:keydown",
        %{"semester_index" => semester_index, "course_index" => course_index, "key" => key},
        socket
      ) do
    semester_index = parse_index(semester_index)
    course_index = parse_index(course_index)
    state = picker_state(socket)
    editor = editor_state(socket)

    case key do
      "ArrowDown" ->
        {:halt,
         assign(
           socket,
           state_key(socket),
           state
           |> put_picker_open(semester_index, course_index, true)
           |> put_picker_active_index(
             semester_index,
             course_index,
             next_active_index(state, editor, semester_index, course_index, 1)
           )
         )}

      "ArrowUp" ->
        {:halt,
         assign(
           socket,
           state_key(socket),
           state
           |> put_picker_open(semester_index, course_index, true)
           |> put_picker_active_index(
             semester_index,
             course_index,
             next_active_index(state, editor, semester_index, course_index, -1)
           )
         )}

      "Enter" ->
        case Enum.at(
               picker_suggestions(state, editor, semester_index, course_index),
               max(picker_active_index(state, semester_index, course_index), 0)
             ) do
          nil ->
            {:halt, socket}

          suggestion ->
            {:halt,
             update_socket(socket, fn current_state, current_editor ->
               select_course(
                 current_state,
                 current_editor,
                 semester_index,
                 course_index,
                 suggestion.value
               )
             end)}
        end

      "Escape" ->
        {:halt,
         assign(
           socket,
           state_key(socket),
           state
           |> put_picker_open(semester_index, course_index, false)
           |> put_picker_active_index(semester_index, course_index, -1)
         )}

      _ ->
        {:halt, socket}
    end
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
     update_socket(socket, fn current_state, current_editor ->
       select_course(
         current_state,
         current_editor,
         parse_index(semester_index),
         parse_index(course_index),
         value
       )
     end)}
  end

  def hooked_event("academic-programs-picker:" <> rest, params, socket) do
    Logger.info(
      "Received unhandled academic-programs-picker event academic-programs-picker:#{rest} with params: #{inspect(params)}"
    )

    {:halt, socket}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  defp maybe_attach_hooks(socket) do
    if first_instance?(socket) do
      socket
      |> attach_hook("academic-programs-picker:event", :handle_event, &hooked_event/3)
    else
      socket
    end
  end

  defp first_instance?(socket) do
    Enum.count(socket.assigns, fn {_, v} -> match?(%__MODULE__{}, v) end) == 1
  end

  defp update_socket(socket, updater) do
    state = %{picker_state(socket) | editor: editor_state(socket)}
    editor = state.editor
    {updated_state, updated_editor} = updater.(state, editor)

    socket
    |> assign(state_key(socket), updated_state)
    |> assign(editor_key(updated_state), updated_editor)
  end

  defp picker_state(socket), do: socket.assigns[state_key(socket)]
  defp editor_state(socket), do: socket.assigns[editor_key(picker_state(socket))]
  defp state_key(socket), do: picker_state_key(socket.assigns)
  defp editor_key(state), do: state.editor_key

  defp picker_state_key(assigns) do
    Enum.find_value(assigns, fn
      {key, %__MODULE__{}} -> key
      _ -> nil
    end)
  end

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

  defp next_active_index(state, editor, semester_index, course_index, delta) do
    suggestions = picker_suggestions(state, editor, semester_index, course_index)
    active_index = picker_active_index(state, semester_index, course_index)

    case delta do
      1 ->
        if suggestions == [], do: -1, else: min(active_index + 1, length(suggestions) - 1)

      -1 ->
        if suggestions == [], do: -1, else: max(active_index - 1, 0)
    end
  end

  defp add_course(editor_state, semester_index) do
    semesters =
      editor_state.editor
      |> Map.get("semesters", [])
      |> List.update_at(semester_index, fn semester ->
        update_in(semester["courses"], &(&1 ++ [%{"subject_code" => "", "course_number" => ""}]))
      end)

    %{editor_state | editor: Map.put(editor_state.editor, "semesters", semesters)}
  end

  defp update_course(editor_state, semester_index, course_index, course_value) do
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

  defp select_course(state, editor_state, semester_index, course_index, value) do
    updated_editor = update_course(editor_state, semester_index, course_index, value)
    semesters = Map.get(updated_editor.editor, "semesters", [])
    courses = semesters |> Enum.at(semester_index, %{}) |> Map.get("courses", [])

    next_editor =
      if course_index == length(courses) - 1,
        do: add_course(updated_editor, semester_index),
        else: updated_editor

    token = state.course_focus_token + 1

    next_state = %{
      state
      | course_focus_token: token,
        course_focus_request: %{
          semester_index: semester_index,
          course_index: course_index + 1,
          token: token
        },
        picker_open: Map.put(state.picker_open, picker_key(semester_index, course_index), false),
        picker_active_indexes:
          Map.put(state.picker_active_indexes, picker_key(semester_index, course_index), -1)
    }

    {next_state, next_editor}
  end

  defp picker_course_value(editor_state, semester_index, course_index) do
    editor = Map.get(editor_state, :editor) || %{}

    editor
    |> Map.get("semesters", [])
    |> Enum.at(semester_index, %{})
    |> Map.get("courses", [])
    |> Enum.at(course_index, %{})
    |> AcademicProgramCourseSearch.course_input_value()
  end

  defp picker_suggestions(state, editor_state, semester_index, course_index) do
    catalog_suggestions(
      state.course_catalog || [],
      picker_course_value(editor_state, semester_index, course_index)
    )
  end

  defp picker_matched_course_label(state, editor_state, semester_index, course_index) do
    course_value = picker_course_value(editor_state, semester_index, course_index)

    if course_value != "" do
      Map.get(state.course_label_by_value || %{}, course_value)
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

  defp build_course_catalog(courses) do
    courses
    |> Enum.uniq_by(fn course ->
      {
        String.downcase(Map.get(course, "subject_code", "")),
        String.downcase(Map.get(course, "course_number", ""))
      }
    end)
    |> Enum.map(&course_option/1)
  end

  defp build_course_label_map(courses) do
    Enum.reduce(courses, %{}, fn course, acc ->
      value = AcademicProgramCourseSearch.course_input_value(course)

      if value == "" do
        acc
      else
        Map.put_new(acc, value, Map.get(course, "name", ""))
      end
    end)
  end

  defp catalog_suggestions(catalog, query, limit \\ 8) do
    normalized_query = normalize(query)

    if normalized_query == "" do
      []
    else
      catalog
      |> Enum.filter(fn option ->
        search_fields = [
          option.value_norm,
          option.label_norm,
          option.subject_code_norm,
          option.course_number_norm
        ]

        Enum.any?(search_fields, &String.contains?(&1, normalized_query))
      end)
      |> Enum.sort_by(fn option ->
        subject_match? = String.contains?(option.subject_code_norm, normalized_query)
        number_match? = String.contains?(option.course_number_norm, normalized_query)
        value_match? = String.contains?(option.value_norm, normalized_query)

        priority =
          cond do
            subject_match? -> 0
            number_match? -> 1
            value_match? -> 2
            true -> 3
          end

        {priority, String.downcase(option.value), String.downcase(option.label)}
      end)
      |> Enum.take(limit)
    end
  end

  defp course_option(course) do
    value = AcademicProgramCourseSearch.course_input_value(course)
    label = Map.get(course, "name", "")
    subject_code = Map.get(course, "subject_code", "")
    course_number = Map.get(course, "course_number", "")

    %{
      value: value,
      label: label,
      subject_code: subject_code,
      course_number: course_number,
      value_norm: normalize(value),
      label_norm: normalize(label),
      subject_code_norm: normalize(subject_code),
      course_number_norm: normalize(course_number)
    }
  end

  defp normalize(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\s+/, "")
  end

  defp normalize(_value), do: ""

  defp picker_key(semester_index, course_index), do: {semester_index, course_index}
end
