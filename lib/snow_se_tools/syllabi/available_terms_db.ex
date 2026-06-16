defmodule SnowSeTools.Syllabi.AvailableTermsDb do
  require Logger
  alias SnowSeTools.Data.DbHelpers

  def upsert_terms(terms) when is_list(terms) do
    if Enum.empty?(terms) do
      :ok
    else
      sql = """
      INSERT INTO syllabus_available_terms (term_id, term_name, status, cached_at, updated_at)
      SELECT
        d.term_id,
        d.term_name,
        'active',
        NOW(),
        NOW()
      FROM UNNEST(
        $(term_ids)::text[],
        $(term_names)::text[]
      ) AS d(term_id, term_name)
      ON CONFLICT (term_id) DO UPDATE SET
        term_name = EXCLUDED.term_name,
        status = 'active',
        cached_at = NOW(),
        updated_at = NOW()
      """

      params = %{
        "term_ids" => Enum.map(terms, fn {term_id, _} -> term_id end),
        "term_names" => Enum.map(terms, fn {_, term_name} -> term_name end)
      }

      case DbHelpers.run_sql(sql, params) do
        {:error, reason} -> {:error, reason}
        _rows -> :ok
      end
    end
  end

  def list_active_terms do
    sql = """
    SELECT term_id, term_name
    FROM syllabus_available_terms
    WHERE status = 'active'
    ORDER BY term_id DESC
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err ->
        err

      rows ->
        terms =
          Enum.map(rows, fn row ->
            {row["term_id"], row["term_name"]}
          end)

        {:ok, terms}
    end
  end

  def get_term(term_id) do
    sql = """
    SELECT term_id, term_name, status
    FROM syllabus_available_terms
    WHERE term_id = $(term_id)
    """

    case DbHelpers.run_sql(sql, %{"term_id" => term_id}) do
      {:error, _} = err ->
        err

      [row] ->
        {:ok,
         %{
           term_id: row["term_id"],
           term_name: row["term_name"],
           status: row["status"]
         }}

      [] ->
        nil
    end
  end

  def count_active_terms do
    sql = "SELECT COUNT(*) as count FROM syllabus_available_terms WHERE status = 'active'"

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err ->
        err

      [row] ->
        {:ok, row["count"]}
    end
  end
end
