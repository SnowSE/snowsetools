defmodule SnowSeTools.Syllabi.SyllabusDB do
  require Logger
  alias SnowSeTools.Data.DbHelpers

  def upsert_list_items(docs, org_id: org_id) do
    Enum.each(docs, fn doc ->
      upsert_syllabus(
        syllabus_metadata: doc,
        syllabus_details: nil,
        org_id: org_id,
        linked_email: nil
      )
    end)
  end

  def upsert_syllabus(
        syllabus_metadata: doc,
        syllabus_details: detail_data,
        org_id: org_id,
        linked_email: linked_email
      ) do
    # Extract emails from detail_data if available
    linked_emails = extract_linked_emails(detail_data, linked_email)

    sql = """
    INSERT INTO syllabi
      (code, title, course_name, term_name, term_id, org_id, linked_emails, editors, list_data, detail_data, list_cached_at, detail_cached_at, sync_status, sync_error, synced_at, updated_at)
    VALUES
      ($(code), $(title), $(course_name), $(term_name), $(term_id), $(org_id),
       $(linked_emails)::text[],
       $(editors)::jsonb, $(list_data)::jsonb, $(detail_data)::jsonb,
       NOW(), NOW(), 'synced', NULL, NOW(), NOW())
    ON CONFLICT (code) DO UPDATE SET
      title          = EXCLUDED.title,
      course_name    = EXCLUDED.course_name,
      term_name      = EXCLUDED.term_name,
      term_id        = EXCLUDED.term_id,
      org_id         = COALESCE(EXCLUDED.org_id, syllabi.org_id),
      linked_emails  = EXCLUDED.linked_emails,
      editors        = EXCLUDED.editors,
      list_data      = EXCLUDED.list_data,
      detail_data    = EXCLUDED.detail_data,
      list_cached_at = NOW(),
      detail_cached_at = NOW(),
      sync_status    = 'synced',
      sync_error     = NULL,
      synced_at      = NOW(),
      updated_at     = NOW()
    """

    params = %{
      "code" => doc["code"],
      "title" => doc["title"],
      "course_name" => doc["course_name"],
      "term_name" => doc["term_name"],
      "term_id" => doc["term_id"],
      "org_id" => org_id || doc["entity_id"],
      "editors" => doc["editors"] || [],
      "list_data" => doc,
      "detail_data" => detail_data,
      "linked_emails" => linked_emails
    }

    case DbHelpers.run_sql(sql, params) do
      {:error, reason} = err ->
        Logger.error("Failed to upsert syllabus code=#{doc["code"]} reason=#{inspect(reason)}")
        err

      rows when is_list(rows) ->
        Logger.info("Upserted syllabus #{doc["title"]}")
        :ok
    end
  end

  def list_by_org(org_id) when is_binary(org_id), do: list_by_org(org_id, term_id: nil)

  def list_by_org(org_id, term_id: term_id) when is_binary(org_id) do
    sql = """
    WITH selected_snow_terms AS (
      SELECT st.term_code, st.term_name, sat.term_id AS syllabus_term_id
      FROM snow_terms st
      LEFT JOIN syllabus_available_terms sat ON sat.term_name = st.term_name
      WHERE $(term_id)::text IS NULL OR sat.term_id = $(term_id)
    ),
    org_subjects AS (
      SELECT DISTINCT substring(s.title from '^([A-Z]+)') AS subject_code
      FROM syllabi s
      WHERE s.org_id = ANY($(org_ids)::text[])
        AND substring(s.title from '^([A-Z]+)') IS NOT NULL
    ),
    existing_syllabi AS (
      SELECT s.list_data, s.list_cached_at, 0 AS source_order
      FROM syllabi s
      WHERE s.org_id = ANY($(org_ids)::text[])
        AND ($(term_id)::text IS NULL OR s.term_id = $(term_id))
    ),
    missing_snow_courses AS (
      SELECT
        jsonb_build_object(
          'code', 'snow-course-' || c.term_code || '-' || c.crn,
          'title', c.subject_code || ' ' || c.course_number || ' ' || c.section_number || ' (CRN: ' || c.crn || ')',
          'course_name', c.course_name,
          'term_id', st.syllabus_term_id,
          'term_name', st.term_name,
          'term', st.term_name,
          'entity_id', c.crn,
          'entity_type', 'snow_course',
          'family_name', 'snow_course',
          'visibility', 'unpublished',
          'source', 'snow_courses',
          'syllabus_status', 'unpublished',
          'org_id', $(org_id)::text,
          '__org_id', $(org_id)::text,
          'editors', COALESCE(instructors.editors, '[]'::jsonb),
          'snow_course', jsonb_build_object(
            'term_code', c.term_code,
            'crn', c.crn,
            'subject_code', c.subject_code,
            'course_number', c.course_number,
            'section_number', c.section_number,
            'course_name', c.course_name,
            'primary_instructor_name', c.primary_instructor_name
          )
        ) AS list_data,
        c.cached_at AS list_cached_at,
        1 AS source_order
      FROM snow_courses c
      JOIN selected_snow_terms st ON st.term_code = c.term_code
      LEFT JOIN LATERAL (
        SELECT jsonb_agg(
          jsonb_build_object(
            'full_name', instructor->>'name',
            'first_name', split_part(COALESCE(instructor->>'name', ''), ' ', 1),
            'last_name', trim(regexp_replace(COALESCE(instructor->>'name', ''), '^\\S+\\s*', '')),
            'has_headshot', false,
            'accounts', jsonb_build_array(jsonb_build_object('email', instructor->>'email')),
            'role', jsonb_build_object('role_types', jsonb_build_array('instructor'))
          )
        ) FILTER (WHERE instructor ? 'name' OR instructor ? 'email') AS editors
        FROM jsonb_array_elements(COALESCE(c.data::jsonb->'instructors', '[]'::jsonb)) instructor
      ) instructors ON TRUE
      WHERE c.subject_code IN (SELECT subject_code FROM org_subjects)
        AND NOT EXISTS (
          SELECT 1
          FROM syllabi s
          WHERE s.term_name = st.term_name
            AND s.title ILIKE '%(CRN: ' || c.crn || ')%'
        )
    )
    SELECT list_data, list_cached_at
    FROM (
      SELECT * FROM existing_syllabi
      UNION ALL
      SELECT * FROM missing_snow_courses
    ) results
    ORDER BY source_order, COALESCE(list_data->>'title', list_data->>'course_name') ASC NULLS LAST
    """

    case DbHelpers.run_sql(sql, %{"org_ids" => [org_id], "org_id" => org_id, "term_id" => term_id}) do
      {:error, _} = err -> err
      [] -> {:ok, [], nil}
      rows -> {:ok, Enum.map(rows, & &1["list_data"]), oldest_cached_at(rows)}
    end
  end

  def list_populated_org_ids do
    sql = "SELECT DISTINCT org_id FROM syllabi WHERE org_id IS NOT NULL"

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, Enum.map(rows, & &1["org_id"])}
    end
  end

  def list_by_editor_email(email), do: list_by_editor_email(email, term_id: nil)

  def list_by_editor_email(email, term_id: term_id) do
    sql = """
    WITH selected_snow_terms AS (
      SELECT st.term_code, st.term_name, sat.term_id AS syllabus_term_id
      FROM snow_terms st
      LEFT JOIN syllabus_available_terms sat ON sat.term_name = st.term_name
      WHERE $(term_id)::text IS NULL OR sat.term_id = $(term_id)
    ),
    existing_syllabi AS (
      SELECT s.list_data, s.list_cached_at, 0 AS source_order
      FROM syllabi s
      WHERE EXISTS (
          SELECT 1
          FROM unnest(s.linked_emails) linked_email
          WHERE lower(linked_email) = lower($(email))
        )
        AND ($(term_id)::text IS NULL OR s.term_id = $(term_id))
    ),
    missing_snow_courses AS (
      SELECT
        jsonb_build_object(
          'code', 'snow-course-' || c.term_code || '-' || c.crn,
          'title', c.subject_code || ' ' || c.course_number || ' ' || c.section_number || ' (CRN: ' || c.crn || ')',
          'course_name', c.course_name,
          'term_id', st.syllabus_term_id,
          'term_name', st.term_name,
          'term', st.term_name,
          'entity_id', c.crn,
          'entity_type', 'snow_course',
          'family_name', 'snow_course',
          'visibility', 'unpublished',
          'source', 'snow_courses',
          'syllabus_status', 'unpublished',
          'org_id', NULL,
          '__org_id', NULL,
          'editors', COALESCE(instructors.editors, '[]'::jsonb),
          'snow_course', jsonb_build_object(
            'term_code', c.term_code,
            'crn', c.crn,
            'subject_code', c.subject_code,
            'course_number', c.course_number,
            'section_number', c.section_number,
            'course_name', c.course_name,
            'primary_instructor_name', c.primary_instructor_name
          )
        ) AS list_data,
        c.cached_at AS list_cached_at,
        1 AS source_order
      FROM snow_courses c
      JOIN selected_snow_terms st ON st.term_code = c.term_code
      LEFT JOIN LATERAL (
        SELECT jsonb_agg(
          jsonb_build_object(
            'full_name', instructor->>'name',
            'first_name', split_part(COALESCE(instructor->>'name', ''), ' ', 1),
            'last_name', trim(regexp_replace(COALESCE(instructor->>'name', ''), '^\\S+\\s*', '')),
            'has_headshot', false,
            'accounts', jsonb_build_array(jsonb_build_object('email', instructor->>'email')),
            'role', jsonb_build_object('role_types', jsonb_build_array('instructor'))
          )
        ) FILTER (WHERE instructor ? 'name' OR instructor ? 'email') AS editors
        FROM jsonb_array_elements(COALESCE(c.data::jsonb->'instructors', '[]'::jsonb)) instructor
      ) instructors ON TRUE
      WHERE EXISTS (
          SELECT 1
          FROM jsonb_array_elements(COALESCE(c.data::jsonb->'instructors', '[]'::jsonb)) instructor
          WHERE lower(instructor->>'email') = lower($(email))
        )
        AND NOT EXISTS (
          SELECT 1
          FROM syllabi s
          WHERE s.term_name = st.term_name
            AND s.title ILIKE '%(CRN: ' || c.crn || ')%'
        )
    )
    SELECT list_data, list_cached_at
    FROM (
      SELECT * FROM existing_syllabi
      UNION ALL
      SELECT * FROM missing_snow_courses
    ) results
    ORDER BY source_order, COALESCE(list_data->>'title', list_data->>'course_name') ASC NULLS LAST
    """

    case DbHelpers.run_sql(sql, %{"email" => email, "term_id" => term_id}) do
      {:error, _} = err -> err
      [] -> {:ok, [], nil}
      rows -> {:ok, Enum.map(rows, & &1["list_data"]), oldest_cached_at(rows)}
    end
  end

  def get_detail(code), do: get_detail(code, term_id: nil)

  def get_detail(code, term_id: term_id) do
    sql = """
    SELECT detail_data, detail_cached_at
    FROM syllabi
    WHERE code = $(code)
      AND detail_data IS NOT NULL
      AND ($(term_id)::text IS NULL OR term_id = $(term_id))
    """

    case DbHelpers.run_sql(sql, %{"code" => code, "term_id" => term_id}) do
      {:error, _} = err -> err
      [] -> {:ok, nil, nil}
      [row | _] -> {:ok, row["detail_data"], row["detail_cached_at"]}
    end
  end

  defp oldest_cached_at(rows) do
    rows
    |> Enum.min_by(fn row ->
      case row["list_cached_at"] do
        %DateTime{} = dt -> DateTime.to_unix(dt)
        _ -> :os.system_time(:second)
      end
    end)
    |> Map.get("list_cached_at")
  end

  def count_in_scope do
    sql = """
    SELECT COUNT(*)::integer AS total
    FROM syllabi
    """

    case DbHelpers.run_sql(sql, %{}) do
      [%{"total" => total}] -> {:ok, total}
      {:error, _} = err -> err
    end
  end

  defp extract_linked_emails(nil, linked_email) when is_binary(linked_email),
    do: [linked_email]

  defp extract_linked_emails(nil, _), do: []

  defp extract_linked_emails(detail_data, linked_email) when is_map(detail_data) do
    emails_from_detail =
      case detail_data["editors"] do
        editors when is_list(editors) ->
          Enum.flat_map(editors, fn editor ->
            case editor["accounts"] do
              accounts when is_list(accounts) ->
                Enum.map(accounts, & &1["email"])
                |> Enum.filter(&is_binary/1)

              _ ->
                []
            end
          end)

        _ ->
          []
      end

    extra_email = if is_binary(linked_email), do: [linked_email], else: []

    (emails_from_detail ++ extra_email)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
  end

  defp extract_linked_emails(_, linked_email) when is_binary(linked_email),
    do: [linked_email]

  defp extract_linked_emails(_, _), do: []
end
