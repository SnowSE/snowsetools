defmodule SnowSeTools.Curriculum.SuggestionDb do
  @moduledoc """
  AI review runs and the suggestions they leave for an editor to accept or
  reject.

  A suggestion's `fingerprint` names what it proposes ("course_skill|SE|3820|
  git (command line)|reinforced"), so a later run can skip anything an editor
  already rejected instead of asking the same question every time.
  """

  alias SnowSeTools.Data.DbHelpers

  @run_columns """
  id, program_id, status, started_by, total_courses, finished_courses, notes, error,
  to_char(started_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS started_at,
  to_char(finished_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS finished_at
  """

  @suggestion_columns """
  id, run_id, kind, subject_code, course_number, payload, fingerprint, rationale, evidence,
  status, decided_by,
  to_char(inserted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inserted_at
  """

  def create_run(program_id: program_id, started_by: started_by, total_courses: total) do
    sql = """
    INSERT INTO curriculum_runs (program_id, started_by, total_courses)
    VALUES ($(program_id), $(started_by), $(total))
    RETURNING #{@run_columns}
    """

    case DbHelpers.query(sql, %{
           "program_id" => program_id,
           "started_by" => started_by,
           "total" => total
         }) do
      {:ok, [run]} -> {:ok, run}
      {:error, reason} -> {:error, reason}
    end
  end

  def latest_run do
    case DbHelpers.query(
           "SELECT #{@run_columns} FROM curriculum_runs ORDER BY curriculum_runs.started_at DESC LIMIT 1",
           %{}
         ) do
      {:ok, [run]} -> {:ok, run}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_run(run_id: run_id, changes: changes) when is_map(changes) do
    sql = """
    UPDATE curriculum_runs SET
      finished_courses = COALESCE($(finished_courses), finished_courses),
      notes = COALESCE($(notes)::jsonb, notes),
      status = COALESCE($(status), status),
      error = COALESCE($(error), error),
      finished_at = CASE WHEN $(status) IN ('completed', 'error') THEN NOW() ELSE finished_at END
    WHERE id = $(id)
    RETURNING #{@run_columns}
    """

    params = %{
      "id" => run_id,
      "finished_courses" => changes[:finished_courses],
      "notes" => changes[:notes],
      "status" => changes[:status],
      "error" => changes[:error]
    }

    case DbHelpers.query(sql, params) do
      {:ok, [run]} -> {:ok, run}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retires what earlier runs left undecided: a new run looks at the same
  material again, so its suggestions replace theirs.
  """
  def supersede_pending(except_run_id: run_id) do
    sql = """
    UPDATE curriculum_suggestions
    SET status = 'superseded'
    WHERE status = 'pending' AND run_id <> $(run_id)
    """

    case DbHelpers.query(sql, %{"run_id" => run_id}) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def insert_suggestion(run_id: run_id, suggestion: suggestion) do
    sql = """
    INSERT INTO curriculum_suggestions
      (run_id, kind, subject_code, course_number, payload, fingerprint, rationale, evidence)
    VALUES
      ($(run_id), $(kind), $(subject_code), $(course_number), $(payload), $(fingerprint),
       $(rationale), $(evidence))
    """

    params = %{
      "run_id" => run_id,
      "kind" => suggestion["kind"],
      "subject_code" => suggestion["subject_code"],
      "course_number" => suggestion["course_number"],
      "payload" => suggestion["payload"],
      "fingerprint" => suggestion["fingerprint"],
      "rationale" => suggestion["rationale"] || "",
      "evidence" => suggestion["evidence"] || ""
    }

    case DbHelpers.query(sql, params) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def list_pending do
    sql = """
    SELECT #{@suggestion_columns}
    FROM curriculum_suggestions
    WHERE status = 'pending'
    ORDER BY subject_code NULLS LAST, course_number NULLS LAST, kind, curriculum_suggestions.inserted_at
    """

    DbHelpers.query(sql, %{})
  end

  def get_suggestion(id) do
    case DbHelpers.query(
           "SELECT #{@suggestion_columns} FROM curriculum_suggestions WHERE id = $(id)",
           %{"id" => id}
         ) do
      {:ok, [suggestion]} -> {:ok, suggestion}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def rejected_fingerprints do
    sql = "SELECT DISTINCT fingerprint FROM curriculum_suggestions WHERE status = 'rejected'"

    case DbHelpers.query(sql, %{}) do
      {:ok, rows} -> {:ok, MapSet.new(rows, & &1["fingerprint"])}
      {:error, reason} -> {:error, reason}
    end
  end

  def decide(id: id, status: status, decided_by: decided_by)
      when status in ["accepted", "rejected"] do
    sql = """
    UPDATE curriculum_suggestions
    SET status = $(status), decided_by = $(decided_by), decided_at = NOW()
    WHERE id = $(id) AND status = 'pending'
    RETURNING id
    """

    case DbHelpers.query(sql, %{"id" => id, "status" => status, "decided_by" => decided_by}) do
      {:ok, [_row]} -> :ok
      {:ok, []} -> {:error, "That suggestion was already decided."}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_payload(id: id, payload: payload, fingerprint: fingerprint) do
    sql = """
    UPDATE curriculum_suggestions SET payload = $(payload), fingerprint = $(fingerprint)
    WHERE id = $(id)
    """

    case DbHelpers.query(sql, %{"id" => id, "payload" => payload, "fingerprint" => fingerprint}) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def mark_superseded(id) do
    sql =
      "UPDATE curriculum_suggestions SET status = 'superseded' WHERE id = $(id) AND status = 'pending'"

    case DbHelpers.query(sql, %{"id" => id}) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
