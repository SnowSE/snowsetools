defmodule SnowSeTools.AI.CompletionLog do
  require Logger
  alias SnowSeTools.Data.DbHelpers

  def record(topic, event, model, endpoint, messages, result, thinking \\ nil) do
    {status, result_text} =
      case result do
        {:ok, content} when is_binary(content) -> {"ok", content}
        {:ok, content} -> {"ok", Jason.encode!(content)}
        {:error, reason} -> {"error", inspect(reason)}
      end

    sql = """
    INSERT INTO syllabus_ai_completions (topic, event, model, endpoint, messages, status, result, thinking)
    VALUES ($(topic), $(event), $(model), $(endpoint), $(messages), $(status), $(result), $(thinking))
    """

    case DbHelpers.query(sql, %{
           "topic" => topic,
           "event" => inspect(event),
           "model" => model,
           "endpoint" => endpoint,
           "messages" => messages,
           "result" => result_text,
           "status" => status,
           "thinking" => thinking || ""
         }) do
      {:error, reason} ->
        Logger.error(
          "Failed to log AI completion topic=#{topic} event=#{inspect(event)} reason=#{inspect(reason)}"
        )

      {:ok, rows} when is_list(rows) ->
        :ok
    end
  end

  def list_recent(limit \\ 100) do
    sql = """
    SELECT id, topic, event, model, endpoint, messages, status, result, thinking, inserted_at
    FROM syllabus_ai_completions
    ORDER BY inserted_at DESC
    LIMIT $(limit)
    """

    case DbHelpers.query(sql, %{"limit" => limit}) do
      {:error, _} = err -> err
      {:ok, rows} -> {:ok, rows}
    end
  end

  def get(id) do
    sql = """
    SELECT id, topic, event, model, endpoint, messages, status, result, thinking, inserted_at
    FROM syllabus_ai_completions
    WHERE id = $(id)
    """

    case DbHelpers.query(sql, %{"id" => id}) do
      {:error, _} = err -> err
      {:ok, [row | _]} -> {:ok, row}
      {:ok, []} -> {:error, :not_found}
    end
  end
end
