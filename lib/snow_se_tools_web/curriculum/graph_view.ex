defmodule SnowSeToolsWeb.Curriculum.GraphView do
  @moduledoc """
  The prerequisite map: the program's courses in semester columns, with the
  prerequisite (solid) and corequisite (dashed) edges their master syllabi
  list. Choosing a skill or an ABET outcome lights up the courses that touch
  it and dims the rest.
  """

  use SnowSeToolsWeb, :html

  alias SnowSeTools.Curriculum.{CourseCode, CurriculumDb, CurriculumMap}
  alias SnowSeToolsWeb.Curriculum.CurriculumLive

  attr :courses, :list, required: true
  attr :data, :map, required: true
  attr :nav, :map, required: true

  def graph(assigns) do
    assigns =
      assigns
      |> assign(
        :graph,
        CurriculumMap.graph(
          courses: assigns.courses,
          data: assigns.data,
          overlay: assigns.nav.overlay
        )
      )
      |> assign(:overlay_value, overlay_value(assigns.nav.overlay))
      |> assign(:skills_by_category, Enum.group_by(assigns.data.skills, & &1["category"]))

    ~H"""
    <div class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <form id="graph-overlay-form" phx-change="set_overlay" class="flex items-center gap-2 text-xs">
          <label for="graph-overlay" class="text-slate-400">Highlight</label>
          <select
            id="graph-overlay"
            name="overlay"
            class="max-w-xs rounded-md border border-slate-700 bg-slate-900 px-2 py-1 text-slate-200"
          >
            <option value="">Nothing — just prerequisites</option>
            <optgroup
              :for={category <- CurriculumDb.skill_categories()}
              :if={@skills_by_category[category]}
              label={CurriculumMap.category_label(category)}
            >
              <option
                :for={skill <- @skills_by_category[category]}
                value={"skill:" <> skill["id"]}
                selected={@overlay_value == "skill:" <> skill["id"]}
              >
                {skill["name"]}
              </option>
            </optgroup>
            <optgroup :if={@data.abet_outcomes != []} label="ABET outcomes">
              <option
                :for={outcome <- @data.abet_outcomes}
                value={"abet:" <> outcome["code"]}
                selected={@overlay_value == "abet:" <> outcome["code"]}
              >
                {String.slice(outcome["code"], 0, 70)}
              </option>
            </optgroup>
          </select>
        </form>
        <.legend overlay={@nav.overlay} />
      </div>

      <div class="overflow-x-auto rounded-lg border border-slate-800 bg-slate-950/50">
        <svg
          id="prerequisite-graph"
          width={@graph.width}
          height={@graph.height}
          viewBox={"0 0 #{@graph.width} #{@graph.height}"}
          class="block"
          role="img"
          aria-label="Program courses by semester with prerequisite links"
        >
          <defs>
            <marker
              id="arrow"
              viewBox="0 0 10 10"
              refX="9"
              refY="5"
              markerWidth="7"
              markerHeight="7"
              orient="auto-start-reverse"
            >
              <path d="M 0 0 L 10 5 L 0 10 z" fill="#64748b" />
            </marker>
          </defs>
          <text
            :for={semester <- @graph.semesters}
            x={semester.x}
            y="20"
            text-anchor="middle"
            class="fill-slate-500 text-[11px] font-medium uppercase"
          >
            Semester {semester.number}
          </text>
          <path
            :for={edge <- @graph.edges}
            d={edge.path}
            fill="none"
            stroke="#64748b"
            stroke-width="1.25"
            stroke-dasharray={if edge.kind == :corequisite, do: "4 3"}
            marker-end="url(#arrow)"
            opacity={edge_opacity(edge, @graph.nodes, @nav.overlay)}
          >
            <title>{edge_title(edge)}</title>
          </path>
          <.link
            :for={node <- @graph.nodes}
            navigate={CurriculumLive.course_path(nav: @nav, course: node.key)}
          >
            <g
              id={"graph-node-#{elem(node.key, 0)}-#{elem(node.key, 1)}"}
              opacity={node_opacity(node, @nav.overlay)}
            >
              <title>{node.label} {node.title}{mark_suffix(node.mark)}</title>
              <rect
                x={node.x}
                y={node.y}
                width={@graph.node_width}
                height={@graph.node_height}
                rx="6"
                class={node_class(node.mark)}
              />
              <text x={node.x + 8} y={node.y + 18} class="fill-slate-100 text-[12px] font-semibold">
                {node.label}
              </text>
              <text x={node.x + 8} y={node.y + 34} class="fill-slate-400 text-[10px]">
                {truncate(node.title, 22)}
              </text>
            </g>
          </.link>
        </svg>
      </div>
    </div>
    """
  end

  attr :overlay, :any, default: nil

  defp legend(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3 text-xs text-slate-400">
      <span class="inline-flex items-center gap-1.5">
        <svg width="28" height="8"><line
          x1="0"
          y1="4"
          x2="28"
          y2="4"
          stroke="#64748b"
          stroke-width="1.5"
        /></svg>
        prerequisite
      </span>
      <span class="inline-flex items-center gap-1.5">
        <svg width="28" height="8"><line
          x1="0"
          y1="4"
          x2="28"
          y2="4"
          stroke="#64748b"
          stroke-width="1.5"
          stroke-dasharray="4 3"
        /></svg>
        corequisite
      </span>
      <%= case @overlay do %>
        <% {:skill, _id} -> %>
          <span
            :for={level <- ~w(introduced reinforced mastered)}
            class="inline-flex items-center gap-1.5"
          >
            <span class={["inline-block size-3 rounded-sm", swatch(level)]}></span> {level}
          </span>
        <% {:abet, _code} -> %>
          <span
            :for={mark <- ~w(covered tentative syllabus_only)}
            class="inline-flex items-center gap-1.5"
          >
            <span class={["inline-block size-3 rounded-sm", swatch(mark)]}></span> {String.replace(
              mark,
              "_",
              " "
            )}
          </span>
        <% _none -> %>
      <% end %>
    </div>
    """
  end

  defp node_class(nil), do: "fill-slate-900 stroke-slate-700"
  defp node_class("introduced"), do: "fill-sky-900/80 stroke-sky-400"
  defp node_class("reinforced"), do: "fill-violet-900/80 stroke-violet-400"
  defp node_class("mastered"), do: "fill-emerald-900/80 stroke-emerald-400"
  defp node_class("covered"), do: "fill-indigo-900/80 stroke-indigo-400"
  defp node_class("tentative"), do: "fill-slate-900 stroke-indigo-300 [stroke-dasharray:4_3]"
  defp node_class("syllabus_only"), do: "fill-amber-900/60 stroke-amber-400"

  defp swatch("introduced"), do: "bg-sky-700 ring-1 ring-sky-400"
  defp swatch("reinforced"), do: "bg-violet-700 ring-1 ring-violet-400"
  defp swatch("mastered"), do: "bg-emerald-700 ring-1 ring-emerald-400"
  defp swatch("covered"), do: "bg-indigo-700 ring-1 ring-indigo-400"
  defp swatch("tentative"), do: "ring-1 ring-dashed ring-indigo-300"
  defp swatch("syllabus_only"), do: "bg-amber-800 ring-1 ring-amber-400"

  defp node_opacity(_node, nil), do: "1"
  defp node_opacity(%{mark: nil}, _overlay), do: "0.35"
  defp node_opacity(_node, _overlay), do: "1"

  defp edge_opacity(_edge, _nodes, nil), do: "0.9"
  defp edge_opacity(_edge, _nodes, _overlay), do: "0.35"

  defp edge_title(%{kind: kind, from: from, to: to}),
    do: "#{CourseCode.label(from)} is a #{kind} of #{CourseCode.label(to)}"

  defp mark_suffix(nil), do: ""
  defp mark_suffix(mark), do: " — " <> String.replace(mark, "_", " ")

  defp overlay_value({:skill, id}), do: "skill:" <> id
  defp overlay_value({:abet, code}), do: "abet:" <> code
  defp overlay_value(_none), do: ""

  defp truncate(nil, _length), do: ""

  defp truncate(text, length) do
    if String.length(text) > length, do: String.slice(text, 0, length - 1) <> "…", else: text
  end
end
