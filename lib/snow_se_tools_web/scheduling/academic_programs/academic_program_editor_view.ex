defmodule SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramEditorView do
  use SnowSeToolsWeb, :html

  alias SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker
  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramsState

  attr :courses, :list, required: true
  attr :editor_state, :map, required: true

  def render(assigns) do
    ~H"""
    <section class="min-h-0 overflow-y-auto rounded-lg border border-slate-800 bg-slate-950/45 p-4">
      <div class="mb-4">
        <h2 class="text-base font-semibold text-slate-100">
          {if @editor_state.editing_id, do: "Edit Program", else: "New Program"}
        </h2>
      </div>

      <div
        :if={@editor_state.error}
        id="academic-program-editor-error"
        class="mb-4 rounded-lg border border-red-900/60 bg-red-950/40 px-3 py-2 text-sm text-red-200"
      >
        {@editor_state.error}
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
          value={@editor_state.editor["name"]}
          placeholder="Civil Engineering"
          class="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-600 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        />

        <div class="mt-5 space-3 grid grid-cols-2 gap-3">
          <div
            :if={@editor_state.editor["semesters"] == []}
            class="rounded-lg border border-dashed border-slate-800 p-6 text-center text-sm text-slate-500"
          >
            Add a semester, then add required courses.
          </div>

          <%= for {semester, semester_index} <- Enum.with_index(@editor_state.editor["semesters"]) do %>
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
                <%= for {course, course_index} <- Enum.with_index(semester["courses"]) do %>
                  <div class="grid grid-cols-[1fr_auto] gap-2">
                    <AcademicProgramCoursePicker.render
                      semester_index={semester_index}
                      course_index={course_index}
                      course_value={
                        AcademicProgramsState.picker_course_value(
                          @editor_state,
                          semester_index,
                          course_index
                        )
                      }
                      suggestions={
                        AcademicProgramsState.picker_suggestions(
                          @editor_state,
                          @courses,
                          semester_index,
                          course_index
                        )
                      }
                      matched_course_label={
                        AcademicProgramsState.picker_matched_course_label(
                          @editor_state,
                          @courses,
                          semester_index,
                          course_index
                        )
                      }
                      focus_token={
                        AcademicProgramsState.course_focus_token(
                          @editor_state.course_focus_request,
                          semester_index,
                          course_index
                        )
                      }
                      open?={
                        AcademicProgramsState.picker_open?(
                          @editor_state,
                          semester_index,
                          course_index
                        )
                      }
                      active_suggestion_index={
                        AcademicProgramsState.picker_active_index(
                          @editor_state,
                          semester_index,
                          course_index
                        )
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
                    " px-2 py-1.5 text-slate-400 transition hover:bg-slate-800 hover:text-slate-200"
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
              "inline-flex items-center justify-center gap-1 rounded-md border border-dashed border-slate-700 ",
              "p-3 font-medium text-slate-300 ",
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
            :if={@editor_state.editing_id}
            type="button"
            phx-click="academic-programs:cancel-edit"
            class="inline-flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium text-slate-400 transition hover:bg-slate-800 hover:text-slate-200"
          >
            <.icon name="hero-x-mark" class="size-4" /> Cancel
          </button>

          <div :if={!@editor_state.editing_id} />

          <button
            id="save-academic-program"
            type="button"
            phx-click="academic-programs-editor:save"
            disabled={String.trim(@editor_state.editor["name"]) == ""}
            class={[
              "inline-flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition",
              if(String.trim(@editor_state.editor["name"]) == "",
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
