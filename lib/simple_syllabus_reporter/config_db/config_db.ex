defmodule SimpleSyllabusReporter.ConfigDB do
  alias SimpleSyllabusReporter.Data.DbHelpers

  @current_term_key "selected_term_id"

  @doc "Returns the currently selected term_id, or nil if none is set."
  def get_current_term do
    sql = "SELECT value FROM site_config WHERE key = $(key)"

    case DbHelpers.run_sql(sql, %{"key" => @current_term_key}) do
      [%{"value" => value}] -> value
      [] -> nil
      {:error, _} = err -> err
    end
  end

  @doc "Sets the current term. Pass nil to clear the selection."
  def set_current_term(nil) do
    sql = "DELETE FROM site_config WHERE key = $(key)"

    case DbHelpers.run_sql(sql, %{"key" => @current_term_key}) do
      {:error, _} = err -> err
      _ -> :ok
    end
  end

  def set_current_term(term_id) when is_binary(term_id) do
    sql = """
    INSERT INTO site_config (key, value, inserted_at, updated_at)
    VALUES ($(key), $(value)::uuid::text, NOW(), NOW())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
    """

    case DbHelpers.run_sql(sql, %{"key" => @current_term_key, "value" => term_id}) do
      {:error, _} = err -> err
      _ -> :ok
    end
  end

  @doc "Returns all distinct terms present in the syllabi table as a list of maps with term_id and term_name."
  def list_available_terms do
    sql = """
    SELECT DISTINCT term_id, term_name
    FROM syllabi
    WHERE term_id IS NOT NULL
    """

    season_order = %{"spring" => 1, "summer" => 2, "fall" => 3}

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err ->
        err

      rows ->
        Enum.sort_by(
          rows,
          fn %{"term_name" => name} ->
            year = Regex.run(~r/\d{4}/, name || "") |> List.first() |> then(&(&1 || "0"))

            season =
              Map.get(
                season_order,
                name |> String.downcase() |> String.split() |> List.first(),
                9
              )

            {year, season}
          end,
          :desc
        )
    end
  end
end
