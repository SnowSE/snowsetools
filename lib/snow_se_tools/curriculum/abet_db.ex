defmodule SnowSeTools.Curriculum.AbetDb do
  @moduledoc """
  ABET student outcomes and program criteria, which courses the department's
  matrix says cover them, and when that matrix was last imported.
  """

  alias SnowSeTools.Data.DbHelpers

  def list_outcomes do
    sql = """
    SELECT id, code, kind, number, title, position
    FROM curriculum_abet_outcomes
    ORDER BY position, code
    """

    DbHelpers.query(sql, %{})
  end

  def list_coverage do
    sql = """
    SELECT c.subject_code, c.course_number, c.tentative, o.code
    FROM curriculum_course_abet c
    JOIN curriculum_abet_outcomes o ON o.id = c.abet_outcome_id
    """

    DbHelpers.query(sql, %{})
  end

  def last_import do
    sql = """
    SELECT file_name, slo_sheet, criteria_sheet, imported_by,
      to_char(imported_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS imported_at
    FROM curriculum_abet_imports
    ORDER BY curriculum_abet_imports.imported_at DESC
    LIMIT 1
    """

    case DbHelpers.query(sql, %{}) do
      {:ok, [import]} -> {:ok, import}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Replaces the matrix with the one just read. Outcome titles are updated in
  place so their ids (and anything pointing at them) survive; program
  criteria the new matrix no longer lists are removed.
  """
  def import_matrix(matrix: %{outcomes: outcomes, coverage: coverage}, meta: meta) do
    DbHelpers.transaction(fn ->
      with :ok <- upsert_outcomes(outcomes),
           :ok <- remove_dropped_criteria(outcomes),
           {:ok, _rows} <- DbHelpers.query("DELETE FROM curriculum_course_abet", %{}),
           :ok <- insert_coverage(coverage),
           {:ok, _rows} <- record_import(meta) do
        {:ok, %{outcomes: length(outcomes), coverage: length(coverage)}}
      end
    end)
  end

  defp upsert_outcomes(outcomes) do
    sql = """
    INSERT INTO curriculum_abet_outcomes (code, kind, number, title, position)
    VALUES ($(code), $(kind), $(number), $(title), $(position))
    ON CONFLICT (code) DO UPDATE SET
      kind = EXCLUDED.kind,
      number = EXCLUDED.number,
      title = EXCLUDED.title,
      position = EXCLUDED.position,
      updated_at = NOW()
    """

    each_query(outcomes, sql, fn outcome ->
      %{
        "code" => outcome.code,
        "kind" => outcome.kind,
        "number" => outcome.number,
        "title" => outcome.title,
        "position" => outcome.position
      }
    end)
  end

  defp remove_dropped_criteria(outcomes) do
    sql = """
    DELETE FROM curriculum_abet_outcomes
    WHERE kind = 'criterion' AND NOT (code = ANY($(codes)::text[]))
    """

    case DbHelpers.query(sql, %{"codes" => Enum.map(outcomes, & &1.code)}) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_coverage(coverage) do
    sql = """
    INSERT INTO curriculum_course_abet (subject_code, course_number, abet_outcome_id, tentative)
    SELECT $(subject_code), $(course_number), id, $(tentative)
    FROM curriculum_abet_outcomes
    WHERE code = $(code)
    ON CONFLICT DO NOTHING
    """

    each_query(coverage, sql, fn row ->
      %{
        "subject_code" => row.subject_code,
        "course_number" => row.course_number,
        "tentative" => row.tentative,
        "code" => row.code
      }
    end)
  end

  defp record_import(meta) do
    sql = """
    INSERT INTO curriculum_abet_imports (file_name, slo_sheet, criteria_sheet, imported_by)
    VALUES ($(file_name), $(slo_sheet), $(criteria_sheet), $(imported_by))
    """

    DbHelpers.query(sql, %{
      "file_name" => meta.file_name,
      "slo_sheet" => meta.slo_sheet,
      "criteria_sheet" => meta.criteria_sheet,
      "imported_by" => meta.imported_by
    })
  end

  defp each_query(items, sql, params_fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case DbHelpers.query(sql, params_fun.(item)) do
        {:ok, _rows} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
