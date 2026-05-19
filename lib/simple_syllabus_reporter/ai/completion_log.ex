defmodule SimpleSyllabusReporter.AI.CompletionLog do
  require Logger
  alias SimpleSyllabusReporter.Data.DbHelpers

  def record_pending(topic, event, messages, opts) do
    event_term = event |> :erlang.term_to_binary() |> Base.encode64()
    recovery_opts = encode_opts(opts)

    sql = """
    INSERT INTO ai_completions (topic, event, event_term, messages, recovery_opts, status, model, endpoint, result)
    VALUES ($(topic), $(event_str), $(event_term), $(messages), $(recovery_opts), 'pending', '', '', '')
    RETURNING id
    """

    case DbHelpers.run_sql(sql, %{
           "topic" => topic,
           "event_str" => inspect(event),
           "event_term" => event_term,
           "messages" => messages,
           "recovery_opts" => recovery_opts
         }) do
      [%{"id" => id}] -> {:ok, id}
      {:error, _} = err -> err
    end
  end

  def mark_completed(id, model, endpoint, result, thinking) do
    {status, result_text} =
      case result do
        {:ok, content} when is_binary(content) -> {"ok", content}
        {:ok, content} -> {"ok", Jason.encode!(content)}
        {:error, reason} -> {"error", inspect(reason)}
      end

    sql = """
    UPDATE ai_completions
    SET status = $(status), model = $(model), endpoint = $(endpoint),
        result = $(result), thinking = $(thinking)
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(sql, %{
           "id" => id,
           "status" => status,
           "model" => model,
           "endpoint" => endpoint,
           "result" => result_text,
           "thinking" => thinking || ""
         }) do
      {:error, reason} -> Logger.error("Failed to mark AI completion done: #{inspect(reason)}")
      _ -> :ok
    end
  end

  def list_pending do
    sql = """
    SELECT id, topic, event_term, messages, recovery_opts
    FROM ai_completions
    WHERE status = 'pending'
    ORDER BY inserted_at ASC
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def list_recent(limit \\ 100) do
    sql = """
    SELECT id, topic, event, model, endpoint, messages, status, result, thinking, inserted_at
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
    SELECT id, topic, event, model, endpoint, messages, status, result, thinking, inserted_at
    FROM ai_completions
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(sql, %{"id" => id}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  defp encode_opts([]), do: nil
  defp encode_opts(opts), do: Map.new(opts, fn {k, v} -> {Atom.to_string(k), v} end)

  def decode_opts(nil), do: []
  def decode_opts(map), do: Enum.map(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
end
