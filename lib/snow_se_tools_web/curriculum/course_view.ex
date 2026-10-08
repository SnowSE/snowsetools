defmodule SnowSeToolsWeb.Curriculum.CourseView do
  @moduledoc """
  One course: its master syllabus outcomes (with what changed since the
  first read), the skills it teaches with where each comes from and goes
  next, its ABET coverage, and any suggestions waiting on it.
  """

  use SnowSeToolsWeb, :html

  import SnowSeToolsWeb.Curriculum.CurriculumComponents, only: [level_badge: 1]

  alias SnowSeTools.Curriculum.{CourseCode, CurriculumDb, CurriculumMap}
  alias SnowSeToolsWeb.Curriculum.{CurriculumLive, SuggestionsView}

  attr :course_key, :any, required: true
  attr :courses, :list, required: true
  attr :data, :map, required: true
  attr :nav, :map, required: true
  attr :editor?, :boolean, required: true

  def course_view(assigns) do
    view =
      CurriculumMap.course_view(
        course: assigns.course_key,
        courses: assigns.courses,
        data: assigns.data
      )

    linked = MapSet.new(view.skills, & &1.skill["id"])

    assigns =
      assigns
      |> assign(:view, view)
      |> assign(
        :unlinked_skills,
        Enum.reject(assigns.data.skills, &MapSet.member?(linked, &1["id"]))
      )

    ~H"""
    <div id="course-detail" class="mx-auto max-w-6xl space-y-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <.link
            patch={CurriculumLive.curriculum_path(@nav)}
            class="text-xs text-slate-400 hover:text-slate-200"
          >
            ← Curriculum map
          </.link>
          <h2 class="mt-1 text-xl font-semibold text-slate-100">
            {@view.label} <span class="font-normal text-slate-300">{title(@view)}</span>
          </h2>
          <p class="text-xs text-slate-500">
            <span :if={@view.course}>Semester {@view.course["semester"]} of {@nav.program["name"]}</span>
            <span :if={!@view.in_program?}>Not in {@nav.program && @nav.program["name"]}'s plan</span>
          </p>
        </div>
        <div class="text-right text-xs text-slate-400">
          <a
            :if={@view.syllabus && @view.syllabus["url"]}
            href={@view.syllabus["url"]}
            target="_blank"
            rel="noopener"
            class="text-indigo-300 hover:text-indigo-200"
          >
            Master syllabus on snow.edu ↗
          </a>
          <p :if={@view.syllabus && @view.syllabus["semester_approved"] != ""}>
            Approved {@view.syllabus["semester_approved"]} · five-year review {@view.syllabus[
              "five_year_review"
            ]}
          </p>
          <p :if={@view.syllabus && @view.syllabus["fetched_at"]}>
            Read {String.slice(@view.syllabus["fetched_at"], 0, 10)}
          </p>
          <p :if={@view.syllabus && @view.syllabus["fetch_error"]} class="text-amber-300">
            Last read failed: {@view.syllabus["fetch_error"]}
          </p>
          <p :if={!@view.syllabus}>Master syllabus not read yet (Suggestions → Re-read).</p>
        </div>
      </div>

      <div
        :if={@view.prerequisites not in [nil, []] or @view.corequisites not in [nil, []]}
        class="flex flex-wrap gap-4 text-xs"
      >
        <.course_chips label="Prerequisites" codes={@view.prerequisites} nav={@nav} />
        <.course_chips label="Corequisites" codes={@view.corequisites} nav={@nav} />
      </div>

      <section id="course-outcomes" class="space-y-2">
        <h3 class="text-sm font-semibold text-slate-200">
          Learning outcomes <span class="font-normal text-slate-500">(from the master syllabus)</span>
        </h3>
        <p :if={@view.outcomes == []} class="text-xs text-slate-500">None on file.</p>
        <ol class="ms-5 list-decimal space-y-1.5 text-sm text-slate-200">
          <li :for={outcome <- @view.outcomes}>
            {CurriculumMap.outcome_text(outcome)}
            <span
              :for={number <- outcome["abet_slos"] || []}
              class="ms-1 rounded bg-emerald-500/15 px-1.5 text-[11px] text-emerald-200"
            >
              ABET SLO {number}
            </span>
            <span
              :if={outcome["added_since_first_read"]}
              class="ms-1 rounded bg-amber-500/15 px-1.5 text-[11px] text-amber-200"
            >
              new {String.slice(outcome["first_seen_at"], 0, 10)}
            </span>
          </li>
        </ol>
        <details :if={@view.retired_outcomes != []} class="text-xs text-slate-500">
          <summary class="cursor-pointer">
            {length(@view.retired_outcomes)} outcomes removed from the master syllabus
          </summary>
          <ul class="ms-5 mt-1 list-disc space-y-1">
            <li :for={outcome <- @view.retired_outcomes} class="line-through decoration-slate-600">
              {CurriculumMap.outcome_text(outcome)}
              <span class="no-underline">(removed {String.slice(outcome["retired_at"], 0, 10)})</span>
            </li>
          </ul>
        </details>
      </section>

      <section id="course-skills" class="space-y-2">
        <h3 class="text-sm font-semibold text-slate-200">Skills</h3>
        <p :if={@view.skills == []} class="text-xs text-slate-500">No skills linked yet.</p>
        <div :if={@view.skills != []} class="overflow-x-auto rounded-lg border border-slate-800">
          <table class="w-full text-sm">
            <thead class="text-left text-xs text-slate-500">
              <tr>
                <th class="px-3 py-2 font-medium">Skill</th>
                <th class="px-3 py-2 font-medium">Here</th>
                <th class="px-3 py-2 font-medium">Earlier</th>
                <th class="px-3 py-2 font-medium">Later</th>
                <th :if={@editor?} class="px-3 py-2"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-800">
              <tr :for={row <- @view.skills} id={"course-skill-#{row.skill["id"]}"}>
                <td class="px-3 py-2 align-top">
                  <p class="text-slate-100">{row.skill["name"]}</p>
                  <p :if={row.note not in [nil, ""]} class="max-w-md text-xs text-slate-500">
                    {row.note}
                  </p>
                </td>
                <td class="px-3 py-2 align-top">
                  <form
                    :if={@editor?}
                    phx-change="curriculum-edit:save_link"
                    id={"level-form-#{row.skill["id"]}"}
                  >
                    <input type="hidden" name="link[subject_code]" value={elem(@view.key, 0)} />
                    <input type="hidden" name="link[course_number]" value={elem(@view.key, 1)} />
                    <input type="hidden" name="link[skill_id]" value={row.skill["id"]} />
                    <input type="hidden" name="link[note]" value={row.note} />
                    <select
                      name="link[level]"
                      class="rounded-md border border-slate-700 bg-slate-900 px-1.5 py-1 text-xs text-slate-200"
                    >
                      <option
                        :for={level <- CurriculumDb.levels()}
                        value={level}
                        selected={level == row.level}
                      >
                        {level}
                      </option>
                    </select>
                  </form>
                  <.level_badge :if={!@editor?} level={row.level} long />
                </td>
                <td class="px-3 py-2 align-top"><.link_chips links={row.earlier} nav={@nav} /></td>
                <td class="px-3 py-2 align-top"><.link_chips links={row.later} nav={@nav} /></td>
                <td :if={@editor?} class="px-3 py-2 text-right align-top">
                  <button
                    type="button"
                    phx-click="curriculum-edit:remove_link"
                    phx-value-subject_code={elem(@view.key, 0)}
                    phx-value-course_number={elem(@view.key, 1)}
                    phx-value-skill_id={row.skill["id"]}
                    class="rounded-md px-2 py-1 text-xs text-rose-300/80 hover:bg-rose-500/10"
                  >
                    Remove
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <form
          :if={@editor?}
          id="add-course-skill"
          phx-submit="curriculum-edit:save_link"
          class="flex flex-wrap items-end gap-2 rounded-lg border border-dashed border-slate-800 p-3 text-xs"
        >
          <input type="hidden" name="link[subject_code]" value={elem(@view.key, 0)} />
          <input type="hidden" name="link[course_number]" value={elem(@view.key, 1)} />
          <label class="text-slate-400">
            Skill
            <select
              name="link[skill_id]"
              class="mt-0.5 block rounded-md border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200"
            >
              <option value="">Choose…</option>
              <option :for={skill <- @unlinked_skills} value={skill["id"]}>{skill["name"]}</option>
            </select>
          </label>
          <label class="text-slate-400">
            Level
            <select
              name="link[level]"
              class="mt-0.5 block rounded-md border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200"
            >
              <option :for={level <- CurriculumDb.levels()} value={level}>{level}</option>
            </select>
          </label>
          <label class="min-w-48 flex-1 text-slate-400">
            Note
            <input
              name="link[note]"
              placeholder="Where or how it shows up"
              class="mt-0.5 block w-full rounded-md border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200"
            />
          </label>
          <button
            type="submit"
            class="rounded-md bg-indigo-500/20 px-2.5 py-1.5 font-medium text-indigo-200 hover:bg-indigo-500/30"
          >
            Link skill
          </button>
        </form>
      </section>

      <section id="course-abet" class="space-y-2">
        <h3 class="text-sm font-semibold text-slate-200">ABET coverage</h3>
        <p :if={@view.abet == []} class="text-xs text-slate-500">
          Neither the matrix nor the master syllabus maps this course to an ABET outcome.
        </p>
        <ul class="space-y-1 text-sm">
          <li :for={item <- @view.abet} class="flex items-start gap-2">
            <span class="mt-1 text-xs text-slate-400">{coverage_label(item.cell)}</span>
            <span class="text-slate-200">{item.outcome["title"]}</span>
          </li>
        </ul>
      </section>

      <section :if={@view.pending != []} id="course-suggestions" class="space-y-2">
        <h3 class="text-sm font-semibold text-slate-200">Waiting suggestions</h3>
        <div class="divide-y divide-slate-800 rounded-lg border border-slate-800">
          <SuggestionsView.suggestion_row
            :for={suggestion <- @view.pending}
            suggestion={suggestion}
            editor?={@editor?}
          />
        </div>
      </section>

      <details
        :if={@view.syllabus && @view.syllabus["description"] != ""}
        class="text-sm text-slate-300"
      >
        <summary class="cursor-pointer text-xs text-slate-400">
          Catalog description and content
        </summary>
        <p class="mt-2 whitespace-pre-line">{@view.syllabus["description"]}</p>
        <p :if={@view.syllabus["content"] != ""} class="mt-2 whitespace-pre-line text-slate-400">
          {@view.syllabus["content"]}
        </p>
      </details>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :codes, :list, default: nil
  attr :nav, :map, required: true

  defp course_chips(assigns) do
    ~H"""
    <div :if={@codes not in [nil, []]} class="flex flex-wrap items-center gap-1.5">
      <span class="text-slate-500">{@label}</span>
      <.link
        :for={code <- @codes}
        navigate={CurriculumLive.course_path(nav: @nav, course: code)}
        class="rounded-md bg-slate-800/70 px-1.5 py-0.5 text-slate-300 hover:bg-slate-800"
      >
        {CourseCode.label(code)}
      </.link>
    </div>
    """
  end

  attr :links, :list, required: true
  attr :nav, :map, required: true

  defp link_chips(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-1">
      <.link
        :for={link <- @links}
        navigate={CurriculumLive.course_path(nav: @nav, course: CourseCode.key(link))}
        class="inline-flex items-center gap-1 whitespace-nowrap rounded-md bg-slate-800/60 px-1 py-0.5 text-xs text-slate-300 hover:bg-slate-800"
      >
        <.level_badge level={link["level"]} /> {CourseCode.label(link)}
      </.link>
      <span :if={@links == []} class="text-xs text-slate-600">—</span>
    </div>
    """
  end

  defp title(%{course: %{"title" => title}}) when title not in [nil, ""], do: title

  defp title(%{syllabus: %{"title" => title}, label: label}) when is_binary(title),
    do: String.replace_prefix(title, label, "") |> String.trim()

  defp title(_view), do: ""

  defp coverage_label(%{matrix: :covered, syllabus: true}), do: "matrix + syllabus"
  defp coverage_label(%{matrix: :covered}), do: "matrix"
  defp coverage_label(%{matrix: :tentative, syllabus: true}), do: "matrix (?) + syllabus"
  defp coverage_label(%{matrix: :tentative}), do: "matrix (?)"
  defp coverage_label(%{syllabus: true}), do: "syllabus only"
end
