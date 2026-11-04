defmodule SnowSeToolsWeb.Curriculum.CurriculumComponents do
  @moduledoc "Pieces the curriculum views share: level badges and the course column headers."

  use SnowSeToolsWeb, :html

  alias SnowSeTools.Curriculum.{CourseCode, CurriculumMap}
  alias SnowSeToolsWeb.Curriculum.CurriculumLive

  attr :level, :string, required: true
  attr :long, :boolean, default: false

  def level_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center justify-center rounded font-semibold",
        level_class(@level),
        @long && "px-1.5 py-0.5 text-xs",
        !@long && "size-6 text-xs"
      ]}
      title={@level}
    >
      {if @long, do: @level, else: CurriculumMap.level_letter(@level)}
    </span>
    """
  end

  def level_class("introduced"), do: "bg-sky-500/20 text-sky-200 ring-1 ring-sky-400/40"
  def level_class("reinforced"), do: "bg-violet-500/20 text-violet-200 ring-1 ring-violet-400/40"
  def level_class("mastered"), do: "bg-emerald-500/25 text-emerald-200 ring-1 ring-emerald-400/50"
  def level_class(_level), do: "bg-slate-800 text-slate-400"

  def level_legend(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3 text-xs text-slate-400">
      <span
        :for={level <- ~w(introduced reinforced mastered)}
        class="inline-flex items-center gap-1.5"
      >
        <.level_badge level={level} /> {level}
      </span>
    </div>
    """
  end

  attr :courses, :list, required: true
  attr :nav, :map, required: true
  attr :corner, :string, default: ""

  @doc "Two header rows: semesters, then one vertical course code per column."
  def course_headers(assigns) do
    assigns = assign(assigns, :semesters, CurriculumMap.semesters(assigns.courses))

    ~H"""
    <tr>
      <th class="sticky left-0 z-20 bg-slate-950"></th>
      <th
        :for={semester <- @semesters}
        colspan={length(semester.courses)}
        class="border-b border-l border-slate-800 px-1 py-1 text-center text-[11px] font-medium uppercase tracking-wide text-slate-500"
      >
        Sem {semester.number}
      </th>
    </tr>
    <tr>
      <th class="sticky left-0 z-20 bg-slate-950 px-2 py-1 text-left align-bottom text-xs font-medium text-slate-400">
        {@corner}
      </th>
      <th :for={course <- @courses} class="border-l border-slate-800/70 px-0.5 pb-1 align-bottom">
        <.link
          navigate={CurriculumLive.course_path(nav: @nav, course: CourseCode.key(course))}
          class="mx-auto block whitespace-nowrap text-[11px] font-medium text-slate-300 [writing-mode:vertical-rl] rotate-180 hover:text-indigo-300"
          title={"#{CourseCode.label(course)} #{course["title"]}"}
        >
          {CourseCode.label(course)}
        </.link>
      </th>
    </tr>
    """
  end
end
