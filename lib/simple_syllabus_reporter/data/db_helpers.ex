defmodule SimpleSyllabusReporter.Data.DbHelpers do
  require Logger
  @get_named_param ~r/\$\((\w+)\)/

  @doc """
  Runs SQL with named parameters (e.g. `$(name)`) and validates each row
  against the given Zoi schema, returning `{:error, :db_error}` or a list of
  validated structs/maps.
  """
  def run_sql(sql, params, schema) when not is_nil(schema) do
    run_sql(sql, params) |> validate_rows(schema)
  end

  @doc """
  Runs SQL with named parameters (e.g. `$(name)`) and returns a list of row
  maps with string keys, or `{:error, :db_error}`.
  """
  def run_sql(sql, params) do
    original_sql = sql
    original_params = params
    {sql, params} = named_params_to_positional_params(sql, params)

    try do
      result = Ecto.Adapters.SQL.query!(SimpleSyllabusReporter.Repo, sql, params)

      Enum.map(result.rows || [], fn row ->
        Enum.zip(result.columns, row)
        |> Enum.map(fn {col, val} -> {col, format_uuid_binary(val)} end)
        |> Enum.into(%{})
      end)
    rescue
      exception ->
        Logger.error("Database error: #{Exception.message(exception)}")
        Logger.error("Failed SQL: #{original_sql}")
        Logger.error("SQL params: #{inspect(original_params, pretty: true)}")
        {:error, :db_error}
    end
  end

  @doc """
  Converts `$(param_name)` placeholders to positional `$1`, `$2`, … params
  expected by Postgrex. Repeated occurrences of the same name reuse the same
  positional index.
  """
  def named_params_to_positional_params(query, params) do
    param_occurrences = Regex.scan(@get_named_param, query)

    {param_to_index, ordered_values} =
      Enum.reduce(param_occurrences, {%{}, []}, fn [_full, param_name], {index_map, values} ->
        if Map.has_key?(index_map, param_name) do
          {index_map, values}
        else
          next_index = map_size(index_map) + 1
          param_value = params |> Map.fetch!(param_name) |> parse_uuid_string_to_binary()
          {Map.put(index_map, param_name, next_index), values ++ [param_value]}
        end
      end)

    positional_sql =
      Regex.replace(@get_named_param, query, fn _full, param_name ->
        "$#{param_to_index[param_name]}"
      end)

    {positional_sql, ordered_values}
  end

  # Postgrex expects UUID params as 16-byte binaries; convert formatted strings.
  defp parse_uuid_string_to_binary(
         <<_::binary-size(8), ?-, _::binary-size(4), ?-, _::binary-size(4), ?-, _::binary-size(4),
           ?-, _::binary-size(12)>> = val
       ) do
    val |> String.replace("-", "") |> Base.decode16!(case: :lower)
  end

  defp parse_uuid_string_to_binary(val), do: val

  defp format_uuid_binary(<<a::4-bytes, b::2-bytes, c::2-bytes, d::2-bytes, e::6-bytes>>) do
    [a, b, c, d, e]
    |> Enum.map(&Base.encode16(&1, case: :lower))
    |> Enum.join("-")
  end

  defp format_uuid_binary(val), do: val

  defp validate_rows({:error, :db_error}, _schema), do: {:error, :db_error}

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
