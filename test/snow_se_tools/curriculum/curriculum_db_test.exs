defmodule SnowSeTools.Curriculum.CurriculumDbTest do
  @moduledoc """
  The curriculum tables against a real database. The suite shares one
  database, so every skill and course here carries a unique name or number.
  """
  use ExUnit.Case, async: false

  alias SnowSeTools.Curriculum.{
    CurriculumDomainManager,
    OutcomeDb,
    SkillDb,
    SuggestionDb,
    SuggestionDecisions
  }

  setup do
    start_supervised!(CurriculumDomainManager)
    :ok
  end

  defp unique, do: System.unique_integer([:positive])

  defp skill!(name) do
    {:ok, skill} =
      SkillDb.create_skill(name: "#{name} #{unique()}", category: "practice", description: "")

    skill
  end

  defp course_number, do: Integer.to_string(5000 + rem(unique(), 4000))

  test "seeds the catalog the department asked for" do
    assert {:ok, %{"category" => "tool"}} = SkillDb.find_skill_by_name("git (COMMAND LINE)")
    assert {:ok, _skill} = SkillDb.find_skill_by_name("Onion architecture")
  end

  test "skill names are unique regardless of case" do
    name = "Pairing #{unique()}"
    assert {:ok, _skill} = SkillDb.create_skill(name: name, category: "practice", description: "")

    assert {:error, message} =
             SkillDb.create_skill(
               name: String.upcase(name),
               category: "practice",
               description: ""
             )

    assert message =~ "already exists"
  end

  test "refuses a builds-on link that would make the graph circular" do
    a = skill!("A")
    b = skill!("B")
    c = skill!("C")

    assert :ok = SkillDb.add_dependency(skill_id: a["id"], builds_on_skill_id: b["id"])
    assert :ok = SkillDb.add_dependency(skill_id: b["id"], builds_on_skill_id: c["id"])

    assert {:error, message} =
             SkillDb.add_dependency(skill_id: c["id"], builds_on_skill_id: a["id"])

    assert message =~ "circular"
  end

  test "merging moves links and edges to the kept skill and removes the duplicate" do
    keep = skill!("Keep")
    duplicate = skill!("Duplicate")
    base = skill!("Base")
    number = course_number()

    :ok = SkillDb.add_dependency(skill_id: duplicate["id"], builds_on_skill_id: base["id"])

    :ok =
      SkillDb.set_course_skill(
        subject_code: "QA",
        course_number: number,
        skill_id: duplicate["id"],
        level: "introduced",
        note: "",
        updated_by: "test"
      )

    assert :ok = SkillDb.merge_skills(keep_id: keep["id"], merge_id: duplicate["id"])

    {:ok, links} = SkillDb.list_course_skills()
    assert Enum.any?(links, &(&1["skill_id"] == keep["id"] and &1["course_number"] == number))
    refute Enum.any?(links, &(&1["skill_id"] == duplicate["id"]))

    {:ok, dependencies} = SkillDb.list_dependencies()

    assert %{"skill_id" => _, "builds_on_skill_id" => _} =
             Enum.find(dependencies, &(&1["skill_id"] == keep["id"]))

    assert {:error, :not_found} = SkillDb.find_skill_by_name(duplicate["name"])
  end

  test "re-reading a master syllabus adds new outcomes and retires dropped ones" do
    number = course_number()

    first = %{
      "title" => "QA #{number} Testing",
      "outcomes" => ["Write unit tests.", "Use a debugger. (ABET SLO 1)"]
    }

    second = %{
      "title" => "QA #{number} Testing",
      "outcomes" => ["Use a  debugger. (ABET SLO 1)", "Practice TDD."]
    }

    assert {:ok, %{added: 2, retired: 0}} =
             OutcomeDb.save_master_syllabus(
               subject_code: "QA",
               course_number: number,
               syllabus: first
             )

    assert {:ok, %{added: 1, retired: 1}} =
             OutcomeDb.save_master_syllabus(
               subject_code: "QA",
               course_number: number,
               syllabus: second
             )

    {:ok, outcomes} = OutcomeDb.list_outcomes()
    mine = Enum.filter(outcomes, &(&1["course_number"] == number))

    assert %{"retired_at" => retired_at} = Enum.find(mine, &(&1["text"] == "Write unit tests."))
    assert retired_at != nil

    assert %{"added_since_first_read" => true, "abet_slos" => []} =
             Enum.find(mine, &(&1["text"] == "Practice TDD."))

    assert %{"added_since_first_read" => false, "abet_slos" => [1]} =
             Enum.find(mine, &(&1["text"] =~ "debugger"))
  end

  describe "accepting suggestions" do
    setup do
      {:ok, run} = SuggestionDb.create_run(program_id: nil, started_by: "test", total_courses: 1)
      {:ok, run: run}
    end

    defp suggest!(run, suggestion) do
      :ok = SuggestionDb.insert_suggestion(run_id: run["id"], suggestion: suggestion)
      {:ok, pending} = SuggestionDb.list_pending()
      Enum.find(pending, &(&1["fingerprint"] == suggestion["fingerprint"]))
    end

    defp course_skill(number, name, level) do
      %{
        "kind" => "course_skill",
        "subject_code" => "QA",
        "course_number" => number,
        "payload" => %{
          "skill_name" => name,
          "skill_id" => nil,
          "category" => "tool",
          "description" => "d",
          "level" => level
        },
        "fingerprint" => "course_skill|QA|#{number}|#{String.downcase(name)}|#{level}",
        "evidence" => "plan.md"
      }
    end

    test "a new skill is created along with its link, at the editor's level", %{run: run} do
      number = course_number()
      name = "Container builds #{unique()}"
      suggestion = suggest!(run, course_skill(number, name, "introduced"))

      assert :ok =
               SuggestionDecisions.accept(
                 suggestion: suggestion,
                 decided_by: "editor@snow.edu",
                 level: "reinforced"
               )

      {:ok, skill} = SkillDb.find_skill_by_name(name)
      {:ok, links} = SkillDb.list_course_skills()

      assert %{"level" => "reinforced", "note" => "plan.md"} =
               Enum.find(
                 links,
                 &(&1["skill_id"] == skill["id"] and &1["course_number"] == number)
               )

      assert {:error, _already} =
               SuggestionDecisions.accept(
                 suggestion: suggestion,
                 decided_by: "editor@snow.edu",
                 level: nil
               )
    end

    test "merging a proposed name renames it in the other waiting suggestions", %{run: run} do
      number = course_number()
      tag = unique()
      waiting = suggest!(run, course_skill(number, "Git CLI #{tag}", "introduced"))

      merge =
        suggest!(run, %{
          "kind" => "merge_skills",
          "subject_code" => nil,
          "course_number" => nil,
          "payload" => %{"keep_name" => "Git (command line)", "merge_name" => "Git CLI #{tag}"},
          "fingerprint" => "merge_skills|git (command line)|git cli #{tag}"
        })

      assert :ok =
               SuggestionDecisions.accept(
                 suggestion: merge,
                 decided_by: "editor@snow.edu",
                 level: nil
               )

      {:ok, renamed} = SuggestionDb.get_suggestion(waiting["id"])
      assert renamed["payload"]["skill_name"] == "Git (command line)"
      assert renamed["fingerprint"] == "course_skill|QA|#{number}|git (command line)|introduced"
    end

    test "a builds-on link waits for both skills to exist", %{run: run} do
      tag = unique()

      suggestion =
        suggest!(run, %{
          "kind" => "skill_dependency",
          "subject_code" => nil,
          "course_number" => nil,
          "payload" => %{"skill_name" => "Not yet #{tag}", "builds_on_name" => "Command line"},
          "fingerprint" => "skill_dependency|not yet #{tag}|command line"
        })

      assert {:error, message} =
               SuggestionDecisions.accept(
                 suggestion: suggestion,
                 decided_by: "editor@snow.edu",
                 level: nil
               )

      assert message =~ "first"
      assert {:ok, %{"status" => "pending"}} = SuggestionDb.get_suggestion(suggestion["id"])
    end
  end
end
