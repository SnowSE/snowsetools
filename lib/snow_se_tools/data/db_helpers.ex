defmodule SnowSeTools.Data.DbHelpers do
  require Logger
  @get_named_param ~r/\$\((\w+)\)/

  def run_sql(sql, params, schema) when not is_nil(schema) do
    run_sql(sql, params) |> validate_rows(schema)
  end

  def run_sql(sql, params) do
    original_sql = sql
    original_params = params
    {sql, params} = named_params_to_positional_params(sql, params)

    try do
      result = Ecto.Adapters.SQL.query!(SnowSeTools.Repo, sql, params)

      Enum.map(result.rows || [], fn row ->
        Enum.zip(result.columns, row)
        |> Enum.map(fn {col, val} -> {col, format_uuid_binary(val)} end)
        |> Enum.into(%{})
      end)
    rescue
      exception ->
        error_message = extract_error_message(exception)
        Logger.error("Database error: #{error_message}")
        Logger.error("Failed SQL: #{original_sql}")
        Logger.error("SQL params: #{inspect(original_params, pretty: true)}")
        {:error, error_message}
    end
  end

  defp extract_error_message(exception) do
    msg =
      case exception do
        %{message: msg} when is_binary(msg) and byte_size(msg) > 0 -> msg
        _ -> nil
      end

    msg || Exception.message(exception)
  end

  def named_params_to_positional_params(query, params) do
    param_occurrences = Regex.scan(@get_named_param, query)

    {param_to_index, ordered_values} =
      Enum.reduce(param_occurrences, {%{}, []}, fn [_full, param_name], {index_map, values} ->
        if Map.has_key?(index_map, param_name) do
          {index_map, values}
        else
          next_index = map_size(index_map) + 1
          param_value = Map.fetch!(params, param_name)
          {Map.put(index_map, param_name, next_index), values ++ [param_value]}
        end
      end)

    positional_sql =
      Regex.replace(@get_named_param, query, fn _full, param_name ->
        "$#{param_to_index[param_name]}"
      end)

    {positional_sql, ordered_values}
  end

  defp format_uuid_binary(<<a::4-bytes, b::2-bytes, c::2-bytes, d::2-bytes, e::6-bytes>>) do
    [a, b, c, d, e]
    |> Enum.map(&Base.encode16(&1, case: :lower))
    |> Enum.join("-")
  end

  defp format_uuid_binary(val), do: val

  @doc """
  Runs a transaction. Inside the callback, use `run_sql/2,3` as normal — any
  `{:error, _}` return will automatically roll back the transaction. If the
  callback returns `:ok` or `{:ok, value}`, the transaction commits and that
  value is returned unwrapped.

  Example:

      DbHelpers.transaction(fn ->
        DbHelpers.run_sql("DELETE FROM foo WHERE id = $(id)", %{"id" => id})
        {:ok, DbHelpers.run_sql("INSERT INTO bar ...", %{...})}
      end)
  """
  def transaction(fun) when is_function(fun, 0) do
    SnowSeTools.Repo.transaction(fn ->
      result =
        try do
          fun.()
        rescue
          e ->
            Logger.error("Transaction callback raised: #{Exception.message(e)}")
            {:error, e}
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

  defp validate_rows({:error, _} = err, _schema), do: err

  defp validate_rows(rows, schema) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case Zoi.parse(schema, row, coerce: true) do
        {:ok, valid} ->
          {:cont, {:ok, [valid | acc]}}

        {:error, errors} ->
          Logger.error("Schema validation error: #{inspect(errors)}")
          {:halt, {:error, :validation_error}}
      end
    end)
    |> then(fn
      {:ok, valid_rows} -> Enum.reverse(valid_rows)
      error -> error
    end)
  end
end
