defmodule SnowSeTools.Curriculum.SuggestionBuilderTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Curriculum.{FacultyMaterials, SuggestionBuilder}

  @git %{
    "id" => "git-id",
    "name" => "Git (command line)",
    "category" => "tool",
    "description" => "git"
  }
  @cli %{
    "id" => "cli-id",
    "name" => "Command line",
    "category" => "tool",
    "description" => "shell"
  }
  @course %{"subject_code" => "SE", "course_number" => "3820"}

  defp state(overrides \\ %{}) do
    Map.merge(
      %{
        skills: [@git, @cli],
        links: [
          %{
            "subject_code" => "SE",
            "course_number" => "3820",
            "skill_id" => "git-id",
            "level" => "reinforced"
          }
        ],
        dependencies: [%{"skill_id" => "git-id", "builds_on_skill_id" => "cli-id"}],
        rejected: MapSet.new()
      },
      overrides
    )
  end

  defp skill(name, level, extra \\ %{}) do
    Map.merge(
      %{
        "name" => name,
        "is_new" => false,
        "category" => "tool",
        "description" => "",
        "level" => level,
        "evidence" => "modules/git.md",
        "source" => "faculty_materials"
      },
      extra
    )
  end

  test "suggests links for known and new skills, under the catalog's own names" do
    answer = %{
      "skills" => [
        skill("command LINE", "reinforced"),
        skill("Docker Compose", "introduced", %{
          "is_new" => true,
          "description" => "Multi-container apps."
        })
      ],
      "builds_on" => []
    }

    [cli, docker] =
      SuggestionBuilder.from_course_review(answer: answer, course: @course, state: state())

    assert cli["payload"]["skill_name"] == "Command line"
    assert cli["payload"]["skill_id"] == "cli-id"
    assert cli["fingerprint"] == "course_skill|SE|3820|command line|reinforced"

    assert docker["payload"]["skill_id"] == nil
    assert docker["payload"]["description"] == "Multi-container apps."
    assert docker["evidence"] == "modules/git.md"
  end

  test "skips what the map already says and what an editor rejected" do
    answer = %{
      "skills" => [skill("Git (command line)", "reinforced"), skill("Command line", "mastered")],
      "builds_on" => []
    }

    rejected = MapSet.new(["course_skill|SE|3820|command line|mastered"])

    assert SuggestionBuilder.from_course_review(
             answer: answer,
             course: @course,
             state: state(%{rejected: rejected})
           ) ==
             []
  end

  test "a different level for an existing link is a suggestion that names the current level" do
    answer = %{"skills" => [skill("Git (command line)", "mastered")], "builds_on" => []}

    assert [%{"payload" => %{"level" => "mastered", "current_level" => "reinforced"}}] =
             SuggestionBuilder.from_course_review(answer: answer, course: @course, state: state())
  end

  test "builds-on pairs must name known or proposed skills and not be drawn already" do
    answer = %{
      "skills" => [skill("GitHub Actions", "introduced", %{"is_new" => true})],
      "builds_on" => [
        %{
          "skill" => "GitHub Actions",
          "builds_on" => "git (command line)",
          "rationale" => "CI runs on pushes"
        },
        %{
          "skill" => "Git (command line)",
          "builds_on" => "Command line",
          "rationale" => "already drawn"
        },
        %{
          "skill" => "Kubernetes",
          "builds_on" => "Command line",
          "rationale" => "never proposed"
        },
        %{"skill" => "Command line", "builds_on" => "command line", "rationale" => "itself"}
      ]
    }

    dependencies =
      answer
      |> then(&SuggestionBuilder.from_course_review(answer: &1, course: @course, state: state()))
      |> Enum.filter(&(&1["kind"] == "skill_dependency"))

    assert [
             %{
               "payload" => %{
                 "skill_name" => "GitHub Actions",
                 "builds_on_name" => "Git (command line)"
               }
             }
           ] = dependencies
  end

  test "ignores malformed answers instead of failing the run" do
    assert SuggestionBuilder.from_course_review(answer: %{}, course: @course, state: state()) ==
             []

    assert SuggestionBuilder.from_course_review(
             answer: "not json",
             course: @course,
             state: state()
           ) == []

    answer = %{
      "skills" => [
        %{"name" => "  ", "level" => "introduced"},
        %{"name" => "Thing", "level" => "expert"},
        "x"
      ]
    }

    assert SuggestionBuilder.from_course_review(answer: answer, course: @course, state: state()) ==
             []
  end

  test "merge suggestions only pair names the run knows" do
    answer = %{
      "merges" => [
        %{"keep" => "Git (command line)", "merge" => "Git CLI", "rationale" => "same"},
        %{"keep" => "Git (command line)", "merge" => "Invented Name", "rationale" => "unknown"},
        %{"keep" => "Git CLI", "merge" => "git cli", "rationale" => "itself"}
      ]
    }

    assert [%{"payload" => %{"keep_name" => "Git (command line)", "merge_name" => "Git CLI"}}] =
             SuggestionBuilder.from_merge_review(
               answer: answer,
               proposed_names: ["Git CLI"],
               state: state()
             )
  end

  describe "FacultyMaterials.select_files/1" do
    defp blob(path, size \\ 100),
      do: %{"type" => "blob", "path" => path, "size" => size, "sha" => path}

    defp dir(path), do: %{"type" => "tree", "path" => path}

    test "reads markdown from the course's three newest terms, plans first" do
      tree = [
        dir("3820_BackEnd"),
        dir("3820_BackEnd/2024-fall"),
        dir("3820_BackEnd/2025-fall"),
        dir("3820_BackEnd/2026-spring-alex"),
        dir("3820_BackEnd/2026-fall-dallan"),
        dir("3820_BackEnd/notes"),
        dir("1400_engr/2026-fall"),
        blob("3820_BackEnd/2024-fall/old.md"),
        blob("3820_BackEnd/2025-fall/modules/lecture.md"),
        blob("3820_BackEnd/2026-fall-dallan/course-plan.md"),
        blob("3820_BackEnd/2026-fall-dallan/modules/M1/assignment.md"),
        blob("3820_BackEnd/2026-fall-dallan/diagram.png"),
        blob("3820_BackEnd/2026-fall-dallan/huge.md", 900_000),
        blob("3820_BackEnd/2026-spring-alex/README.md"),
        blob("3820_BackEnd/notes/ideas.md")
      ]

      paths =
        [tree: tree, course_number: "3820"]
        |> FacultyMaterials.select_files()
        |> Enum.map(& &1["path"])

      assert paths == [
               "3820_BackEnd/2026-fall-dallan/course-plan.md",
               "3820_BackEnd/2026-spring-alex/README.md",
               "3820_BackEnd/2025-fall/modules/lecture.md",
               "3820_BackEnd/2026-fall-dallan/modules/M1/assignment.md"
             ]
    end

    test "does not mistake another department's copy of a course number for ours" do
      tree = [dir("1400_engr"), dir("1400_engr/2026-fall"), blob("1400_engr/2026-fall/plan.md")]
      assert FacultyMaterials.select_files(tree: tree, course_number: "1400") == []
    end
  end
end
