defmodule SnowSeTools.Data.DbHelpers do
  @moduledoc """
  Raw SQL against `SnowSeTools.Repo`, with named parameters.

  Write `$(name)` in the SQL and pass `%{"name" => value}`; the names are
  rewritten to Postgrex's positional `$1` at call time, so a query reads the
  same as the map beside it and repeating a parameter costs nothing.

  Every query answers `{:ok, rows} | {:error, reason}`. Success and failure used
  to share one channel — a bare list for rows, a tuple for errors — which meant
  a caller that piped the result into `Enum` blew up on a database error
  instead of handling it. `reason` is one of the atoms below rather than a
  message string, so callers can tell the cases apart:

    * `:not_unique` — a unique constraint rejected the write
    * `:missing_reference` — a foreign key had nothing to point at
    * `:missing_param` — the SQL named a parameter the map did not carry
    * `:validation_error` — rows came back in a shape the Zoi schema refuses
    * `{:query_failed, message}` — anything else, message already logged
  """

  require Logger

  @get_named_param ~r/\$\((\w+)\)/

  @type row :: %{optional(String.t()) => term()}
  @type reason ::
          :not_unique
          | :missing_reference
          | :missing_param
          | :validation_error
          | {:query_failed, String.t()}

  @spec query(String.t(), map(), term()) :: {:ok, [row()]} | {:error, reason()}
  def query(sql, params, nil), do: query(sql, params)

  def query(sql, params, schema) do
    case query(sql, params) do
      {:ok, rows} -> validate_rows(rows, schema)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec query(String.t(), map()) :: {:ok, [row()]} | {:error, reason()}
  def query(sql, params) do
    with {:ok, positional_sql, positional_params} <- positional(sql, params) do
      run(sql: sql, positional_sql: positional_sql, params: positional_params, names: params)
    end
  end

  @doc """
  The rows, or `default` when the query fails. For reads where an empty result
  and a broken database lead to the same screen; anything that writes, or that
  must tell the user why it could not answer, should match on `query/2,3`.
  """
  def query_or(sql, params, default), do: query_or(sql, params, nil, default)

  def query_or(sql, params, schema, default) do
    case query(sql, params, schema) do
      {:ok, rows} -> rows
      {:error, _reason} -> default
    end
  end

  defp run(sql: sql, positional_sql: positional_sql, params: params, names: names) do
    {:ok, Ecto.Adapters.SQL.query!(SnowSeTools.Repo, positional_sql, params) |> to_rows()}
  rescue
    exception ->
      message = extract_error_message(exception)
      Logger.error("Database error: #{message}")
      Logger.error("Failed SQL: #{sql}")
      # Values are redacted: several tables hold student PII and credentials.
      Logger.error("SQL param names: #{inspect(Map.keys(names))}")

      {:error, classify(exception, message)}
  end

  defp to_rows(result) do
    Enum.map(result.rows || [], fn row ->
      result.columns |> Enum.zip(row) |> Map.new()
    end)
  end

  # Postgrex reports constraint violations as codes; turning the common ones
  # into atoms means a caller can say "that name is taken" instead of matching
  # on the text of a Postgres message.
  defp classify(%Postgrex.Error{postgres: %{code: :unique_violation}}, _message), do: :not_unique

  defp classify(%Postgrex.Error{postgres: %{code: :foreign_key_violation}}, _message),
    do: :missing_reference

  defp classify(_exception, message), do: {:query_failed, message}

  defp extract_error_message(exception) do
    case exception do
      %{message: message} when is_binary(message) and message != "" -> message
      _other -> Exception.message(exception)
    end
  end

  defp positional(sql, params) do
    {names, ordered_names} =
      @get_named_param
      |> Regex.scan(sql)
      |> Enum.reduce({%{}, []}, fn [_full, name], {indexes, ordered} ->
        if Map.has_key?(indexes, name) do
          {indexes, ordered}
        else
          {Map.put(indexes, name, map_size(indexes) + 1), [name | ordered]}
        end
      end)

    ordered_names = Enum.reverse(ordered_names)

    case Enum.reject(ordered_names, &Map.has_key?(params, &1)) do
      [] ->
        positional_sql =
          Regex.replace(@get_named_param, sql, fn _full, name -> "$#{names[name]}" end)

        {:ok, positional_sql, Enum.map(ordered_names, &Map.fetch!(params, &1))}

      missing ->
        # Raising here would escape the caller's error handling entirely, which
        # is what this used to do by expanding parameters outside the rescue.
        Logger.error("SQL is missing parameters: #{inspect(missing)}")
        Logger.error("Failed SQL: #{sql}")
        {:error, :missing_param}
    end
  end

  @doc """
  Runs a transaction. Inside the callback, use `query/2,3` as normal — any
  `{:error, _}` return rolls the transaction back. If the callback returns
  `:ok` or `{:ok, value}`, the transaction commits and that value is returned
  unwrapped.

      DbHelpers.transaction(fn ->
        with {:ok, _} <- DbHelpers.query("DELETE FROM foo WHERE id = $(id)", %{"id" => id}) do
          DbHelpers.query("INSERT INTO bar ...", %{})
        end
      end)
  """
  def transaction(fun) when is_function(fun, 0) do
    SnowSeTools.Repo.transaction(fn ->
      result =
        try do
          fun.()
        rescue
          exception ->
            Logger.error("Transaction callback raised: #{Exception.message(exception)}")
            {:error, {:query_failed, Exception.message(exception)}}
        end

      case result do
        {:error, reason} ->
          Logger.error("Transaction rolling back reason=#{inspect(reason)}")
          SnowSeTools.Repo.rollback(reason)

        other ->
          other
      end
    end)
    |> case do
      {:ok, result} ->
        result

      {:error, reason} = err ->
        Logger.error("Transaction failed reason=#{inspect(reason)}")
        err
    end
  end

  defp validate_rows(rows, schema) do
    rows
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, acc} ->
      case Zoi.parse(schema, row, coerce: true) do
        {:ok, valid} ->
          {:cont, {:ok, [valid | acc]}}

        {:error, errors} ->
          Logger.error("Schema validation error: #{inspect(errors)}")
          {:halt, {:error, :validation_error}}
      end
    end)
    |> case do
      {:ok, valid_rows} -> {:ok, Enum.reverse(valid_rows)}
      {:error, reason} -> {:error, reason}
    end
  end
end
