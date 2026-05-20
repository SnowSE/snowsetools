defmodule SimpleSyllabusReporter.Syllabi.SyllabusDB do
  require Logger
  alias SimpleSyllabusReporter.Data.DbHelpers

  @doc """
  Upserts a batch of list-item docs into the syllabi table.

  Options:
    - `:org_id` — entity_id of the org these syllabi were fetched under
    - `:linked_email` — email address this search was performed with
  """
  def upsert_list_items([], _opts), do: :ok

  def upsert_list_items(docs, opts) do
    org_id = Keyword.get(opts, :org_id)
    linked_email = Keyword.get(opts, :linked_email)

    sql = """
    INSERT INTO syllabi
      (code, title, course_name, term_name, term_id, org_id, linked_emails, editors, list_data, list_cached_at, updated_at)
    SELECT
      d.code,
      d.title,
      d.course_name,
      d.term_name,
      d.term_id,
      d.org_id,
      CASE WHEN $(linked_email)::text IS NOT NULL
           THEN ARRAY[$(linked_email)::text]
           ELSE '{}'::text[]
      END,
      parsed.editors,
      parsed.list_data,
      NOW(),
      NOW()
    FROM UNNEST(
      $(codes)::text[],
      $(titles)::text[],
      $(course_names)::text[],
      $(term_names)::text[],
      $(term_ids)::text[],
      $(org_ids)::text[],
      $(editors_list)::text[],
      $(list_data_list)::text[]
    ) AS d(code, title, course_name, term_name, term_id, org_id, editors_json, list_data_json),
    LATERAL (SELECT editors_json::jsonb AS editors, list_data_json::jsonb AS list_data) AS parsed
    ON CONFLICT (code) DO UPDATE SET
      title          = EXCLUDED.title,
      course_name    = EXCLUDED.course_name,
      term_name      = EXCLUDED.term_name,
      term_id        = EXCLUDED.term_id,
      org_id         = COALESCE(EXCLUDED.org_id, syllabi.org_id),
      linked_emails  = (SELECT array(SELECT DISTINCT unnest(syllabi.linked_emails || EXCLUDED.linked_emails))),
      editors        = EXCLUDED.editors,
      list_data      = EXCLUDED.list_data,
      list_cached_at = NOW(),
      updated_at     = NOW()
    """

    params = %{
      "codes" => Enum.map(docs, & &1["code"]),
      "titles" => Enum.map(docs, & &1["title"]),
      "course_names" => Enum.map(docs, & &1["course_name"]),
      "term_names" => Enum.map(docs, & &1["term_name"]),
      "term_ids" => Enum.map(docs, & &1["term_id"]),
      "org_ids" => Enum.map(docs, fn doc -> org_id || doc["entity_id"] end),
      "editors_list" => Enum.map(docs, fn doc -> Jason.encode!(doc["editors"] || []) end),
      "list_data_list" => Enum.map(docs, &Jason.encode!/1),
      "linked_email" => linked_email
    }

    case DbHelpers.run_sql(sql, params) do
      {:error, _} = err -> err
      _ -> :ok
    end
  end

  @doc "Upserts detail data for a syllabus code."
  def upsert_detail(code, doc) do
    sql = """
    INSERT INTO syllabi (code, detail_data, detail_cached_at, updated_at)
    VALUES ($(code), $(detail_data), NOW(), NOW())
    ON CONFLICT (code) DO UPDATE SET
      detail_data      = EXCLUDED.detail_data,
      detail_cached_at = EXCLUDED.detail_cached_at,
      updated_at       = NOW()
    """

    case DbHelpers.run_sql(sql, %{"code" => code, "detail_data" => doc}) do
      {:error, _} = err -> err
      _ -> :ok
    end
  end

  @doc """
  Returns all cached list items for an org, scoped to the currently selected term
  (as stored in site_config). If no term is selected, all terms are returned.
  Result: `{:ok, docs, oldest_cached_at}` where oldest_cached_at is nil when empty.
  """
  def list_by_org(org_id) when is_binary(org_id) do
    sql = """
    SELECT s.list_data, s.list_cached_at
    FROM syllabi s
    LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
    WHERE s.org_id = ANY($(org_ids)::text[])
      AND (sc.value IS NULL OR s.term_id = sc.value)
    ORDER BY COALESCE(s.title, s.course_name) ASC NULLS LAST
    """

    case DbHelpers.run_sql(sql, %{"org_ids" => [org_id]}) do
      {:error, _} = err -> err
      [] -> {:ok, [], nil}
      rows -> {:ok, Enum.map(rows, & &1["list_data"]), oldest_cached_at(rows)}
    end
  end

  @doc "Returns the distinct set of org_ids that have syllabi in the database."
  def list_populated_org_ids do
    sql = "SELECT DISTINCT org_id FROM syllabi WHERE org_id IS NOT NULL"

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, Enum.map(rows, & &1["org_id"])}
    end
  end

  @doc """
  Returns all cached list items for a given editor email, scoped to the currently selected term.
  Result: `{:ok, docs, oldest_cached_at}` where oldest_cached_at is nil when empty.
  """
  def list_by_editor_email(email) do
    sql = """
    SELECT s.list_data, s.list_cached_at
    FROM syllabi s
    LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
    WHERE $(email) = ANY(s.linked_emails)
      AND (sc.value IS NULL OR s.term_id = sc.value)
    ORDER BY COALESCE(s.title, s.course_name) ASC NULLS LAST
    """

    case DbHelpers.run_sql(sql, %{"email" => email}) do
      {:error, _} = err -> err
      [] -> {:ok, [], nil}
      rows -> {:ok, Enum.map(rows, & &1["list_data"]), oldest_cached_at(rows)}
    end
  end

  @doc """
  Returns the cached detail for a code, or `{:ok, nil, nil}` if not cached.
  Result: `{:ok, doc_or_nil, detail_cached_at_or_nil}`
  """
  def get_detail(code) do
    sql = """
    SELECT detail_data, detail_cached_at
    FROM syllabi
    WHERE code = $(code) AND detail_data IS NOT NULL
    """

    case DbHelpers.run_sql(sql, %{"code" => code}) do
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

  @doc "Counts syllabi in scope (scoped to selected term, or all if none set)."
  def count_in_scope do
    sql = """
    SELECT COUNT(*)::integer AS total
    FROM syllabi s
    LEFT JOIN site_config sc ON sc.key = 'selected_term_id'
    WHERE sc.value IS NULL OR s.term_id = sc.value
    """

    case DbHelpers.run_sql(sql, %{}) do
      [%{"total" => total}] -> {:ok, total}
      {:error, _} = err -> err
    end
  end
end
