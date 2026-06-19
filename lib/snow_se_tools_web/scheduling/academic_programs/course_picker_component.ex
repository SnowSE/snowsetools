defmodule SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker do
  use SnowSeToolsWeb, :live_component

  alias SnowSeToolsWeb.Scheduling.AcademicProgramCourseSearch
  alias SnowSeToolsWeb.Scheduling.AcademicProgramEditorComponent

  attr :semester_index, :integer, required: true
  attr :course_index, :integer, required: true
  attr :course, :map, required: true
  attr :courses, :list, required: true
  attr :focus_token, :integer, default: nil

  def mount(socket) do
    {:ok, assign(socket, active_suggestion_index: -1, focused: false)}
  end

  def update(assigns, socket) do
    course_value = AcademicProgramCourseSearch.course_input_value(assigns.course)
    suggestions = AcademicProgramCourseSearch.course_suggestions(assigns.courses, course_value)

    socket =
      socket
      |> assign(:semester_index, assigns.semester_index)
      |> assign(:course_index, assigns.course_index)
      |> assign(:course, assigns.course)
      |> assign(:courses, assigns.courses)
      |> assign(:course_value, course_value)
      |> assign(:suggestions, suggestions)
      |> assign(:focus_token, assigns.focus_token)

    {:ok,
     assign_new(socket, :active_suggestion_index, fn -> -1 end)
     |> assign_new(:focused, fn -> false end)}
  end

  def handle_event("value_updated", %{"value" => value}, socket) do
    semester_index = socket.assigns.semester_index
    course_index = socket.assigns.course_index

    send_update(AcademicProgramEditorComponent,
      id: "academic-program-editor",
      update_course: {semester_index, course_index, value}
    )

    {:noreply,
     socket
     |> assign(:course_value, value)
     |> assign(
       :suggestions,
       AcademicProgramCourseSearch.course_suggestions(socket.assigns.courses, value)
     )
     |> assign(:active_suggestion_index, -1)}
  end

  def handle_event("value_updated", %{"course" => course_data}, socket) do
    semester_index = socket.assigns.semester_index
    course_index = socket.assigns.course_index

    value =
      course_data
      |> Map.get(to_string(semester_index), %{})
      |> Map.get(to_string(course_index), "")

    send_update(AcademicProgramEditorComponent,
      id: "academic-program-editor",
      update_course: {semester_index, course_index, value}
    )

    {:noreply,
     socket
     |> assign(:course_value, value)
     |> assign(
       :suggestions,
       AcademicProgramCourseSearch.course_suggestions(socket.assigns.courses, value)
     )
     |> assign(:active_suggestion_index, -1)}
  end

  def handle_event("select_suggestion", %{"value" => value}, socket) do
    semester_index = socket.assigns.semester_index
    course_index = socket.assigns.course_index

    send_update(AcademicProgramEditorComponent,
      id: "academic-program-editor",
      select_course: {semester_index, course_index, value}
    )

    {:noreply,
     socket
     |> assign(:course_value, value)
     |> assign(:suggestions, [])
     |> assign(:active_suggestion_index, -1)}
  end

  def handle_event("focus", _params, socket) do
    {:noreply, assign(socket, :focused, true)}
  end

  def handle_event("blur", _params, socket) do
    {:noreply, assign(socket, :focused, false)}
  end

  def handle_event("keydown", %{"key" => key}, socket) do
    suggestions = socket.assigns.suggestions
    active_index = socket.assigns.active_suggestion_index

    case key do
      "ArrowDown" ->
        next_index =
          if suggestions == [] do
            -1
          else
            min(active_index + 1, length(suggestions) - 1)
          end

        {:noreply, assign(socket, :active_suggestion_index, next_index)}

      "ArrowUp" ->
        next_index =
          if suggestions == [] do
            -1
          else
            max(active_index - 1, 0)
          end

        {:noreply, assign(socket, :active_suggestion_index, next_index)}

      "Enter" ->
        semester_index = socket.assigns.semester_index
        course_index = socket.assigns.course_index

        case Enum.at(suggestions, max(active_index, 0)) do
          nil ->
            {:noreply, socket}

          suggestion ->
            send_update(AcademicProgramEditorComponent,
              id: "academic-program-editor",
              select_course: {semester_index, course_index, suggestion.value}
            )

            {:noreply,
             socket
             |> assign(:course_value, suggestion.value)
             |> assign(:suggestions, [])
             |> assign(:active_suggestion_index, -1)}
        end

      "Escape" ->
        {:noreply, assign(socket, :active_suggestion_index, -1)}

      _ ->
        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="relative min-w-0">
      <input
        id={"program-course-input-#{@semester_index}-#{@course_index}"}
        name={"course[#{@semester_index}][#{@course_index}]"}
        value={@course_value}
        placeholder="MATH 1010"
        autocomplete="off"
        phx-hook=".CourseSuggestionInput"
        data-semester-index={@semester_index}
        data-course-index={@course_index}
        data-autofocus-token={@focus_token}
        phx-keydown="keydown"
        phx-change="value_updated"
        phx-focus="focus"
        phx-blur="blur"
        phx-target={@myself}
        class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-2 py-1.5 text-sm uppercase text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
      />

      <div
        :if={@focused and @course_value != "" and @suggestions != []}
        id={"program-course-suggestions-#{@semester_index}-#{@course_index}"}
        class="absolute left-0 right-0 top-full z-20 mt-1 max-h-56 overflow-y-auto overflow-hidden rounded-md border border-slate-700 bg-slate-950 shadow-xl"
      >
        <%= for {suggestion, suggestion_index} <- Enum.with_index(@suggestions) do %>
          <button
            id={"program-course-suggestion-#{@semester_index}-#{@course_index}-#{suggestion_index}"}
            type="button"
            phx-hook=".CourseSuggestionOption"
            phx-mousedown="select_suggestion"
            phx-target={@myself}
            phx-value-value={suggestion.value}
            class={[
              "flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm transition hover:bg-slate-900",
              @active_suggestion_index == suggestion_index && "bg-slate-900"
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
            });
          },
        };
      </script>
    </div>
    """
  end
end
