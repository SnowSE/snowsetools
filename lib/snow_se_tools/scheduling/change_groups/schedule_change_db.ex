defmodule SnowSeTools.Scheduling.ScheduleChangeDb do
  alias SnowSeTools.Data.{DbHelpers, Uuid}

  @group_schema Zoi.object(%{
                  "id" => Zoi.uuid(),
                  "name" => Zoi.string(),
                  "created_at" => Zoi.string(),
                  "inserted_at" => Zoi.string()
                })

  @change_schema Zoi.object(%{
                   "id" => Zoi.uuid(),
                   "group_id" => Zoi.uuid(),
                   "crn" => Zoi.string(),
                   "term" => Zoi.string(),
                   "subject_code" => Zoi.string(),
                   "course_number" => Zoi.string(),
                   "course_name" => Zoi.optional(Zoi.string()),
                   "target_professor" => Zoi.optional(Zoi.string()),
                   "meet_info" => Zoi.optional(Zoi.any()),
                   "operation" => Zoi.string(),
                   "created_at" => Zoi.string(),
                   "inserted_at" => Zoi.string()
                 })

  def bootstrap_tables do
    statements = [
      """
      CREATE TABLE IF NOT EXISTS schedule_change_groups (
        id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        name        TEXT        NOT NULL,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
        inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS schedule_changes (
        id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        group_id          UUID        NOT NULL REFERENCES schedule_change_groups(id) ON DELETE CASCADE,
        crn               TEXT        NOT NULL,
        term              TEXT        NOT NULL,
        subject_code      TEXT        NOT NULL,
        course_number     TEXT        NOT NULL,
        course_name       TEXT,
        target_professor TEXT,
        meet_info         JSONB,
        operation         TEXT        NOT NULL DEFAULT 'update' CHECK (operation IN ('add', 'update')),
        created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
        inserted_at       TIMESTAMPTZ NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_schedule_changes_group_id ON schedule_changes(group_id)
      """,
      """
      ALTER TABLE schedule_changes ADD COLUMN IF NOT EXISTS subject_code TEXT NOT NULL DEFAULT ''
      """,
      """
      ALTER TABLE schedule_changes ADD COLUMN IF NOT EXISTS course_number TEXT NOT NULL DEFAULT ''
      """,
      """
      ALTER TABLE schedule_changes ALTER COLUMN subject_code SET DEFAULT ''
      """,
      """
      ALTER TABLE schedule_changes ALTER COLUMN course_number SET DEFAULT ''
      """,
      """
      UPDATE schedule_changes SET subject_code = '' WHERE subject_code IS NULL
      """,
      """
      UPDATE schedule_changes SET course_number = '' WHERE course_number IS NULL
      """,
      """
      ALTER TABLE schedule_changes ALTER COLUMN subject_code SET NOT NULL
      """,
      """
      ALTER TABLE schedule_changes ALTER COLUMN course_number SET NOT NULL
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_schedule_changes_crn_term ON schedule_changes(crn, term)
      """
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case DbHelpers.run_sql(sql, %{}) do
        {:error, reason} -> {:halt, {:error, reason}}
        _rows -> {:cont, :ok}
      end
    end)
  end

  def list_groups do
    sql = """
    SELECT
      id,
      name,
      to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
      to_char(inserted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inserted_at
    FROM schedule_change_groups
    ORDER BY created_at DESC
    """

    case DbHelpers.run_sql(sql, %{}, @group_schema) do
      {:error, _reason} = error ->
        error

      groups ->
        {:ok, groups}
    end
  end

  def create_group(name) do
    sql = """
    INSERT INTO schedule_change_groups (name)
    VALUES ($(name))
    RETURNING id, name,
      to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
      to_char(inserted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inserted_at
    """

    case DbHelpers.run_sql(sql, %{"name" => name}, @group_schema) do
      [group] -> {:ok, group}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_insert_result, other}}
    end
  end

  def delete_group(group_id) do
    sql = "DELETE FROM schedule_change_groups WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(group_id)}) do
      {:error, _reason} = error -> error
      _rows -> :ok
    end
  end

  def rename_group(group_id, new_name) do
    sql = """
    UPDATE schedule_change_groups
    SET name = $(name)
    WHERE id = $(id)
    RETURNING id, name,
      to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
      to_char(inserted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inserted_at
    """

    case DbHelpers.run_sql(
           sql,
           %{"id" => Uuid.to_binary(group_id), "name" => new_name},
           @group_schema
         ) do
      [group] -> {:ok, group}
      [] -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_changes_for_group(group_id) do
    sql = """
    SELECT
      id,
      group_id,
      crn,
      term,
      subject_code,
      course_number,
      course_name,
      target_professor,
      meet_info,
      operation,
      to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
      to_char(inserted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inserted_at
    FROM schedule_changes
    WHERE group_id = $(group_id)
    ORDER BY crn
    """

    case DbHelpers.run_sql(sql, %{"group_id" => Uuid.to_binary(group_id)}, @change_schema) do
      {:error, _reason} = error ->
        error

      changes ->
        {:ok, changes}
    end
  end

  def add_or_update_change(group_id, change_attrs) do
    group_binary = Uuid.to_binary(group_id)
    crn = change_attrs["crn"] || change_attrs[:crn]
    _term = change_attrs["term"] || change_attrs[:term]

    DbHelpers.transaction(fn ->
      case get_change_by_crn(group_binary, crn) do
        nil ->
          insert_change(group_binary, change_attrs)

        existing ->
          change_id = existing["id"]
          update_change(change_id, change_attrs)
      end
    end)
  end

  def remove_change(change_id) do
    sql = "DELETE FROM schedule_changes WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(change_id)}) do
      {:error, _reason} = error -> error
      _rows -> :ok
    end
  end

  defp get_change_by_crn(group_id, crn) do
    sql = """
    SELECT id
    FROM schedule_changes
    WHERE group_id = $(group_id) AND crn = $(crn)
    LIMIT 1
    """

    case DbHelpers.run_sql(sql, %{"group_id" => group_id, "crn" => crn}) do
      [%{"id" => id}] -> %{"id" => id}
      [] -> nil
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_change(group_id, attrs) do
    sql = """
    INSERT INTO schedule_changes (
      group_id,
      crn,
      term,
      subject_code,
      course_number,
      course_name,
      target_professor,
      meet_info,
      operation
    )
    VALUES (
      $(group_id),
      $(crn),
      $(term),
      $(subject_code),
      $(course_number),
      $(course_name),
      $(target_professor),
      $(meet_info),
      $(operation)
    )
    RETURNING id, group_id, crn, term, subject_code, course_number, course_name, target_professor, meet_info, operation,
      to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
      to_char(inserted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inserted_at
    """

    params = %{
      "group_id" => group_id,
      "crn" => attrs["crn"] || attrs[:crn],
      "term" => attrs["term"] || attrs[:term],
      "subject_code" => attrs["subject_code"] || attrs[:subject_code],
      "course_number" => attrs["course_number"] || attrs[:course_number],
      "course_name" => attrs["course_name"] || attrs[:course_name],
      "target_professor" => attrs["target_professor"] || attrs[:target_professor],
      "meet_info" => attrs["meet_info"] || attrs[:meet_info],
      "operation" => attrs["operation"] || attrs[:operation] || "update"
    }

    case DbHelpers.run_sql(sql, params, @change_schema) do
      [change] -> {:ok, change}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_insert_result, other}}
    end
  end

  defp update_change(change_id, attrs) do
    sql = """
    UPDATE schedule_changes
    SET
      term = COALESCE($(term), term),
      subject_code = COALESCE($(subject_code), subject_code),
      course_number = COALESCE($(course_number), course_number),
      course_name = COALESCE($(course_name), course_name),
      target_professor = COALESCE($(target_professor), target_professor),
      meet_info = COALESCE($(meet_info), meet_info),
      operation = COALESCE($(operation), operation)
    WHERE id = $(id)
    RETURNING id, group_id, crn, term, subject_code, course_number, course_name, target_professor, meet_info, operation,
      to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
      to_char(inserted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inserted_at
    """

    params = %{
      "id" => Uuid.to_binary(change_id),
      "term" => attrs["term"] || attrs[:term],
      "subject_code" => attrs["subject_code"] || attrs[:subject_code],
      "course_number" => attrs["course_number"] || attrs[:course_number],
      "course_name" => attrs["course_name"] || attrs[:course_name],
      "target_professor" => attrs["target_professor"] || attrs[:target_professor],
      "meet_info" => attrs["meet_info"] || attrs[:meet_info],
      "operation" => attrs["operation"] || attrs[:operation]
    }

    case DbHelpers.run_sql(sql, params, @change_schema) do
      [change] -> {:ok, change}
      [] -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
