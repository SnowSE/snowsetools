defmodule SimpleSyllabusReporter.Reports.GeneratedReport do
  require Logger
  alias SimpleSyllabusReporter.Data.DbHelpers

  @schema Zoi.object(%{
            "syllabus_code" => Zoi.string(),
            "syllabus_title" => Zoi.string(),
            "instructor_name" => Zoi.string(),
            "status" =>
              Zoi.default(
                Zoi.optional(Zoi.enum(["pending", "completed", "error"])),
                "pending"
              )
          })

  defp validate(attrs) do
    string_attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    Zoi.parse(@schema, string_attrs)
  end

  def list_all do
    sql = """
    SELECT id, syllabus_code, syllabus_title, instructor_name, status, inserted_at
    FROM generated_reports
    ORDER BY inserted_at DESC
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def get(id) do
    sql = """
    SELECT id, syllabus_code, syllabus_title, instructor_name, status, inserted_at, updated_at
    FROM generated_reports
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(sql, %{"id" => id}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  def create(attrs) do
    case validate(attrs) do
      {:ok, d} ->
        sql = """
        INSERT INTO generated_reports (syllabus_code, syllabus_title, instructor_name, status)
        VALUES ($(syllabus_code), $(syllabus_title), $(instructor_name), $(status))
        RETURNING id, syllabus_code, syllabus_title, instructor_name, status, inserted_at
        """

        case DbHelpers.run_sql(sql, %{
               "syllabus_code" => d["syllabus_code"],
               "syllabus_title" => d["syllabus_title"],
               "instructor_name" => d["instructor_name"],
               "status" => d["status"]
             }) do
          {:error, _} = err -> err
          [row | _] -> {:ok, row}
          [] -> {:error, :not_found}
        end

      {:error, errors} ->
        {:error, {:validation, errors}}
    end
  end

  def update_status(id, status) when status in ["pending", "completed", "error"] do
    sql = """
    UPDATE generated_reports
    SET status     = $(status),
        updated_at = NOW()
    WHERE id = $(id)
    RETURNING id, syllabus_code, syllabus_title, instructor_name, status
    """

    case DbHelpers.run_sql(sql, %{"id" => id, "status" => status}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  def get_latest_for_syllabus(syllabus_code) do
    sql = """
    SELECT id, syllabus_code, syllabus_title, instructor_name, status
    FROM generated_reports
    WHERE syllabus_code = $(syllabus_code)
    ORDER BY inserted_at DESC
    LIMIT 1
    """

    case DbHelpers.run_sql(sql, %{"syllabus_code" => syllabus_code}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  def get_or_create_for_syllabus(syllabus_code, syllabus_title, instructor_name) do
    case get_latest_for_syllabus(syllabus_code) do
      {:ok, report} ->
        {:ok, report}

      {:error, :not_found} ->
        create(%{
          "syllabus_code" => syllabus_code,
          "syllabus_title" => syllabus_title,
          "instructor_name" => instructor_name
        })

      {:error, _} = err ->
        err
    end
  end

  def delete(id) do
    sql = "DELETE FROM generated_reports WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => id}) do
      {:error, _} = err -> err
      _ -> :ok
    end
  end
end
