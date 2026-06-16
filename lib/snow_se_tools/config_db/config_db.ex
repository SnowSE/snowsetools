defmodule SnowSeTools.ConfigDB do
  alias SnowSeTools.Data.DbHelpers
  alias SnowSeTools.Syllabi.AvailableTermsDb

  @current_term_key "selected_term_id"
  @pubsub SnowSeTools.PubSub
  @topic "config:term_changed"

  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)
  def unsubscribe, do: Phoenix.PubSub.unsubscribe(@pubsub, @topic)

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
      {:error, _} = err ->
        err

      _ ->
        Phoenix.PubSub.broadcast(@pubsub, @topic, {:term_changed, nil})
        :ok
    end
  end

  def set_current_term(term_id) when is_binary(term_id) do
    sql = """
    INSERT INTO site_config (key, value, inserted_at, updated_at)
    VALUES ($(key), $(value), NOW(), NOW())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
    """

    case DbHelpers.run_sql(sql, %{"key" => @current_term_key, "value" => term_id}) do
      {:error, _} = err ->
        err

      _ ->
        Phoenix.PubSub.broadcast(@pubsub, @topic, {:term_changed, term_id})
        :ok
    end
  end

  @doc "Returns all available terms from the syllabus_available_terms table, sorted by term_id descending."
  def list_available_terms do
    case AvailableTermsDb.list_active_terms() do
      {:ok, terms} ->
        Enum.map(terms, fn {term_id, term_name} ->
          %{"term_id" => term_id, "term_name" => term_name}
        end)
        |> Enum.sort_by(& &1["term_id"], :desc)

      {:error, _} ->
        []
    end
  end
end
