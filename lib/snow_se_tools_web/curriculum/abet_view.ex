defmodule SnowSeToolsWeb.Curriculum.AbetView do
  @moduledoc """
  ABET coverage: the department's matrix (which courses cover which student
  outcome and program criterion) beside what each course's own master
  syllabus tags. Where the two disagree the cell says so.
  """

  use SnowSeToolsWeb, :html

  import SnowSeToolsWeb.Curriculum.CurriculumComponents, only: [course_headers: 1]

  alias SnowSeTools.Curriculum.{CourseCode, CurriculumMap}
  alias SnowSeToolsWeb.Curriculum.CurriculumLive

  attr :courses, :list, required: true
  attr :data, :map, required: true
  attr :nav, :map, required: true
  attr :editor?, :boolean, required: true
  attr :workbook, :map, default: nil
  attr :upload, :any, default: nil

  def abet(assigns) do
    assigns =
      assign(
        assigns,
        :rows,
        CurriculumMap.abet_rows(courses: assigns.courses, data: assigns.data)
      )

    ~H"""
    <div class="space-y-4">
      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="space-y-1 text-xs text-slate-400">
          <p :if={@data.last_import}>
            Matrix imported from <span class="text-slate-200">{@data.last_import["file_name"]}</span>
            (sheet {@data.last_import["slo_sheet"]}<span :if={@data.last_import["criteria_sheet"]}>, criteria from {@data.last_import["criteria_sheet"]}</span>)
            by {@data.last_import["imported_by"]} on <time>{String.slice(@data.last_import["imported_at"], 0, 10)}</time>.
          </p>
          <p :if={!@data.last_import}>
            No ABET matrix imported yet; only outcomes tagged in the master syllabi show.
          </p>
          <div class="flex flex-wrap items-center gap-3">
            <span class="inline-flex items-center gap-1"><.mark cell={
              %{matrix: :covered, syllabus: true}
            } /> matrix and syllabus agree</span>
            <span class="inline-flex items-center gap-1"><.mark cell={
              %{matrix: :covered, syllabus: false}
            } /> matrix only</span>
            <span class="inline-flex items-center gap-1"><.mark cell={
              %{matrix: :tentative, syllabus: false}
            } /> tentative (?) in matrix</span>
            <span class="inline-flex items-center gap-1"><.mark cell={%{matrix: nil, syllabus: true}} />
            syllabus tags it, matrix does not</span>
          </div>
        </div>
        <.import_panel :if={@editor?} workbook={@workbook} upload={@upload} />
      </div>

      <div class="overflow-x-auto rounded-lg border border-slate-800">
        <table id="abet-matrix" class="border-separate border-spacing-0 text-sm">
          <thead>
            <.course_headers courses={@courses} nav={@nav} corner="ABET outcome" />
          </thead>
          <tbody>
            <tr :for={row <- @rows} id={"abet-#{slug(row.outcome["code"])}"} class="group">
              <th class="sticky left-0 z-10 w-80 min-w-80 border-t border-slate-800 bg-slate-950 px-2 py-1.5 text-left font-normal group-hover:bg-slate-900">
                <.link
                  patch={
                    CurriculumLive.curriculum_path(@nav,
                      tab: :graph,
                      overlay: "abet:" <> row.outcome["code"]
                    )
                  }
                  class="block text-slate-200 hover:text-indigo-300"
                  title={row.outcome["title"]}
                >
                  <span class="font-medium">{short_code(row.outcome)}</span>
                  <span class="line-clamp-2 text-xs text-slate-400">{row.outcome["title"]}</span>
                </.link>
              </th>
              <td
                :for={course <- @courses}
                class="border-l border-t border-slate-800/70 px-0.5 py-1 text-center group-hover:bg-slate-900/60"
              >
                <.mark cell={row.cells[CourseCode.key(course)]} course={CourseCode.label(course)} />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :cell, :map, default: nil
  attr :course, :string, default: nil

  defp mark(assigns) do
    ~H"""
    <span
      :if={@cell && (@cell.matrix || @cell.syllabus)}
      class={["inline-block size-4 rounded-full", mark_class(@cell)]}
      title={mark_title(@cell, @course)}
    ></span>
    """
  end

  defp mark_class(%{matrix: :covered, syllabus: true}), do: "bg-emerald-400"
  defp mark_class(%{matrix: :covered}), do: "bg-indigo-400"
  defp mark_class(%{matrix: :tentative}), do: "border-2 border-dashed border-indigo-300"
  defp mark_class(%{syllabus: true}), do: "border-2 border-amber-400 bg-amber-400/20"

  defp mark_title(cell, course) do
    matrix =
      case cell.matrix do
        :covered -> "the matrix marks it"
        :tentative -> "the matrix marks it tentatively (?)"
        nil -> "the matrix does not mark it"
      end

    syllabus =
      if cell.syllabus,
        do: "its master syllabus tags it",
        else: "its master syllabus does not tag it"

    "#{course}: #{matrix}; #{syllabus}"
  end

  attr :workbook, :map, default: nil
  attr :upload, :any, required: true

  defp import_panel(assigns) do
    ~H"""
    <div
      id="abet-import"
      class="w-full max-w-md rounded-lg border border-slate-800 bg-slate-900/40 p-3 text-xs"
    >
      <h3 class="mb-2 text-sm font-semibold text-slate-100">Import the ABET matrix</h3>
      <form
        :if={!@workbook}
        id="abet-upload-form"
        phx-change="curriculum-edit:abet_validate"
        phx-submit="curriculum-edit:abet_validate"
      >
        <p class="mb-2 text-slate-400">
          Upload the department's matrix workbook (.xlsx). Importing replaces the current matrix.
        </p>
        <.live_file_input upload={@upload} class="text-slate-300" />
        <p :for={entry <- @upload.entries} class="mt-1 text-slate-400">
          {entry.client_name} — {entry.progress}%
        </p>
        <p :for={error <- upload_errors(@upload)} class="mt-1 text-rose-300">{upload_error(error)}</p>
      </form>

      <form
        :if={@workbook}
        id="abet-sheets-form"
        phx-change="curriculum-edit:abet_sheets"
        phx-submit="curriculum-edit:abet_import"
        class="space-y-2"
      >
        <p class="text-slate-300">{@workbook.file_name}</p>
        <label class="block text-slate-400">
          Student outcomes from
          <select
            name="slo_sheet"
            class="mt-0.5 w-full rounded-md border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200"
          >
            <option
              :for={name <- @workbook.slo_sheets}
              value={name}
              selected={name == @workbook.slo_sheet}
            >
              {name}
            </option>
          </select>
        </label>
        <label class="block text-slate-400">
          Program criteria from
          <select
            name="criteria_sheet"
            class="mt-0.5 w-full rounded-md border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200"
          >
            <option value="">(none)</option>
            <option
              :for={name <- @workbook.criteria_sheets}
              value={name}
              selected={name == @workbook.criteria_sheet}
            >
              {name}
            </option>
          </select>
        </label>
        <p :if={match?({:ok, _}, @workbook.result)} id="abet-preview" class="text-slate-300">
          {preview_text(@workbook.result)}
        </p>
        <p :if={match?({:error, _}, @workbook.result)} class="text-rose-300">
          {elem(@workbook.result, 1)}
        </p>
        <div class="flex gap-2">
          <button
            type="submit"
            disabled={!match?({:ok, _}, @workbook.result)}
            class="rounded-md bg-indigo-500/20 px-2.5 py-1.5 font-medium text-indigo-200 hover:bg-indigo-500/30 disabled:opacity-40"
          >
            Import
          </button>
          <button
            type="button"
            phx-click="curriculum-edit:abet_cancel"
            class="rounded-md px-2.5 py-1.5 text-slate-400 hover:text-slate-200"
          >
            Cancel
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp preview_text({:ok, matrix}) do
    {slos, criteria} = Enum.split_with(matrix.outcomes, &(&1.kind == "slo"))

    courses =
      matrix.coverage |> Enum.map(&{&1.subject_code, &1.course_number}) |> Enum.uniq() |> length()

    "#{length(slos)} student outcomes, #{length(criteria)} program criteria, #{length(matrix.coverage)} marks across #{courses} courses."
  end

  defp upload_error(:too_large), do: "That file is too large."
  defp upload_error(:not_accepted), do: "Choose an .xlsx workbook."
  defp upload_error(:too_many_files), do: "Choose one workbook."
  defp upload_error(error), do: "Upload failed: #{inspect(error)}"

  defp short_code(%{"kind" => "slo", "number" => number}), do: "SLO #{number}"
  defp short_code(%{"kind" => "criterion"}), do: "Program criterion"

  defp slug(code),
    do: code |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
end
