defmodule SnowSeToolsWeb.Curriculum.SuggestionsView do
  @moduledoc """
  The review: a button that re-reads every master syllabus and asks the model
  which skills each course teaches, what the last run found, and the
  suggestions waiting for an editor, grouped by course.
  """

  use SnowSeToolsWeb, :html

  import SnowSeToolsWeb.Curriculum.CurriculumComponents, only: [level_badge: 1]

  alias SnowSeTools.Curriculum.{CourseCode, CurriculumDb}
  alias SnowSeToolsWeb.Curriculum.CurriculumLive

  attr :courses, :list, required: true
  attr :data, :map, required: true
  attr :nav, :map, required: true
  attr :editor?, :boolean, required: true
  attr :run_status, :map, required: true

  def suggestions(assigns) do
    titles = Map.new(assigns.courses, &{CourseCode.key(&1), &1["title"]})

    {course_groups, graph} =
      Enum.split_with(assigns.data.pending, &(&1["kind"] == "course_skill"))

    assigns =
      assigns
      |> assign(:titles, titles)
      |> assign(:course_groups, group_by_course(course_groups, assigns.courses))
      |> assign(:graph_suggestions, graph)
      |> assign(:fetch_errors, Enum.filter(assigns.data.master_syllabi, & &1["fetch_error"]))

    ~H"""
    <div class="mx-auto max-w-5xl space-y-6">
      <section id="review-run" class="rounded-lg border border-slate-800 bg-slate-900/40 p-4">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="max-w-2xl space-y-1 text-sm">
            <h2 class="font-semibold text-slate-100">Re-read master syllabi and suggest skills</h2>
            <p class="text-xs text-slate-400">
              Reads every course in {@nav.program && @nav.program["name"]} from snow.edu's master syllabi (outcomes are
              mirrored; changes are flagged on the course page), then asks the AI which skills each course teaches using
              the master syllabus, the latest three terms of course materials in SnowSE/faculty and the section syllabi.
              Nothing changes in the map until an editor accepts a suggestion.
            </p>
          </div>
          <div :if={@editor?} class="flex shrink-0 flex-col gap-2">
            <button
              id="start-review"
              type="button"
              phx-click="curriculum-edit:start_run"
              phx-value-kind="full"
              disabled={@run_status.running?}
              class="inline-flex items-center gap-1.5 rounded-md bg-indigo-500/20 px-3 py-1.5 text-xs font-medium text-indigo-100 hover:bg-indigo-500/30 disabled:opacity-40"
            >
              <.icon name="hero-sparkles" class="size-4" /> Re-read &amp; suggest
            </button>
            <button
              id="start-syllabi-only"
              type="button"
              phx-click="curriculum-edit:start_run"
              phx-value-kind="syllabi_only"
              disabled={@run_status.running?}
              class="rounded-md px-3 py-1.5 text-xs text-slate-400 hover:bg-slate-800 hover:text-slate-200 disabled:opacity-40"
            >
              Re-read master syllabi only
            </button>
          </div>
        </div>
        <.run_summary status={@run_status} />
        <div :if={@fetch_errors != []} class="mt-3 text-xs text-amber-200/90">
          <p class="font-medium">Master syllabi that could not be read last time:</p>
          <ul class="ms-4 list-disc">
            <li :for={row <- @fetch_errors}>{CourseCode.label(row)}: {row["fetch_error"]}</li>
          </ul>
        </div>
      </section>

      <p
        :if={@data.pending == []}
        class="rounded-lg border border-dashed border-slate-800 p-8 text-center text-sm text-slate-500"
      >
        No suggestions waiting.
      </p>

      <section
        :for={{key, suggestions} <- @course_groups}
        id={"suggestions-#{elem(key, 0)}-#{elem(key, 1)}"}
        class="space-y-2"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h3 class="text-sm font-semibold text-slate-100">
            <.link
              navigate={CurriculumLive.course_path(nav: @nav, course: key)}
              class="hover:text-indigo-300"
            >
              {CourseCode.label(key)} <span class="font-normal text-slate-400">{@titles[key]}</span>
            </.link>
          </h3>
          <div :if={@editor?} class="flex gap-1 text-xs">
            <button
              type="button"
              phx-click="curriculum-edit:accept_group"
              phx-value-ids={Enum.map_join(suggestions, ",", & &1["id"])}
              class="rounded-md px-2 py-1 text-emerald-300 hover:bg-emerald-500/10"
            >
              Accept all {length(suggestions)}
            </button>
            <button
              type="button"
              phx-click="curriculum-edit:reject_group"
              phx-value-ids={Enum.map_join(suggestions, ",", & &1["id"])}
              class="rounded-md px-2 py-1 text-rose-300/80 hover:bg-rose-500/10"
            >
              Reject all
            </button>
          </div>
        </div>
        <div class="divide-y divide-slate-800 rounded-lg border border-slate-800">
          <.suggestion_row
            :for={suggestion <- suggestions}
            suggestion={suggestion}
            editor?={@editor?}
          />
        </div>
      </section>

      <section :if={@graph_suggestions != []} id="suggestions-skill-graph" class="space-y-2">
        <h3 class="text-sm font-semibold text-slate-100">Skill catalog</h3>
        <div class="divide-y divide-slate-800 rounded-lg border border-slate-800">
          <.suggestion_row
            :for={suggestion <- @graph_suggestions}
            suggestion={suggestion}
            editor?={@editor?}
          />
        </div>
      </section>
    </div>
    """
  end

  attr :suggestion, :map, required: true
  attr :editor?, :boolean, required: true

  def suggestion_row(assigns) do
    ~H"""
    <form
      id={"suggestion-#{@suggestion["id"]}"}
      phx-submit="curriculum-edit:accept"
      class="flex flex-wrap items-start justify-between gap-3 p-3 text-sm"
    >
      <input type="hidden" name="suggestion_id" value={@suggestion["id"]} />
      <div class="min-w-0 flex-1 space-y-1">
        <.describe suggestion={@suggestion} />
        <p :if={@suggestion["evidence"] != ""} class="text-xs text-slate-400">
          <span class="text-slate-500">Evidence:</span> {@suggestion["evidence"]}
        </p>
        <p :if={@suggestion["rationale"] != ""} class="text-xs text-slate-400">
          {@suggestion["rationale"]}
        </p>
      </div>
      <div :if={@editor?} class="flex shrink-0 items-center gap-1 text-xs">
        <select
          :if={@suggestion["kind"] == "course_skill"}
          name="level"
          class="rounded-md border border-slate-700 bg-slate-900 px-1.5 py-1 text-slate-200"
        >
          <option
            :for={level <- CurriculumDb.levels()}
            value={level}
            selected={level == @suggestion["payload"]["level"]}
          >
            {level}
          </option>
        </select>
        <button
          type="submit"
          class="rounded-md bg-emerald-500/15 px-2 py-1 font-medium text-emerald-200 hover:bg-emerald-500/25"
        >
          Accept
        </button>
        <button
          type="button"
          phx-click="curriculum-edit:reject"
          phx-value-id={@suggestion["id"]}
          class="rounded-md px-2 py-1 text-rose-300/80 hover:bg-rose-500/10"
        >
          Reject
        </button>
      </div>
    </form>
    """
  end

  attr :suggestion, :map, required: true

  defp describe(%{suggestion: %{"kind" => "course_skill"}} = assigns) do
    ~H"""
    <p class="flex flex-wrap items-center gap-1.5 text-slate-200">
      <.level_badge level={@suggestion["payload"]["level"]} long />
      <span class="font-medium">{@suggestion["payload"]["skill_name"]}</span>
      <span
        :if={!@suggestion["payload"]["skill_id"]}
        class="rounded bg-amber-500/15 px-1.5 text-[11px] text-amber-200"
        title={@suggestion["payload"]["description"]}
      >
        new skill
      </span>
      <span :if={@suggestion["payload"]["current_level"]} class="text-xs text-slate-500">
        (now {@suggestion["payload"]["current_level"]})
      </span>
    </p>
    """
  end

  defp describe(%{suggestion: %{"kind" => "skill_dependency"}} = assigns) do
    ~H"""
    <p class="text-slate-200">
      <span class="font-medium">{@suggestion["payload"]["skill_name"]}</span>
      <span class="text-slate-400">builds on</span>
      <span class="font-medium">{@suggestion["payload"]["builds_on_name"]}</span>
    </p>
    """
  end

  defp describe(%{suggestion: %{"kind" => "merge_skills"}} = assigns) do
    ~H"""
    <p class="text-slate-200">
      <span class="text-slate-400">Merge</span>
      <span class="font-medium">{@suggestion["payload"]["merge_name"]}</span>
      <span class="text-slate-400">into</span>
      <span class="font-medium">{@suggestion["payload"]["keep_name"]}</span>
    </p>
    """
  end

  attr :status, :map, required: true

  defp run_summary(assigns) do
    ~H"""
    <div
      :if={@status.run}
      id="last-run"
      class="mt-3 space-y-1 border-t border-slate-800 pt-3 text-xs text-slate-400"
    >
      <p :if={@status.running?} class="text-amber-200">{@status.phase}</p>
      <p :if={!@status.running?}>
        Last run {run_state(@status.run)} — started by {@status.run["started_by"]}
        <span :if={@status.run["started_at"]}>on <time>{String.slice(@status.run["started_at"], 0, 10)}</time></span>.
        <span :if={@status.run["error"]} class="text-rose-300">{@status.run["error"]}</span>
      </p>
      <ul :if={notes(@status.run) != []} class="ms-4 list-disc space-y-0.5">
        <li :for={note <- notes(@status.run)}>{note}</li>
      </ul>
    </div>
    """
  end

  defp run_state(%{"status" => "completed"}), do: "finished"
  defp run_state(%{"status" => "error"}), do: "stopped"
  defp run_state(%{"status" => status}), do: status

  defp notes(%{"notes" => notes}) when is_list(notes), do: notes
  defp notes(_run), do: []

  defp group_by_course(suggestions, courses) do
    order = courses |> Enum.with_index() |> Map.new(fn {c, i} -> {CourseCode.key(c), i} end)

    suggestions
    |> Enum.group_by(&{&1["subject_code"], &1["course_number"]})
    |> Enum.sort_by(fn {key, _list} -> {Map.get(order, key, 10_000), key} end)
  end
end
