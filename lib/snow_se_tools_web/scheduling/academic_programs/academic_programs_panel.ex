defmodule SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramsPanel do
  use SnowSeToolsWeb, :html

  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramEditorView

  attr :courses, :list, required: true
  attr :programs, :list, required: true
  attr :selected_program_id, :string, default: nil
  attr :editing?, :boolean, default: false
  attr :editor_state, :map, required: true

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
            is_selected={@selected_program_id == program["id"]}
          />
        </div>
      </aside>

      <div :if={@editing?}>
        <AcademicProgramEditorView.render
          courses={@courses}
          editor_state={@editor_state}
        />
      </div>

      <.program_display :if={!@editing?} program={@selected_program} />
    </div>
    """
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

  defp selected_program(assigns) do
    Enum.find(assigns.programs, &(&1["id"] == assigns.selected_program_id))
  end

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
    Enum.reduce(semesters, 0, fn semester, acc ->
      acc + length(semester["courses"] || [])
    end)
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
