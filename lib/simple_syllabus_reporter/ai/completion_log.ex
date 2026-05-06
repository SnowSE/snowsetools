defmodule SimpleSyllabusReporter.AI.CompletionLog do
  require Logger
  alias SimpleSyllabusReporter.Data.DbHelpers

  def record(topic, event, model, endpoint, messages, result) do
    {status, result_text} =
      case result do
        {:ok, content} when is_binary(content) -> {"ok", content}
        {:ok, content} -> {"ok", Jason.encode!(content)}
        {:error, reason} -> {"error", inspect(reason)}
      end

    sql = """
    INSERT INTO ai_completions (topic, event, model, endpoint, messages, status, result)
    VALUES ($(topic), $(event), $(model), $(endpoint), $(messages), $(status), $(result))
    """

    case DbHelpers.run_sql(sql, %{
           "topic" => topic,
           "event" => inspect(event),
           "model" => model,
           "endpoint" => endpoint,
           "messages" => messages,
           "result" => result_text,
           "status" => status
         }) do
      {:error, reason} -> Logger.error("Failed to log AI completion: #{inspect(reason)}")
      _ -> :ok
    end
  end

  def list_recent(limit \\ 100) do
    sql = """
    SELECT id, topic, event, model, endpoint, messages, status, result, inserted_at
    FROM ai_completions
    ORDER BY inserted_at DESC
    LIMIT $(limit)
    """

    case DbHelpers.run_sql(sql, %{"limit" => limit}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def get(id) do
    sql = """
    SELECT id, topic, event, model, endpoint, messages, status, result, inserted_at
    FROM ai_completions
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(sql, %{"id" => id}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end
end
