defmodule SnowSeTools.AcademicPrograms.ProgramDb do
  alias SnowSeTools.Data.DbHelpers
  alias SnowSeTools.Data.Uuid

  @program_schema Zoi.object(%{
                    "id" => Zoi.uuid(),
                    "name" => Zoi.string(),
                    "inserted_at" => Zoi.string(),
                    "updated_at" => Zoi.string()
                  })

  def bootstrap_tables do
    statements = [
      """
      CREATE TABLE IF NOT EXISTS academic_programs (
        id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        name        TEXT        NOT NULL UNIQUE,
        inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS academic_program_semesters (
        id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        academic_program_id UUID        NOT NULL REFERENCES academic_programs(id) ON DELETE CASCADE,
        position            INTEGER     NOT NULL DEFAULT 0,
        inserted_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE(academic_program_id, position)
      )
      """,
      """
      ALTER TABLE academic_program_semesters
      DROP COLUMN IF EXISTS name
      """,
      """
      CREATE UNIQUE INDEX IF NOT EXISTS academic_program_semesters_program_position_unique_idx
      ON academic_program_semesters(academic_program_id, position)
      """,
      """
      CREATE TABLE IF NOT EXISTS academic_program_semester_courses (
        id                           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        academic_program_semester_id UUID        NOT NULL REFERENCES academic_program_semesters(id) ON DELETE CASCADE,
        subject_code                 TEXT        NOT NULL,
        course_number                TEXT        NOT NULL,
        position                     INTEGER     NOT NULL DEFAULT 0,
        inserted_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE(academic_program_semester_id, subject_code, course_number)
      )
      """,
      """
      CREATE INDEX IF NOT EXISTS academic_program_semesters_program_idx
      ON academic_program_semesters(academic_program_id, position)
      """,
      """
      CREATE INDEX IF NOT EXISTS academic_program_semester_courses_semester_idx
      ON academic_program_semester_courses(academic_program_semester_id, position)
      """
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case DbHelpers.run_sql(sql, %{}) do
        {:error, reason} -> {:halt, {:error, reason}}
        _rows -> {:cont, :ok}
      end
    end)
  end

  def list_programs do
    sql = """
    SELECT
      id,
      name,
      to_char(inserted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inserted_at,
      to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS updated_at
    FROM academic_programs
    ORDER BY lower(name)
    """

    case DbHelpers.run_sql(sql, %{}, @program_schema) do
      {:error, _reason} = error ->
        error

      programs ->
        hydrate_programs(programs)
    end
  end

  def create_program(attrs: attrs) do
    name = normalize_name(Map.get(attrs, "name"))

    if name == "" do
      {:error, "Program name is required."}
    else
      DbHelpers.transaction(fn ->
        case insert_program(name: name) do
          {:ok, program_id} ->
            save_semesters(program_id: program_id, semesters: Map.get(attrs, "semesters", []))
            |> case do
              :ok -> get_program(program_id: program_id)
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end
  end

  def update_program(id: id, attrs: attrs) do
    name = normalize_name(Map.get(attrs, "name"))

    if name == "" do
      {:error, "Program name is required."}
    else
      DbHelpers.transaction(fn ->
        update_sql = """
        UPDATE academic_programs
        SET name = $(name), updated_at = NOW()
        WHERE id = $(id)
        """

        case DbHelpers.run_sql(update_sql, %{"id" => uuid_param(id), "name" => name}) do
          {:error, reason} ->
            {:error, reason}

          _rows ->
            case DbHelpers.run_sql(
                   "DELETE FROM academic_program_semesters WHERE academic_program_id = $(id)",
                   %{"id" => uuid_param(id)}
                 ) do
              {:error, reason} ->
                {:error, reason}

              _rows ->
                save_semesters(program_id: id, semesters: Map.get(attrs, "semesters", []))
                |> case do
                  :ok -> get_program(program_id: id)
                  {:error, reason} -> {:error, reason}
                end
            end
        end
      end)
    end
  end

  def delete_program(id: id) do
    sql = "DELETE FROM academic_programs WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => uuid_param(id)}) do
      {:error, _reason} = error -> error
      _rows -> :ok
    end
  end

  defp insert_program(name: name) do
    sql = """
    INSERT INTO academic_programs (name)
    VALUES ($(name))
    RETURNING id
    """

    case DbHelpers.run_sql(sql, %{"name" => name}) do
      [%{"id" => id}] -> {:ok, id}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_insert_result, other}}
    end
  end

  defp get_program(program_id: program_id) do
    sql = """
    SELECT
      id,
      name,
      to_char(inserted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS inserted_at,
      to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS updated_at
    FROM academic_programs
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(sql, %{"id" => uuid_param(program_id)}, @program_schema) do
      [program] -> {:ok, hydrate_program(program)}
      [] -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp hydrate_programs(programs) do
    {:ok, Enum.map(programs, &hydrate_program/1)}
  end

  defp hydrate_program(program) do
    Map.put(program, "semesters", list_semesters(program_id: program["id"]))
  end

  defp list_semesters(program_id: program_id) do
    sql = """
    SELECT id, position
    FROM academic_program_semesters
    WHERE academic_program_id = $(program_id)
    ORDER BY position
    """

    case DbHelpers.run_sql(sql, %{"program_id" => uuid_param(program_id)}) do
      {:error, _reason} ->
        []

      semesters ->
        Enum.map(semesters, fn semester ->
          Map.put(semester, "courses", list_courses(semester_id: semester["id"]))
        end)
    end
  end

  defp list_courses(semester_id: semester_id) do
    sql = """
    SELECT id, subject_code, course_number, position
    FROM academic_program_semester_courses
    WHERE academic_program_semester_id = $(semester_id)
    ORDER BY position, subject_code, course_number
    """

    case DbHelpers.run_sql(sql, %{"semester_id" => uuid_param(semester_id)}) do
      {:error, _reason} -> []
      courses -> courses
    end
  end

  defp save_semesters(program_id: program_id, semesters: semesters) when is_list(semesters) do
    semesters
    |> normalize_semesters()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {semester, index}, :ok ->
      case insert_semester(program_id: program_id, position: index) do
        {:ok, semester_id} ->
          case save_courses(semester_id: semester_id, courses: Map.get(semester, "courses", [])) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_semester(program_id: program_id, position: position) do
    sql = """
    INSERT INTO academic_program_semesters (academic_program_id, position)
    VALUES ($(program_id), $(position))
    RETURNING id
    """

    params = %{
      "program_id" => uuid_param(program_id),
      "position" => position
    }

    case DbHelpers.run_sql(sql, params) do
      [%{"id" => id}] -> {:ok, id}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_insert_result, other}}
    end
  end

  defp save_courses(semester_id: semester_id, courses: courses) when is_list(courses) do
    courses
    |> normalize_courses()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {course, index}, :ok ->
      sql = """
      INSERT INTO academic_program_semester_courses (
        academic_program_semester_id,
        subject_code,
        course_number,
        position
      )
      VALUES ($(semester_id), $(subject_code), $(course_number), $(position))
      """

      params = %{
        "semester_id" => uuid_param(semester_id),
        "subject_code" => course["subject_code"],
        "course_number" => course["course_number"],
        "position" => index
      }

      case DbHelpers.run_sql(sql, params) do
        {:error, reason} -> {:halt, {:error, reason}}
        _rows -> {:cont, :ok}
      end
    end)
  end

  defp normalize_semesters(semesters) do
    semesters
    |> Enum.map(fn semester ->
      %{
        "courses" => Map.get(semester, "courses", [])
      }
    end)
  end

  defp normalize_courses(courses) do
    courses
    |> Enum.map(fn course ->
      %{
        "subject_code" =>
          course |> Map.get("subject_code", "") |> String.trim() |> String.upcase(),
        "course_number" => course |> Map.get("course_number", "") |> String.trim()
      }
    end)
    |> Enum.reject(&(&1["subject_code"] == "" or &1["course_number"] == ""))
    |> Enum.uniq_by(fn course -> {course["subject_code"], course["course_number"]} end)
  end

  defp normalize_name(name) when is_binary(name), do: String.trim(name)
  defp normalize_name(_name), do: ""

  defp uuid_param(<<_::16-bytes>> = value), do: value
  defp uuid_param(value) when is_binary(value), do: Uuid.to_binary(value)
end
