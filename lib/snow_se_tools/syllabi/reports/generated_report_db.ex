defmodule SnowSeTools.Reports.GeneratedReportDB do
  alias SnowSeTools.Data.{DbHelpers, Uuid}

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
    FROM syllabus_generated_reports gr
    JOIN syllabi s ON s.code = gr.syllabus_code
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
    FROM syllabus_generated_reports
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
        INSERT INTO syllabus_generated_reports (syllabus_code, syllabus_title, instructor_name, status)
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
    UPDATE syllabus_generated_reports
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
    get_latest_for_syllabus(syllabus_code, term_id: nil)
  end

  def get_latest_for_syllabus(syllabus_code, term_id: term_id) do
    sql = """
    SELECT gr.id, gr.syllabus_code, gr.syllabus_title, gr.instructor_name, gr.status
    FROM syllabus_generated_reports gr
    JOIN syllabi s ON s.code = gr.syllabus_code
    WHERE gr.syllabus_code = $(syllabus_code)
      AND ($(term_id)::text IS NULL OR s.term_id = $(term_id))
    ORDER BY gr.inserted_at DESC
    LIMIT 1
    """

    case DbHelpers.run_sql(sql, %{"syllabus_code" => syllabus_code, "term_id" => term_id}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  def get_or_create_for_syllabus(syllabus_code, syllabus_title, instructor_name) do
    get_or_create_for_syllabus(syllabus_code, syllabus_title, instructor_name, term_id: nil)
  end

  def get_or_create_for_syllabus(
        syllabus_code,
        syllabus_title,
        instructor_name,
        term_id: term_id
      ) do
    case get_latest_for_syllabus(syllabus_code, term_id: term_id) do
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
    sql = "DELETE FROM syllabus_generated_reports WHERE id = $(id)"

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
    FROM syllabus_generated_reports gr
    JOIN syllabus_required_elements re ON TRUE
    JOIN syllabi s ON s.code = gr.syllabus_code
    LEFT JOIN syllabus_generated_report_items gri
      ON gri.generated_report_id = gr.id
     AND gri.required_element_id = re.id
    WHERE gr.status = 'pending'
      AND gri.id IS NULL
    ORDER BY gr.inserted_at ASC
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end
end
