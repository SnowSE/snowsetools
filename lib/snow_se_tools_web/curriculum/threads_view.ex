defmodule SnowSeToolsWeb.Curriculum.ThreadsView do
  @moduledoc """
  Skill threads: one row per skill, one column per course in plan order, so a
  skill's path from introduced to mastered reads left to right.
  """

  use SnowSeToolsWeb, :html

  import SnowSeToolsWeb.Curriculum.CurriculumComponents

  alias SnowSeTools.Curriculum.{CourseCode, CurriculumDb, CurriculumMap}
  alias SnowSeToolsWeb.Curriculum.CurriculumLive

  attr :courses, :list, required: true
  attr :data, :map, required: true
  attr :nav, :map, required: true
  attr :filter, :map, required: true

  def threads(assigns) do
    rows = CurriculumMap.threads(courses: assigns.courses, data: assigns.data)
    visible = filter_rows(rows, assigns.filter)

    assigns =
      assigns
      |> assign(:rows, visible)
      |> assign(:hidden_unused, Enum.count(rows, &(&1.cells == %{})))
      |> assign(:issue_count, Enum.count(visible, &(&1.issues != [])))

    ~H"""
    <div class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <form
          id="threads-filter"
          phx-change="filter_threads"
          class="flex flex-wrap items-center gap-2 text-xs"
        >
          <input
            type="search"
            name="query"
            value={@filter["query"]}
            placeholder="Filter skills…"
            phx-debounce="200"
            class="w-48 rounded-md border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200"
          />
          <select
            name="category"
            class="rounded-md border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200"
          >
            <option value="">All categories</option>
            <option
              :for={category <- CurriculumDb.skill_categories()}
              value={category}
              selected={@filter["category"] == category}
            >
              {CurriculumMap.category_label(category)}
            </option>
          </select>
          <input type="hidden" name="show_unused" value="false" />
          <label class="inline-flex items-center gap-1.5 text-slate-400">
            <input
              type="checkbox"
              name="show_unused"
              value="true"
              checked={@filter["show_unused"] == "true"}
            /> Show skills no course teaches yet
          </label>
        </form>
        <div class="flex items-center gap-4">
          <span :if={@issue_count > 0} class="inline-flex items-center gap-1 text-xs text-amber-300">
            <.icon name="hero-exclamation-triangle" class="size-4" /> {@issue_count} skills with sequencing questions
          </span>
          <.level_legend />
        </div>
      </div>

      <div
        :if={@rows == []}
        class="rounded-lg border border-dashed border-slate-800 p-8 text-center text-sm text-slate-500"
      >
        No course in this program is linked to a skill yet. Link skills on a course page, or run the review on the
        Suggestions tab and accept what fits.
      </div>

      <div :if={@rows != []} class="overflow-x-auto rounded-lg border border-slate-800">
        <table id="skill-threads" class="border-separate border-spacing-0 text-sm">
          <thead>
            <.course_headers courses={@courses} nav={@nav} corner="Skill" />
          </thead>
          <tbody>
            <tr :for={row <- @rows} id={"thread-#{row.skill["id"]}"} class="group">
              <th class="sticky left-0 z-10 min-w-56 max-w-72 border-t border-slate-800 bg-slate-950 px-2 py-1 text-left font-normal group-hover:bg-slate-900">
                <div class="flex items-center gap-1.5">
                  <.link
                    patch={
                      CurriculumLive.curriculum_path(@nav,
                        tab: :graph,
                        overlay: "skill:" <> row.skill["id"]
                      )
                    }
                    class="truncate text-slate-200 hover:text-indigo-300"
                    title={thread_title(row)}
                  >
                    {row.skill["name"]}
                  </.link>
                  <span
                    :if={row.issues != []}
                    title={Enum.join(row.issues, "\n")}
                    class="text-amber-300"
                  >
                    <.icon name="hero-exclamation-triangle" class="size-3.5" />
                  </span>
                </div>
                <div class="text-[11px] text-slate-500">
                  {CurriculumMap.category_label(row.skill["category"])}
                </div>
              </th>
              <td
                :for={course <- @courses}
                class="border-l border-t border-slate-800/70 px-0.5 py-1 text-center group-hover:bg-slate-900/60"
              >
                <span
                  :for={cell <- List.wrap(row.cells[CourseCode.key(course)])}
                  title={"#{CourseCode.label(course)}: #{cell.level}#{if cell.note not in [nil, ""], do: " — " <> cell.note}"}
                >
                  <.level_badge level={cell.level} />
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p :if={@hidden_unused > 0 and @filter["show_unused"] != "true"} class="text-xs text-slate-500">
        {@hidden_unused} catalog skills are not linked to any course in this program.
      </p>
    </div>
    """
  end

  defp filter_rows(rows, filter) do
    query = String.downcase(String.trim(filter["query"] || ""))

    Enum.filter(rows, fn row ->
      (filter["show_unused"] == "true" or row.cells != %{}) and
        (filter["category"] in [nil, ""] or row.skill["category"] == filter["category"]) and
        (query == "" or String.contains?(String.downcase(row.skill["name"]), query))
    end)
  end

  defp thread_title(row) do
    builds_on =
      case row.builds_on do
        [] -> ""
        skills -> "\nBuilds on: " <> Enum.map_join(skills, ", ", & &1["name"])
      end

    "#{row.skill["description"]}#{builds_on}\nClick to see it on the prerequisite map."
  end
end
