defmodule SnowSeTools.Reports.GeneratedReportItemDB do
  require Logger
  alias SnowSeTools.Data.{DbHelpers, Uuid}

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
    FROM syllabus_generated_report_items gri
    JOIN syllabus_required_elements re ON re.id = gri.required_element_id
    WHERE gri.generated_report_id = $(generated_report_id)
    ORDER BY re.name ASC
    """

    case DbHelpers.run_sql(sql, %{"generated_report_id" => Uuid.to_binary(generated_report_id)}) do
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
    FROM syllabus_generated_report_items
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(id)}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  def get_by_report_and_element(generated_report_id, required_element_id) do
    sql = """
    SELECT id, generated_report_id, required_element_id, status, description, evidence, additional_considerations
    FROM syllabus_generated_report_items
    WHERE generated_report_id = $(generated_report_id)
      AND required_element_id = $(required_element_id)
    """

    case DbHelpers.run_sql(sql, %{
           "generated_report_id" => Uuid.to_binary(generated_report_id),
           "required_element_id" => Uuid.to_binary(required_element_id)
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
        INSERT INTO syllabus_generated_report_items
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
               "generated_report_id" => Uuid.to_binary(generated_report_id),
               "required_element_id" => Uuid.to_binary(required_element_id),
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
    sql = "DELETE FROM syllabus_generated_report_items WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(id)}) do
      {:error, _} = err -> err
      _ -> :ok
    end
  end

  def item_counts_for_syllabi(codes, opts \\ [])

  def item_counts_for_syllabi([], _opts), do: {:ok, %{}}

  def item_counts_for_syllabi(codes, opts) when is_list(codes) do
    term_id = Keyword.get(opts, :term_id)

    sql = """
    WITH latest_reports AS (
      SELECT DISTINCT ON (gr.syllabus_code) gr.id, gr.syllabus_code
      FROM syllabus_generated_reports gr
      JOIN syllabi s ON s.code = gr.syllabus_code
      WHERE gr.syllabus_code = ANY($(codes))
        AND ($(term_id)::text IS NULL OR s.term_id = $(term_id))
      ORDER BY gr.syllabus_code, gr.inserted_at DESC
    )
    SELECT
      lr.syllabus_code,
      COUNT(gri.id) FILTER (WHERE gri.status = 'met')::integer          AS met_count,
      COUNT(gri.id) FILTER (WHERE gri.status = 'not_met')::integer      AS not_met_count,
      COUNT(gri.id) FILTER (WHERE gri.status = 'partially_met')::integer AS partially_met_count
    FROM latest_reports lr
    LEFT JOIN syllabus_generated_report_items gri ON gri.generated_report_id = lr.id
    GROUP BY lr.syllabus_code
    """

    case DbHelpers.run_sql(sql, %{"codes" => codes, "term_id" => term_id}) do
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
      FROM syllabus_generated_reports gr
      JOIN syllabi s ON s.code = gr.syllabus_code
      ORDER BY gr.syllabus_code, gr.inserted_at DESC
    )
    SELECT
      COUNT(DISTINCT lr.id)::integer                                     AS total_syllabi,
      COUNT(gri.id) FILTER (WHERE gri.status = 'met')::integer           AS met,
      COUNT(gri.id) FILTER (WHERE gri.status = 'not_met')::integer       AS not_met,
      COUNT(gri.id) FILTER (WHERE gri.status = 'partially_met')::integer AS partially_met
    FROM latest_reports lr
    LEFT JOIN syllabus_generated_report_items gri
      ON gri.generated_report_id = lr.id
      AND gri.required_element_id = $(element_id)
    """

    case DbHelpers.run_sql(sql, %{"element_id" => Uuid.to_binary(element_id)}) do
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
      FROM syllabus_generated_reports gr
      JOIN syllabi s ON s.code = gr.syllabus_code
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
    LEFT JOIN syllabus_generated_report_items gri ON gri.generated_report_id = lr.id
    WHERE gri.required_element_id IS NOT NULL
    GROUP BY gri.required_element_id, total.total_syllabi
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def totals_by_school(term_id) do
    sql = """
    WITH scoped_syllabi AS (
      SELECT s.code, s.org_id
      FROM syllabi s
      WHERE s.org_id IS NOT NULL
        AND s.term_id = $(term_id)
    ),
    selected_snow_terms AS (
      SELECT st.term_code, st.term_name
      FROM snow_terms st
      JOIN syllabus_available_terms sat ON sat.term_name = st.term_name
      WHERE sat.term_id = $(term_id)
    ),
    org_subjects AS (
      SELECT DISTINCT s.org_id, substring(s.title from '^([A-Z]+)') AS subject_code
      FROM syllabi s
      WHERE s.org_id IS NOT NULL
        AND substring(s.title from '^([A-Z]+)') IS NOT NULL
    ),
    not_published_by_school AS (
      SELECT
        os.org_id,
        COUNT(DISTINCT c.term_code || ':' || c.crn)::integer AS not_published
      FROM snow_courses c
      JOIN selected_snow_terms st ON st.term_code = c.term_code
      JOIN org_subjects os ON os.subject_code = c.subject_code
      WHERE NOT EXISTS (
        SELECT 1
        FROM syllabi s
        WHERE s.term_name = st.term_name
          AND s.title ILIKE '%(CRN: ' || c.crn || ')%'
      )
      GROUP BY os.org_id
    ),
    scoped_orgs AS (
      SELECT org_id FROM scoped_syllabi
      UNION
      SELECT org_id FROM not_published_by_school
    ),
    latest_reports AS (
      SELECT DISTINCT ON (gr.syllabus_code) gr.id, gr.syllabus_code
      FROM syllabus_generated_reports gr
      JOIN scoped_syllabi ss ON ss.code = gr.syllabus_code
      ORDER BY gr.syllabus_code, gr.inserted_at DESC
    ),
    published_by_school AS (
      SELECT
        ss.org_id,
        COUNT(DISTINCT ss.code)::integer                                    AS total_syllabi,
        COUNT(DISTINCT lr.id)::integer                                      AS syllabi_with_reports,
        COUNT(gri.id) FILTER (WHERE gri.status = 'met')::integer           AS met,
        COUNT(gri.id) FILTER (WHERE gri.status = 'not_met')::integer       AS not_met,
        COUNT(gri.id) FILTER (WHERE gri.status = 'partially_met')::integer AS partially_met
      FROM scoped_syllabi ss
      LEFT JOIN latest_reports lr ON lr.syllabus_code = ss.code
      LEFT JOIN syllabus_generated_report_items gri ON gri.generated_report_id = lr.id
      GROUP BY ss.org_id
    )
    SELECT
      so.org_id,
      COALESCE(pbs.total_syllabi, 0)::integer AS total_syllabi,
      COALESCE(pbs.syllabi_with_reports, 0)::integer AS syllabi_with_reports,
      COALESCE(pbs.met, 0)::integer AS met,
      COALESCE(pbs.not_met, 0)::integer AS not_met,
      COALESCE(pbs.partially_met, 0)::integer AS partially_met,
      COALESCE(npbs.not_published, 0)::integer AS not_published
    FROM scoped_orgs so
    LEFT JOIN published_by_school pbs ON pbs.org_id = so.org_id
    LEFT JOIN not_published_by_school npbs ON npbs.org_id = so.org_id
    """

    case DbHelpers.run_sql(sql, %{"term_id" => term_id}) do
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
    FROM syllabus_generated_report_items gri
    JOIN syllabus_generated_reports gr ON gr.id = gri.generated_report_id
    JOIN syllabus_required_elements re ON re.id = gri.required_element_id
    JOIN syllabi s ON s.code = gr.syllabus_code
    WHERE gri.required_element_id = $(required_element_id)
      AND gri.status IN ('not_met', 'partially_met')
    ORDER BY gr.inserted_at ASC
    """

    case DbHelpers.run_sql(sql, %{"required_element_id" => Uuid.to_binary(required_element_id)}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def list_not_generated_for_element(element_id, all_codes) when is_list(all_codes) do
    sql = """
    WITH latest_reports AS (
      SELECT DISTINCT ON (gr.syllabus_code) gr.id, gr.syllabus_code
      FROM syllabus_generated_reports gr
      JOIN syllabi s ON s.code = gr.syllabus_code
      WHERE gr.syllabus_code = ANY($(codes))
      ORDER BY gr.syllabus_code, gr.inserted_at DESC
    ),
    covered AS (
      SELECT lr.syllabus_code
      FROM latest_reports lr
      JOIN syllabus_generated_report_items gri
        ON gri.generated_report_id = lr.id
        AND gri.required_element_id = $(element_id)
    )
    SELECT code
    FROM UNNEST($(codes)::text[]) AS t(code)
    WHERE code NOT IN (SELECT syllabus_code FROM covered)
    """

    case DbHelpers.run_sql(sql, %{
           "element_id" => Uuid.to_binary(element_id),
           "codes" => all_codes
         }) do
      {:error, _} = err -> err
      rows -> {:ok, Enum.map(rows, & &1["code"])}
    end
  end
end
