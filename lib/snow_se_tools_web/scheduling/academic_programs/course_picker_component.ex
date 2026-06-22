defmodule SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker do
  use SnowSeToolsWeb, :html

  attr :semester_index, :integer, required: true
  attr :course_index, :integer, required: true
  attr :course_value, :string, required: true
  attr :suggestions, :list, required: true
  attr :matched_course_label, :string, default: nil
  attr :focus_token, :integer, default: nil
  attr :open?, :boolean, default: false
  attr :active_suggestion_index, :integer, default: -1

  def render(assigns) do
    ~H"""
    <div class="relative min-w-0">
      <label>
        <span class="flex justify-between">
          <span class="text-sm text-slate-400">
            Course
          </span>
          <span
            :if={@matched_course_label != nil}
            class="text-sm text-indigo-200/70"
          >
            {@matched_course_label}
          </span>
        </span>
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
        :if={@open? and @course_value != "" and @suggestions != []}
        id={"program-course-suggestions-#{@semester_index}-#{@course_index}"}
        class="absolute left-0 right-0 top-full z-20 mt-1 max-h-56 overflow-y-auto overflow-hidden rounded-md border border-slate-700 bg-slate-950 shadow-xl"
      >
        <%= for {suggestion, suggestion_index} <- Enum.with_index(@suggestions) do %>
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
end
