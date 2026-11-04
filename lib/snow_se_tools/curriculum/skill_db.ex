defmodule SnowSeTools.Curriculum.SkillDb do
  @moduledoc """
  The skill catalog, the "builds on" graph between skills, and the
  introduced / reinforced / mastered links from courses to skills.
  """

  alias SnowSeTools.Curriculum.CurriculumDb
  alias SnowSeTools.Data.DbHelpers

  @skill_schema Zoi.object(%{
                  "id" => Zoi.uuid(),
                  "name" => Zoi.string(),
                  "category" => Zoi.string(),
                  "description" => Zoi.string()
                })

  @course_skill_schema Zoi.object(%{
                         "subject_code" => Zoi.string(),
                         "course_number" => Zoi.string(),
                         "skill_id" => Zoi.uuid(),
                         "level" => Zoi.string(),
                         "note" => Zoi.string()
                       })

  def list_skills do
    sql = """
    SELECT id, name, category, description
    FROM curriculum_skills
    ORDER BY lower(name)
    """

    DbHelpers.query(sql, %{}, @skill_schema)
  end

  def list_dependencies do
    sql = """
    SELECT skill_id, builds_on_skill_id
    FROM curriculum_skill_dependencies
    """

    DbHelpers.query(sql, %{})
  end

  def list_course_skills do
    sql = """
    SELECT subject_code, course_number, skill_id, level, note
    FROM curriculum_course_skills
    """

    DbHelpers.query(sql, %{}, @course_skill_schema)
  end

  def find_skill_by_name(name) when is_binary(name) do
    sql = """
    SELECT id, name, category, description
    FROM curriculum_skills
    WHERE lower(name) = lower($(name))
    """

    case DbHelpers.query(sql, %{"name" => String.trim(name)}, @skill_schema) do
      {:ok, [skill]} -> {:ok, skill}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_skill(name: name, category: category, description: description) do
    with {:ok, attrs} <- validate_skill(name: name, category: category, description: description) do
      sql = """
      INSERT INTO curriculum_skills (name, category, description)
      VALUES ($(name), $(category), $(description))
      RETURNING id, name, category, description
      """

      case DbHelpers.query(sql, attrs, @skill_schema) do
        {:ok, [skill]} -> {:ok, skill}
        {:error, :not_unique} -> {:error, "A skill named \"#{attrs["name"]}\" already exists."}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def update_skill(id: id, name: name, category: category, description: description) do
    with {:ok, attrs} <- validate_skill(name: name, category: category, description: description) do
      sql = """
      UPDATE curriculum_skills
      SET name = $(name), category = $(category), description = $(description), updated_at = NOW()
      WHERE id = $(id)
      RETURNING id, name, category, description
      """

      case DbHelpers.query(sql, Map.put(attrs, "id", id), @skill_schema) do
        {:ok, [skill]} -> {:ok, skill}
        {:ok, []} -> {:error, :not_found}
        {:error, :not_unique} -> {:error, "A skill named \"#{attrs["name"]}\" already exists."}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def delete_skill(id: id) do
    case DbHelpers.query("DELETE FROM curriculum_skills WHERE id = $(id)", %{"id" => id}) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Replaces everything `skill_id` builds on. Refuses a set that would make the
  graph circular, since "A builds on B builds on A" has no reading order.
  """
  def set_dependencies(skill_id: skill_id, builds_on_ids: builds_on_ids) do
    builds_on_ids = builds_on_ids |> Enum.uniq() |> Enum.reject(&(&1 == skill_id))

    DbHelpers.transaction(fn ->
      with {:ok, _rows} <-
             DbHelpers.query(
               "DELETE FROM curriculum_skill_dependencies WHERE skill_id = $(skill_id)",
               %{"skill_id" => skill_id}
             ) do
        Enum.reduce_while(builds_on_ids, :ok, fn builds_on_id, :ok ->
          case add_dependency(skill_id: skill_id, builds_on_skill_id: builds_on_id) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end
    end)
  end

  def add_dependency(skill_id: skill_id, builds_on_skill_id: builds_on_id) do
    if skill_id == builds_on_id do
      {:error, "A skill cannot build on itself."}
    else
      case reaches?(from: builds_on_id, to: skill_id) do
        {:ok, true} ->
          {:error, "That link would make the skill graph circular."}

        {:ok, false} ->
          sql = """
          INSERT INTO curriculum_skill_dependencies (skill_id, builds_on_skill_id)
          VALUES ($(skill_id), $(builds_on_id))
          ON CONFLICT DO NOTHING
          """

          case DbHelpers.query(sql, %{"skill_id" => skill_id, "builds_on_id" => builds_on_id}) do
            {:ok, _rows} -> :ok
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp reaches?(from: from, to: to) do
    sql = """
    WITH RECURSIVE ancestors(id) AS (
      SELECT builds_on_skill_id FROM curriculum_skill_dependencies WHERE skill_id = $(from)
      UNION
      SELECT d.builds_on_skill_id
      FROM curriculum_skill_dependencies d
      JOIN ancestors a ON d.skill_id = a.id
    )
    SELECT EXISTS (SELECT 1 FROM ancestors WHERE id = $(to)) AS reaches
    """

    case DbHelpers.query(sql, %{"from" => from, "to" => to}) do
      {:ok, [%{"reaches" => reaches}]} -> {:ok, reaches}
      {:error, reason} -> {:error, reason}
    end
  end

  def set_course_skill(
        subject_code: subject_code,
        course_number: course_number,
        skill_id: skill_id,
        level: level,
        note: note,
        updated_by: updated_by
      ) do
    if level in CurriculumDb.levels() do
      sql = """
      INSERT INTO curriculum_course_skills
        (subject_code, course_number, skill_id, level, note, updated_by)
      VALUES ($(subject_code), $(course_number), $(skill_id), $(level), $(note), $(updated_by))
      ON CONFLICT (subject_code, course_number, skill_id) DO UPDATE SET
        level = EXCLUDED.level,
        note = EXCLUDED.note,
        updated_by = EXCLUDED.updated_by,
        updated_at = NOW()
      """

      params = %{
        "subject_code" => subject_code,
        "course_number" => course_number,
        "skill_id" => skill_id,
        "level" => level,
        "note" => String.trim(note || ""),
        "updated_by" => updated_by
      }

      case DbHelpers.query(sql, params) do
        {:ok, _rows} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "Unknown level #{inspect(level)}."}
    end
  end

  def remove_course_skill(
        subject_code: subject_code,
        course_number: course_number,
        skill_id: skill_id
      ) do
    sql = """
    DELETE FROM curriculum_course_skills
    WHERE subject_code = $(subject_code) AND course_number = $(course_number) AND skill_id = $(skill_id)
    """

    params = %{
      "subject_code" => subject_code,
      "course_number" => course_number,
      "skill_id" => skill_id
    }

    case DbHelpers.query(sql, params) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Folds `merge_id` into `keep_id`: its course links and graph edges move over
  (where `keep_id` already has a link to the same course, that link wins), then
  the merged skill is deleted.
  """
  def merge_skills(keep_id: keep_id, merge_id: merge_id) when keep_id != merge_id do
    params = %{"keep_id" => keep_id, "merge_id" => merge_id}

    statements = [
      """
      INSERT INTO curriculum_course_skills
        (subject_code, course_number, skill_id, level, note, updated_by)
      SELECT subject_code, course_number, $(keep_id), level, note, updated_by
      FROM curriculum_course_skills
      WHERE skill_id = $(merge_id)
      ON CONFLICT (subject_code, course_number, skill_id) DO NOTHING
      """,
      """
      INSERT INTO curriculum_skill_dependencies (skill_id, builds_on_skill_id)
      SELECT $(keep_id), builds_on_skill_id
      FROM curriculum_skill_dependencies
      WHERE skill_id = $(merge_id) AND builds_on_skill_id <> $(keep_id)
      ON CONFLICT DO NOTHING
      """,
      """
      INSERT INTO curriculum_skill_dependencies (skill_id, builds_on_skill_id)
      SELECT skill_id, $(keep_id)
      FROM curriculum_skill_dependencies
      WHERE builds_on_skill_id = $(merge_id) AND skill_id <> $(keep_id)
      ON CONFLICT DO NOTHING
      """,
      "DELETE FROM curriculum_skills WHERE id = $(merge_id)"
    ]

    DbHelpers.transaction(fn ->
      Enum.reduce_while(statements, :ok, fn sql, :ok ->
        case DbHelpers.query(sql, params) do
          {:ok, _rows} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end)
  end

  def merge_skills(keep_id: same, merge_id: same) when is_binary(same),
    do: {:error, "Cannot merge a skill into itself."}

  defp validate_skill(name: name, category: category, description: description) do
    name = String.trim(name || "")

    cond do
      name == "" ->
        {:error, "Skill name is required."}

      category not in CurriculumDb.skill_categories() ->
        {:error, "Unknown skill category #{inspect(category)}."}

      true ->
        {:ok,
         %{
           "name" => name,
           "category" => category,
           "description" => String.trim(description || "")
         }}
    end
  end
end
