defmodule SimpleSyllabusReporter.Reports.GeneratedReportItem do
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
      SELECT DISTINCT ON (syllabus_code) id, syllabus_code
      FROM generated_reports
      WHERE syllabus_code = ANY($(codes))
      ORDER BY syllabus_code, inserted_at DESC
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
    WHERE gri.required_element_id = $(required_element_id)
      AND gri.status IN ('not_met', 'partially_met')
    ORDER BY gr.inserted_at ASC
    """

    case DbHelpers.run_sql(sql, %{"required_element_id" => required_element_id}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end
end
