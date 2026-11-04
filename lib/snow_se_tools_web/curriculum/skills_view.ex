defmodule SnowSeToolsWeb.Curriculum.SkillsView do
  @moduledoc """
  The skill catalog: every skill with its category, what it builds on, and
  which courses in the program teach it. Editors add, edit and delete skills
  and draw the "builds on" links here.
  """

  use SnowSeToolsWeb, :html

  import SnowSeToolsWeb.Curriculum.CurriculumComponents, only: [level_badge: 1]

  alias SnowSeTools.Curriculum.{CourseCode, CurriculumDb, CurriculumMap}
  alias SnowSeToolsWeb.Curriculum.CurriculumLive

  attr :courses, :list, required: true
  attr :data, :map, required: true
  attr :nav, :map, required: true
  attr :editor?, :boolean, required: true
  attr :editing_skill_id, :string, default: nil

  def skills(assigns) do
    order =
      assigns.courses |> Enum.with_index() |> Map.new(fn {c, i} -> {CourseCode.key(c), i} end)

    names = Map.new(assigns.data.skills, &{&1["id"], &1["name"]})

    assigns =
      assigns
      |> assign(:order, order)
      |> assign(:links_by_skill, Enum.group_by(assigns.data.links, & &1["skill_id"]))
      |> assign(
        :builds_on,
        Enum.group_by(
          assigns.data.dependencies,
          & &1["skill_id"],
          &names[&1["builds_on_skill_id"]]
        )
      )
      |> assign(
        :builds_on_ids,
        Enum.group_by(assigns.data.dependencies, & &1["skill_id"], & &1["builds_on_skill_id"])
      )
      |> assign(:grouped, assigns.data.skills |> Enum.group_by(& &1["category"]))

    ~H"""
    <div class="mx-auto max-w-5xl space-y-6">
      <.skill_form
        :if={@editor? and @editing_skill_id == "new"}
        skill={nil}
        skills={@data.skills}
        builds_on_ids={[]}
      />
      <div :if={@editor? and @editing_skill_id != "new"} class="flex justify-end">
        <button
          id="new-skill"
          type="button"
          phx-click="curriculum-edit:edit_skill"
          phx-value-id="new"
          class="inline-flex items-center gap-1 rounded-md bg-indigo-500/15 px-2.5 py-1.5 text-xs font-medium text-indigo-200 hover:bg-indigo-500/25"
        >
          <.icon name="hero-plus" class="size-3.5" /> New skill
        </button>
      </div>

      <section
        :for={category <- CurriculumDb.skill_categories()}
        :if={@grouped[category]}
        class="space-y-2"
      >
        <h2 class="text-sm font-semibold text-slate-200">{CurriculumMap.category_label(category)}</h2>
        <div class="divide-y divide-slate-800 rounded-lg border border-slate-800">
          <div :for={skill <- @grouped[category]} id={"skill-#{skill["id"]}"} class="p-3">
            <.skill_form
              :if={@editor? and @editing_skill_id == skill["id"]}
              skill={skill}
              skills={@data.skills}
              builds_on_ids={Map.get(@builds_on_ids, skill["id"], [])}
            />
            <div
              :if={@editing_skill_id != skill["id"]}
              class="flex flex-wrap items-start justify-between gap-3"
            >
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-slate-100">{skill["name"]}</p>
                <p :if={skill["description"] != ""} class="text-xs text-slate-400">
                  {skill["description"]}
                </p>
                <p :if={@builds_on[skill["id"]]} class="mt-1 text-xs text-slate-500">
                  Builds on {Enum.join(Enum.sort(@builds_on[skill["id"]]), ", ")}
                </p>
                <div class="mt-2 flex flex-wrap gap-1.5">
                  <.link
                    :for={link <- sorted_links(@links_by_skill[skill["id"]], @order)}
                    navigate={CurriculumLive.course_path(nav: @nav, course: CourseCode.key(link))}
                    class="inline-flex items-center gap-1 whitespace-nowrap rounded-md bg-slate-800/70 px-1.5 py-0.5 text-xs text-slate-300 hover:bg-slate-800"
                  >
                    <.level_badge level={link["level"]} /> {CourseCode.label(link)}
                  </.link>
                  <span :if={!@links_by_skill[skill["id"]]} class="text-xs text-slate-600">No course teaches this yet.</span>
                </div>
              </div>
              <div :if={@editor?} class="flex shrink-0 gap-1">
                <button
                  type="button"
                  phx-click="curriculum-edit:edit_skill"
                  phx-value-id={skill["id"]}
                  class="rounded-md px-2 py-1 text-xs text-slate-400 hover:bg-slate-800 hover:text-slate-200"
                >
                  Edit
                </button>
                <button
                  type="button"
                  phx-click="curriculum-edit:delete_skill"
                  phx-value-id={skill["id"]}
                  data-confirm={"Delete #{skill["name"]}? Its links to courses go with it."}
                  class="rounded-md px-2 py-1 text-xs text-rose-300/80 hover:bg-rose-500/10 hover:text-rose-200"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :skill, :any, default: nil
  attr :skills, :list, required: true
  attr :builds_on_ids, :list, required: true

  defp skill_form(assigns) do
    ~H"""
    <form
      id={"skill-form-#{(@skill && @skill["id"]) || "new"}"}
      phx-submit="curriculum-edit:save_skill"
      class="space-y-2 rounded-lg border border-indigo-500/30 bg-slate-900/50 p-3 text-xs"
    >
      <input type="hidden" name="skill[id]" value={@skill && @skill["id"]} />
      <div class="grid gap-2 sm:grid-cols-[1fr_12rem]">
        <label class="block text-slate-400">
          Name
          <input
            name="skill[name]"
            value={@skill && @skill["name"]}
            required
            class="mt-0.5 w-full rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-sm text-slate-100"
          />
        </label>
        <label class="block text-slate-400">
          Category
          <select
            name="skill[category]"
            class="mt-0.5 w-full rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-sm text-slate-100"
          >
            <option
              :for={category <- CurriculumDb.skill_categories()}
              value={category}
              selected={(@skill && @skill["category"]) == category}
            >
              {CurriculumMap.category_label(category)}
            </option>
          </select>
        </label>
      </div>
      <label class="block text-slate-400">
        Description
        <input
          name="skill[description]"
          value={@skill && @skill["description"]}
          class="mt-0.5 w-full rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-sm text-slate-100"
        />
      </label>
      <label :if={@skill} class="block text-slate-400">
        Builds on (hold Ctrl or ⌘ to pick several)
        <select
          name="skill[builds_on_ids][]"
          multiple
          size="6"
          class="mt-0.5 w-full rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-sm text-slate-100"
        >
          <option
            :for={other <- @skills}
            :if={other["id"] != @skill["id"]}
            value={other["id"]}
            selected={other["id"] in @builds_on_ids}
          >
            {other["name"]}
          </option>
        </select>
      </label>
      <div class="flex gap-2">
        <button
          type="submit"
          class="rounded-md bg-indigo-500/20 px-2.5 py-1.5 font-medium text-indigo-200 hover:bg-indigo-500/30"
        >
          Save
        </button>
        <button
          type="button"
          phx-click="curriculum-edit:cancel_skill"
          class="rounded-md px-2.5 py-1.5 text-slate-400 hover:text-slate-200"
        >
          Cancel
        </button>
      </div>
    </form>
    """
  end

  defp sorted_links(nil, _order), do: []

  defp sorted_links(links, order) do
    Enum.sort_by(links, &{Map.get(order, CourseCode.key(&1), 10_000), CourseCode.label(&1)})
  end
end
