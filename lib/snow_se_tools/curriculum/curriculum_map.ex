defmodule SnowSeTools.Curriculum.CurriculumMap do
  @moduledoc """
  Shapes the stored map into what each view draws, in the order of an academic
  program's plan. Pure: everything comes from `CurriculumData.load/0` and the
  program.
  """

  alias SnowSeTools.Curriculum.{CourseCode, MasterSyllabus}

  @category_order ~w(tool practice design concept)
  @level_rank %{"introduced" => 0, "reinforced" => 1, "mastered" => 2}

  @node_width 132
  @node_height 46
  @column_gap 64
  @row_gap 18
  @margin 16

  @doc """
  The program's courses in plan order, each with the (1-based) semester it is
  planned in. A course listed in two semesters keeps its first.
  """
  def program_courses(program) do
    (program["semesters"] || [])
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {semester, number} ->
      Enum.map(semester["courses"] || [], fn course ->
        %{
          "subject_code" => course["subject_code"],
          "course_number" => course["course_number"],
          "semester" => number
        }
      end)
    end)
    |> Enum.uniq_by(&CourseCode.key/1)
  end

  @doc "Adds each course's title from its master syllabus (\"SE 3140 Ethics…\" → \"Ethics…\")."
  def titled_courses(courses: courses, master_syllabi: master_syllabi) do
    titles = Map.new(master_syllabi, &{CourseCode.key(&1), &1["title"] || ""})

    Enum.map(courses, fn course ->
      title =
        titles
        |> Map.get(CourseCode.key(course), "")
        |> String.replace(~r/^\s*#{course["subject_code"]}\s*#{course["course_number"]}\s*/, "")

      Map.put(course, "title", title)
    end)
  end

  def semesters(courses) do
    courses
    |> Enum.group_by(& &1["semester"])
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {number, semester_courses} -> %{number: number, courses: semester_courses} end)
  end

  @doc """
  One row per skill: its level in each program course, and what looks wrong
  about its sequence — a skill first met as "reinforced" was never introduced,
  and a skill introduced before the skill it builds on is out of order.
  """
  def threads(courses: courses, data: data) do
    order = course_order(courses)
    skills_by_id = Map.new(data.skills, &{&1["id"], &1})
    builds_on = Enum.group_by(data.dependencies, & &1["skill_id"], & &1["builds_on_skill_id"])

    cells_by_skill =
      data.links
      |> Enum.filter(&Map.has_key?(order, CourseCode.key(&1)))
      |> Enum.group_by(& &1["skill_id"])
      |> Map.new(fn {skill_id, links} ->
        {skill_id, Map.new(links, &{CourseCode.key(&1), %{level: &1["level"], note: &1["note"]}})}
      end)

    first_seen =
      Map.new(cells_by_skill, fn {skill_id, cells} -> {skill_id, first_position(cells, order)} end)

    data.skills
    |> Enum.map(fn skill ->
      cells = Map.get(cells_by_skill, skill["id"], %{})
      prerequisites = Enum.map(Map.get(builds_on, skill["id"], []), &skills_by_id[&1])

      %{
        skill: skill,
        cells: cells,
        builds_on: Enum.reject(prerequisites, &is_nil/1),
        issues: thread_issues(skill, cells, order, prerequisites, first_seen)
      }
    end)
    |> Enum.sort_by(fn row ->
      {category_position(row.skill["category"]), first_seen[row.skill["id"]] || 10_000,
       String.downcase(row.skill["name"])}
    end)
  end

  defp thread_issues(skill, cells, order, prerequisites, first_seen) do
    first_course =
      cells
      |> Enum.min_by(fn {key, _cell} -> order[key] end, fn -> nil end)

    not_introduced =
      case first_course do
        {key, %{level: level}} when level != "introduced" ->
          [
            "First appears in #{CourseCode.label(key)} as #{level}; no earlier course introduces it."
          ]

        _introduced_or_unused ->
          []
      end

    out_of_order =
      for prerequisite <- prerequisites,
          prerequisite != nil,
          skill_first = first_seen[skill["id"]],
          prerequisite_first = first_seen[prerequisite["id"]],
          skill_first != nil,
          prerequisite_first == nil or prerequisite_first > skill_first do
        if prerequisite_first == nil,
          do: "Builds on #{prerequisite["name"]}, which no course in this program teaches.",
          else: "Taught before #{prerequisite["name"]}, which it builds on."
      end

    not_introduced ++ out_of_order
  end

  @doc """
  One row per ABET outcome: for each course, what the department's matrix
  says (covered or tentative) and whether the course's own master syllabus
  tags an outcome with that ABET number. The two disagreeing is worth a look.
  """
  def abet_rows(courses: courses, data: data) do
    keys = MapSet.new(courses, &CourseCode.key/1)

    matrix =
      Map.new(
        data.coverage,
        &{{&1["code"], CourseCode.key(&1)}, if(&1["tentative"], do: :tentative, else: :covered)}
      )

    syllabus_tags =
      for outcome <- data.outcomes,
          outcome["retired_at"] == nil,
          number <- outcome["abet_slos"] || [],
          into: MapSet.new(),
          do: {"SLO #{number}", CourseCode.key(outcome)}

    Enum.map(data.abet_outcomes, fn outcome ->
      cells =
        for key <- keys, into: %{} do
          {key,
           %{
             matrix: Map.get(matrix, {outcome["code"], key}),
             syllabus: MapSet.member?(syllabus_tags, {outcome["code"], key})
           }}
        end

      %{outcome: outcome, cells: cells}
    end)
  end

  @doc "Everything the course page shows for one course."
  def course_view(course: {subject, number} = key, courses: courses, data: data) do
    order = course_order(courses)
    syllabus = Enum.find(data.master_syllabi, &(CourseCode.key(&1) == key))

    {retired, active} =
      data.outcomes
      |> Enum.filter(&(CourseCode.key(&1) == key))
      |> Enum.split_with(& &1["retired_at"])

    skills_by_id = Map.new(data.skills, &{&1["id"], &1})
    links_by_skill = Enum.group_by(data.links, & &1["skill_id"])
    position = order[key]

    skills =
      data.links
      |> Enum.filter(&(CourseCode.key(&1) == key))
      |> Enum.map(fn link ->
        others =
          links_by_skill
          |> Map.get(link["skill_id"], [])
          |> Enum.reject(&(CourseCode.key(&1) == key))
          |> Enum.filter(&Map.has_key?(order, CourseCode.key(&1)))
          |> Enum.sort_by(&order[CourseCode.key(&1)])

        %{
          skill: skills_by_id[link["skill_id"]],
          level: link["level"],
          note: link["note"],
          earlier:
            Enum.filter(others, &(position != nil and order[CourseCode.key(&1)] < position)),
          later: Enum.filter(others, &(position == nil or order[CourseCode.key(&1)] > position))
        }
      end)
      |> Enum.reject(&is_nil(&1.skill))
      |> Enum.sort_by(
        &{@level_rank[&1.level], category_position(&1.skill["category"]), &1.skill["name"]}
      )

    abet =
      abet_rows(courses: courses, data: data)
      |> Enum.map(fn row ->
        %{outcome: row.outcome, cell: row.cells[key] || %{matrix: nil, syllabus: false}}
      end)
      |> Enum.filter(fn %{cell: cell} -> cell.matrix != nil or cell.syllabus end)

    %{
      key: key,
      label: "#{subject} #{number}",
      course: Enum.find(courses, &(CourseCode.key(&1) == key)),
      in_program?: position != nil,
      syllabus: syllabus,
      outcomes: Enum.sort_by(active, & &1["position"]),
      retired_outcomes: retired,
      skills: skills,
      abet: abet,
      prerequisites: syllabus && CourseCode.extract_all(syllabus["prerequisites"]),
      corequisites: syllabus && CourseCode.extract_all(syllabus["corequisites"]),
      pending: Enum.filter(data.pending, &({&1["subject_code"], &1["course_number"]} == key))
    }
  end

  @doc """
  Courses laid out by semester, with prerequisite and corequisite edges read
  from the master syllabi. `overlay` is `nil`, `{:skill, id}` or
  `{:abet, code}`; each node carries what the overlay says about it.
  """
  def graph(courses: courses, data: data, overlay: overlay) do
    semesters = semesters(courses)
    keys = MapSet.new(courses, &CourseCode.key/1)
    syllabi = Map.new(data.master_syllabi, &{CourseCode.key(&1), &1})
    marks = overlay_marks(overlay, courses, data)

    nodes =
      for {semester, column} <- Enum.with_index(semesters),
          {course, row} <- Enum.with_index(semester.courses) do
        key = CourseCode.key(course)

        %{
          key: key,
          label: CourseCode.label(course),
          title: course["title"],
          x: @margin + column * (@node_width + @column_gap),
          y: @margin + 24 + row * (@node_height + @row_gap),
          mark: Map.get(marks, key)
        }
      end

    positions = Map.new(nodes, &{&1.key, &1})

    edges =
      for {key, syllabus} <- syllabi,
          Map.has_key?(positions, key),
          {kind, field} <- [prerequisite: "prerequisites", corequisite: "corequisites"],
          from <- CourseCode.extract_all(syllabus[field]),
          MapSet.member?(keys, from),
          from != key do
        edge_path(kind, positions[from], positions[key])
      end

    tallest = semesters |> Enum.map(&length(&1.courses)) |> Enum.max(fn -> 0 end)

    %{
      nodes: nodes,
      edges: edges,
      semesters:
        semesters
        |> Enum.with_index()
        |> Enum.map(fn {semester, column} ->
          %{
            number: semester.number,
            x: @margin + column * (@node_width + @column_gap) + div(@node_width, 2)
          }
        end),
      node_width: @node_width,
      node_height: @node_height,
      width: @margin * 2 + max(length(semesters), 1) * (@node_width + @column_gap) - @column_gap,
      height: @margin * 2 + 24 + tallest * (@node_height + @row_gap)
    }
  end

  defp overlay_marks({:skill, skill_id}, _courses, data) do
    for link <- data.links,
        link["skill_id"] == skill_id,
        into: %{},
        do: {CourseCode.key(link), link["level"]}
  end

  defp overlay_marks({:abet, code}, courses, data) do
    case abet_rows(courses: courses, data: data) |> Enum.find(&(&1.outcome["code"] == code)) do
      nil ->
        %{}

      row ->
        for {key, cell} <- row.cells, cell.matrix != nil or cell.syllabus, into: %{} do
          {key, abet_mark(cell)}
        end
    end
  end

  defp overlay_marks(_none, _courses, _data), do: %{}

  def abet_mark(%{matrix: :covered}), do: "covered"
  def abet_mark(%{matrix: :tentative}), do: "tentative"
  def abet_mark(%{syllabus: true}), do: "syllabus_only"
  def abet_mark(_cell), do: nil

  defp edge_path(kind, from, to) do
    {x1, y1, x2, y2} =
      if from.x == to.x do
        {from.x + @node_width, from.y + div(@node_height, 2), to.x + @node_width,
         to.y + div(@node_height, 2)}
      else
        {from.x + @node_width, from.y + div(@node_height, 2), to.x, to.y + div(@node_height, 2)}
      end

    bend = if from.x == to.x, do: 40, else: div(abs(x2 - x1), 2)
    control_x2 = if from.x == to.x, do: x2 + bend, else: x2 - bend

    %{
      kind: kind,
      from: from.key,
      to: to.key,
      path: "M #{x1} #{y1} C #{x1 + bend} #{y1}, #{control_x2} #{y2}, #{x2} #{y2}"
    }
  end

  def outcome_text(outcome),
    do: outcome["text"] |> MasterSyllabus.display_outcome() |> MasterSyllabus.without_abet_tag()

  def category_label("tool"), do: "Tools"
  def category_label("practice"), do: "Practices"
  def category_label("design"), do: "Design & architecture"
  def category_label("concept"), do: "Concepts"
  def category_label(other), do: other

  def level_letter("introduced"), do: "I"
  def level_letter("reinforced"), do: "R"
  def level_letter("mastered"), do: "M"
  def level_letter(_level), do: ""

  defp course_order(courses) do
    courses
    |> Enum.with_index()
    |> Map.new(fn {course, index} -> {CourseCode.key(course), index} end)
  end

  defp first_position(cells, order) do
    cells |> Map.keys() |> Enum.map(&order[&1]) |> Enum.min(fn -> nil end)
  end

  defp category_position(category), do: Enum.find_index(@category_order, &(&1 == category)) || 99
end
