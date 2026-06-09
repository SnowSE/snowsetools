defmodule SimpleSyllabusReporter.Reports.GeneratedReportDB do
  require Logger
  alias SimpleSyllabusReporter.Data.{DbHelpers, Uuid}

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
    SELECT gr.id, gr.syllabus_code, gr.syllabus_title, gr.instructor_name, gr.status, gr.inserted_at
    FROM generated_reports gr
    JOIN syllabi s ON s.code = gr.syllabus_code
    LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
    WHERE sc.value IS NULL OR s.term_id = sc.value
    ORDER BY gr.inserted_at DESC
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

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(id)}) do
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

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(id), "status" => status}) do
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

  def list_pending_with_incomplete_elements do
    sql = """
    SELECT
      gr.id            AS report_id,
      gr.syllabus_code AS code,
      re.id            AS element_id,
      re.name          AS element_name,
      re.description   AS element_description
    FROM generated_reports gr
    JOIN required_elements re ON TRUE
    JOIN syllabi s ON s.code = gr.syllabus_code
    LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
    LEFT JOIN generated_report_items gri
      ON gri.generated_report_id = gr.id
     AND gri.required_element_id = re.id
    WHERE gr.status = 'pending'
      AND gri.id IS NULL
      AND (sc.value IS NULL OR s.term_id = sc.value)
    ORDER BY gr.inserted_at ASC
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end
end
