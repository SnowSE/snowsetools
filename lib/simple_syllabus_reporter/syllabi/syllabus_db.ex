defmodule SimpleSyllabusReporter.Syllabi.SyllabusDB do
  require Logger
  alias SimpleSyllabusReporter.Data.DbHelpers

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
      (code, title, course_name, term_name, term_id, org_id, linked_emails, editors, list_data, detail_data, list_cached_at, detail_cached_at, updated_at)
    VALUES
      ($(code), $(title), $(course_name), $(term_name), $(term_id), $(org_id),
       $(linked_emails)::text[],
       $(editors)::jsonb, $(list_data)::jsonb, $(detail_data)::jsonb,
       NOW(), NOW(), NOW())
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

  def list_populated_org_ids do
    sql = "SELECT DISTINCT org_id FROM syllabi WHERE org_id IS NOT NULL"

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, Enum.map(rows, & &1["org_id"])}
    end
  end

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

  # Extract email addresses from detail_data's editors field.
  #
  # The detail_data editors structure is:
  # [
  #   {
  #     "role": {...},
  #     "accounts": [{"email": "...", ...}]
  #   }
  # ]
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
