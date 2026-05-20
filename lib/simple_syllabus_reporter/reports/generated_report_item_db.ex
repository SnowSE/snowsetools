defmodule SimpleSyllabusReporter.Reports.GeneratedReportItemDB do
  require Logger
  alias SimpleSyllabusReporter.Data.DbHelpers

  @schema Zoi.object(%{
            "status" => Zoi.enum(["met", "not_met", "partially_met"]),
            "description" => Zoi.string(),
            "evidence" => Zoi.default(Zoi.optional(Zoi.string()), ""),
            "additional_considerations" => Zoi.default(Zoi.optional(Zoi.string()), "")
          })

  defp validate(attrs) do
    string_attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    Zoi.parse(@schema, string_attrs)
  end

  def list_for_report(generated_report_id) do
    sql = """
    SELECT
      gri.id,
      gri.generated_report_id,
      gri.required_element_id,
      gri.status,
      gri.description,
      gri.evidence,
      gri.additional_considerations,
      re.name AS element_name
    FROM generated_report_items gri
    JOIN required_elements re ON re.id = gri.required_element_id
    WHERE gri.generated_report_id = $(generated_report_id)
    ORDER BY re.name ASC
    """

    case DbHelpers.run_sql(sql, %{"generated_report_id" => generated_report_id}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def list_for_report_as_map(generated_report_id) do
    case list_for_report(generated_report_id) do
      {:ok, items} ->
        {:ok, Map.new(items, fn item -> {item["required_element_id"], item} end)}

      {:error, _} = err ->
        err
    end
  end

  def get(id) do
    sql = """
    SELECT id, generated_report_id, required_element_id, status, description, evidence, additional_considerations
    FROM generated_report_items
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(sql, %{"id" => id}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  def get_by_report_and_element(generated_report_id, required_element_id) do
    sql = """
    SELECT id, generated_report_id, required_element_id, status, description, evidence, additional_considerations
    FROM generated_report_items
    WHERE generated_report_id = $(generated_report_id)
      AND required_element_id = $(required_element_id)
    """

    case DbHelpers.run_sql(sql, %{
           "generated_report_id" => generated_report_id,
           "required_element_id" => required_element_id
         }) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  def upsert(generated_report_id, required_element_id, attrs) do
    case validate(attrs) do
      {:ok, d} ->
        sql = """
        INSERT INTO generated_report_items
          (generated_report_id, required_element_id, status, description, evidence, additional_considerations)
        VALUES
          ($(generated_report_id), $(required_element_id), $(status), $(description), $(evidence), $(additional_considerations))
        ON CONFLICT (generated_report_id, required_element_id) DO UPDATE
          SET status                    = EXCLUDED.status,
              description               = EXCLUDED.description,
              evidence                  = EXCLUDED.evidence,
              additional_considerations = EXCLUDED.additional_considerations,
              updated_at                = NOW()
        RETURNING id, generated_report_id, required_element_id, status, description, evidence, additional_considerations
        """

        case DbHelpers.run_sql(sql, %{
               "generated_report_id" => generated_report_id,
               "required_element_id" => required_element_id,
               "status" => d["status"],
               "description" => d["description"],
               "evidence" => d["evidence"],
               "additional_considerations" => d["additional_considerations"]
             }) do
          {:error, _} = err -> err
          [row | _] -> {:ok, row}
          [] -> {:error, :not_found}
        end

      {:error, errors} ->
        {:error, {:validation, errors}}
    end
  end

  def delete(id) do
    sql = "DELETE FROM generated_report_items WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => id}) do
      {:error, _} = err -> err
      _ -> :ok
    end
  end

  def item_counts_for_syllabi([]), do: {:ok, %{}}

  def item_counts_for_syllabi(codes) when is_list(codes) do
    sql = """
    WITH latest_reports AS (
      SELECT DISTINCT ON (gr.syllabus_code) gr.id, gr.syllabus_code
      FROM generated_reports gr
      JOIN syllabi s ON s.code = gr.syllabus_code
      LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
      WHERE gr.syllabus_code = ANY($(codes))
        AND (sc.value IS NULL OR s.term_id = sc.value)
      ORDER BY gr.syllabus_code, gr.inserted_at DESC
    )
    SELECT
      lr.syllabus_code,
      COUNT(gri.id) FILTER (WHERE gri.status = 'met')::integer          AS met_count,
      COUNT(gri.id) FILTER (WHERE gri.status = 'not_met')::integer      AS not_met_count,
      COUNT(gri.id) FILTER (WHERE gri.status = 'partially_met')::integer AS partially_met_count
    FROM latest_reports lr
    LEFT JOIN generated_report_items gri ON gri.generated_report_id = lr.id
    GROUP BY lr.syllabus_code
    """

    case DbHelpers.run_sql(sql, %{"codes" => codes}) do
      {:error, _} = err ->
        err

      rows ->
        {:ok,
         Map.new(rows, fn r ->
           {r["syllabus_code"],
            %{
              "met" => r["met_count"],
              "not_met" => r["not_met_count"],
              "partially_met" => r["partially_met_count"]
            }}
         end)}
    end
  end

  def item_counts_for_element(element_id) do
    sql = """
    WITH latest_reports AS (
      SELECT DISTINCT ON (gr.syllabus_code) gr.id
      FROM generated_reports gr
      JOIN syllabi s ON s.code = gr.syllabus_code
      LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
      WHERE sc.value IS NULL OR s.term_id = sc.value
      ORDER BY gr.syllabus_code, gr.inserted_at DESC
    )
    SELECT
      COUNT(DISTINCT lr.id)::integer                                     AS total_syllabi,
      COUNT(gri.id) FILTER (WHERE gri.status = 'met')::integer           AS met,
      COUNT(gri.id) FILTER (WHERE gri.status = 'not_met')::integer       AS not_met,
      COUNT(gri.id) FILTER (WHERE gri.status = 'partially_met')::integer AS partially_met
    FROM latest_reports lr
    LEFT JOIN generated_report_items gri
      ON gri.generated_report_id = lr.id
      AND gri.required_element_id = $(element_id)
    """

    case DbHelpers.run_sql(sql, %{"element_id" => element_id}) do
      {:error, _} = err ->
        err

      [row] ->
        {:ok, row}

      [] ->
        {:ok, %{"met" => 0, "not_met" => 0, "partially_met" => 0, "total_syllabi" => 0}}
    end
  end

  def all_element_coverage_counts do
    sql = """
    WITH latest_reports AS (
      SELECT DISTINCT ON (gr.syllabus_code) gr.id
      FROM generated_reports gr
      JOIN syllabi s ON s.code = gr.syllabus_code
      LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
      WHERE sc.value IS NULL OR s.term_id = sc.value
      ORDER BY gr.syllabus_code, gr.inserted_at DESC
    ),
    total AS (
      SELECT COUNT(*)::integer AS total_syllabi FROM latest_reports
    )
    SELECT
      gri.required_element_id                                             AS element_id,
      total.total_syllabi                                                 AS total_syllabi,
      COUNT(gri.id) FILTER (WHERE gri.status = 'met')::integer           AS met,
      COUNT(gri.id) FILTER (WHERE gri.status = 'not_met')::integer       AS not_met,
      COUNT(gri.id) FILTER (WHERE gri.status = 'partially_met')::integer AS partially_met
    FROM latest_reports lr
    CROSS JOIN total
    LEFT JOIN generated_report_items gri ON gri.generated_report_id = lr.id
    WHERE gri.required_element_id IS NOT NULL
    GROUP BY gri.required_element_id, total.total_syllabi
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def totals_by_school do
    sql = """
    WITH scoped_syllabi AS (
      SELECT s.code, s.org_id
      FROM syllabi s
      LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
      WHERE s.org_id IS NOT NULL
        AND (sc.value IS NULL OR s.term_id = sc.value)
    ),
    latest_reports AS (
      SELECT DISTINCT ON (gr.syllabus_code) gr.id, gr.syllabus_code
      FROM generated_reports gr
      JOIN scoped_syllabi ss ON ss.code = gr.syllabus_code
      ORDER BY gr.syllabus_code, gr.inserted_at DESC
    )
    SELECT
      ss.org_id,
      COUNT(DISTINCT ss.code)::integer                                    AS total_syllabi,
      COUNT(DISTINCT lr.id)::integer                                      AS syllabi_with_reports,
      COUNT(gri.id) FILTER (WHERE gri.status = 'met')::integer           AS met,
      COUNT(gri.id) FILTER (WHERE gri.status = 'not_met')::integer       AS not_met,
      COUNT(gri.id) FILTER (WHERE gri.status = 'partially_met')::integer AS partially_met
    FROM scoped_syllabi ss
    LEFT JOIN latest_reports lr ON lr.syllabus_code = ss.code
    LEFT JOIN generated_report_items gri ON gri.generated_report_id = lr.id
    GROUP BY ss.org_id
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def list_unmet_for_element(required_element_id) do
    sql = """
    SELECT
      gr.syllabus_code AS code,
      re.id            AS element_id,
      re.name          AS element_name,
      re.description   AS element_description
    FROM generated_report_items gri
    JOIN generated_reports gr ON gr.id = gri.generated_report_id
    JOIN required_elements re ON re.id = gri.required_element_id
    JOIN syllabi s ON s.code = gr.syllabus_code
    LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
    WHERE gri.required_element_id = $(required_element_id)
      AND gri.status IN ('not_met', 'partially_met')
      AND (sc.value IS NULL OR s.term_id = sc.value)
    ORDER BY gr.inserted_at ASC
    """

    case DbHelpers.run_sql(sql, %{"required_element_id" => required_element_id}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def list_not_generated_for_element(element_id, all_codes) when is_list(all_codes) do
    sql = """
    WITH latest_reports AS (
      SELECT DISTINCT ON (gr.syllabus_code) gr.id, gr.syllabus_code
      FROM generated_reports gr
      JOIN syllabi s ON s.code = gr.syllabus_code
      LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
      WHERE gr.syllabus_code = ANY($(codes))
        AND (sc.value IS NULL OR s.term_id = sc.value)
      ORDER BY gr.syllabus_code, gr.inserted_at DESC
    ),
    covered AS (
      SELECT lr.syllabus_code
      FROM latest_reports lr
      JOIN generated_report_items gri
        ON gri.generated_report_id = lr.id
        AND gri.required_element_id = $(element_id)
    )
    SELECT code
    FROM UNNEST($(codes)::text[]) AS t(code)
    WHERE code NOT IN (SELECT syllabus_code FROM covered)
    """

    case DbHelpers.run_sql(sql, %{"element_id" => element_id, "codes" => all_codes}) do
      {:error, _} = err -> err
      rows -> {:ok, Enum.map(rows, & &1["code"])}
    end
  end
end
