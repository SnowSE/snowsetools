defmodule SnowSeTools.Curriculum.SkillReviewPrompt do
  @moduledoc """
  The two questions a review run asks the model.

  Per course: "which skills does this course have students practice, and at
  what level?", given the course's sources, the skill catalog, and where the
  courses before it already touch each skill (which is what separates
  *introduced* from *reinforced*).

  Once per run: "which of these skills are the same skill under two names?",
  over the catalog plus every new name the course reviews proposed.
  """

  alias SnowSeTools.Curriculum.{CourseCode, CurriculumDb, MasterSyllabus}

  @course_schema %{
    "type" => "object",
    "properties" => %{
      "skills" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "is_new" => %{"type" => "boolean"},
            "category" => %{"type" => "string", "enum" => CurriculumDb.skill_categories()},
            "description" => %{"type" => "string"},
            "level" => %{"type" => "string", "enum" => CurriculumDb.levels()},
            "evidence" => %{"type" => "string"},
            "source" => %{
              "type" => "string",
              "enum" => ["master_syllabus", "faculty_materials", "section_syllabi"]
            }
          },
          "required" => [
            "name",
            "is_new",
            "category",
            "description",
            "level",
            "evidence",
            "source"
          ],
          "additionalProperties" => false
        }
      },
      "builds_on" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "skill" => %{"type" => "string"},
            "builds_on" => %{"type" => "string"},
            "rationale" => %{"type" => "string"}
          },
          "required" => ["skill", "builds_on", "rationale"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["skills", "builds_on"],
    "additionalProperties" => false
  }

  @merge_schema %{
    "type" => "object",
    "properties" => %{
      "merges" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "keep" => %{"type" => "string"},
            "merge" => %{"type" => "string"},
            "rationale" => %{"type" => "string"}
          },
          "required" => ["keep", "merge", "rationale"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["merges"],
    "additionalProperties" => false
  }

  def course_schema, do: @course_schema
  def merge_schema, do: @merge_schema

  @doc """
  Messages for one course. `context` carries:

    * `:course` — `%{"subject_code", "course_number", "title"}`
    * `:program_courses` — every course in program order, same shape plus `"semester"`
    * `:skills` — the catalog
    * `:links` — every course–skill link (`"subject_code"`, `"course_number"`, `"skill_id"`, `"level"`)
    * `:master_syllabus` — the stored master syllabus, or nil
    * `:outcomes` — the course's current outcomes
    * `:faculty_text`, `:section_text` — source text, possibly empty
  """
  def course_messages(context) do
    course = context.course
    course_key = CourseCode.key(course)
    order = Enum.map(context.program_courses, &CourseCode.key/1)
    earlier = Enum.take_while(order, &(&1 != course_key)) |> MapSet.new()
    skill_names = Map.new(context.skills, &{&1["id"], &1["name"]})

    system = """
    You build a curriculum map for a university Software Engineering program. For one course you list the concrete skills students practice in it, so faculty can see where each skill is introduced, where it is reinforced, and where students are expected to master it.

    Rules:
    - A skill is something a student can do: a tool (the command line, Git from the command line, GitHub, the .NET SDK CLI, VS Code, Visual Studio), a practice (unit testing, TDD, BDD, code review), a design or architecture technique (dependency injection, mocks & fakes, DDD, onion architecture), or a concept they apply (recursion, SQL joins, HTTP). Prefer specific skills over broad topics: "Git (command line)", not "version control concepts"; never "software engineering".
    - When a skill in the catalog is the same skill, use its catalog name exactly and set is_new to false. Only propose a new name (is_new true) when nothing in the catalog fits, and give it a one-sentence description.
    - level: "introduced" when this course is where students first learn it; "reinforced" when they use or deepen a skill met before; "mastered" when the course expects independent, assessed, advanced use. Use the earlier-course links you are given: a skill an earlier course already introduced is not introduced again here.
    - Only list skills the sources show students actually practicing. evidence is a short quote or a file path from the sources; source says which source it came from.
    - List at most 25 skills, the most important first.
    - builds_on pairs say that one skill requires another (GitHub builds on Git (command line)). Only pairs where both skills appear in your list or in the catalog, and only real prerequisites.
    """

    user = """
    <course>#{CourseCode.label(course)} #{course["title"]}</course>

    <program_order>
    #{Enum.map_join(context.program_courses, "\n", fn c -> "Semester #{c["semester"]}: #{CourseCode.label(c)} #{c["title"]}" end)}
    </program_order>

    <skill_catalog>
    #{Enum.map_join(context.skills, "\n", fn s -> "- #{s["name"]} [#{s["category"]}]: #{s["description"]}" end)}
    </skill_catalog>

    <earlier_course_links>
    #{earlier_links(context.links, earlier, skill_names, context.program_courses)}
    </earlier_course_links>

    <current_links_for_this_course>
    #{current_links(context.links, course_key, skill_names)}
    </current_links_for_this_course>

    <master_syllabus>
    #{master_syllabus_text(context.master_syllabus, context.outcomes)}
    </master_syllabus>

    <faculty_materials>
    #{blank_as_none(context.faculty_text)}
    </faculty_materials>

    <section_syllabi>
    #{blank_as_none(context.section_text)}
    </section_syllabi>
    """

    [
      %{role: "system", content: String.trim(system)},
      %{role: "user", content: String.trim(user)}
    ]
  end

  @doc "Messages for the end-of-run pass that looks for one skill under two names."
  def merge_messages(skills: skills, proposed: proposed) do
    system = """
    You keep a skill catalog for a Software Engineering curriculum map free of duplicates. Given the catalog and newly proposed skill names, list pairs that are the same skill under two names, such as "Git CLI" and "Git (command line)", or "TDD" and "Test-driven development (TDD)".

    Rules:
    - keep is the name to keep: prefer the catalog name, else the clearer name. merge is the duplicate.
    - Only pairs that really are one skill. Related but distinct skills (Git and GitHub, unit testing and TDD) are not duplicates.
    - Both names must appear exactly as written below.
    """

    user = """
    <skill_catalog>
    #{Enum.map_join(skills, "\n", fn s -> "- #{s["name"]}: #{s["description"]}" end)}
    </skill_catalog>

    <proposed_skills>
    #{Enum.map_join(proposed, "\n", fn s -> "- #{s["name"]}: #{s["description"]}" end)}
    </proposed_skills>
    """

    [
      %{role: "system", content: String.trim(system)},
      %{role: "user", content: String.trim(user)}
    ]
  end

  defp earlier_links(links, earlier, skill_names, program_courses) do
    position =
      program_courses |> Enum.with_index() |> Map.new(fn {c, i} -> {CourseCode.key(c), i} end)

    links
    |> Enum.filter(&MapSet.member?(earlier, CourseCode.key(&1)))
    |> Enum.group_by(& &1["skill_id"])
    |> Enum.map(fn {skill_id, skill_links} ->
      courses =
        skill_links
        |> Enum.sort_by(&position[CourseCode.key(&1)])
        |> Enum.map_join(", ", &"#{CourseCode.label(&1)} #{&1["level"]}")

      "- #{skill_names[skill_id]}: #{courses}"
    end)
    |> Enum.sort()
    |> Enum.join("\n")
    |> blank_as_none()
  end

  defp current_links(links, course_key, skill_names) do
    links
    |> Enum.filter(&(CourseCode.key(&1) == course_key))
    |> Enum.map(&"- #{skill_names[&1["skill_id"]]}: #{&1["level"]}")
    |> Enum.sort()
    |> Enum.join("\n")
    |> blank_as_none()
  end

  defp master_syllabus_text(nil, _outcomes), do: "(none on file)"

  defp master_syllabus_text(syllabus, outcomes) do
    """
    Description: #{syllabus["description"]}
    Prerequisites: #{syllabus["prerequisites"]}
    Learning outcomes:
    #{Enum.map_join(outcomes, "\n", &"- #{MasterSyllabus.display_outcome(&1["text"])}")}
    Course content: #{syllabus["content"]}
    """
  end

  defp blank_as_none(text) when text in [nil, ""], do: "(none)"
  defp blank_as_none(text), do: text
end
