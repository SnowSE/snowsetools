defmodule SimpleSyllabusReporter.Reports.ReportInstructionDB do
  require Logger
  alias SimpleSyllabusReporter.Data.{DbHelpers, Uuid}

  @schema Zoi.object(%{
            "content" => Zoi.string()
          })

  defp validate(attrs) do
    string_attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    Zoi.parse(@schema, string_attrs)
  end

  def list_for_element(required_element_id) do
    sql = """
    SELECT id, required_element_id, content
    FROM required_element_report_instructions
    WHERE required_element_id = $(required_element_id)
    ORDER BY inserted_at ASC
    """

    case DbHelpers.run_sql(sql, %{"required_element_id" => Uuid.to_binary(required_element_id)}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def get(id) do
    sql = """
    SELECT id, required_element_id, content
    FROM required_element_report_instructions
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(id)}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  def create(required_element_id, attrs) do
    case validate(attrs) do
      {:ok, d} ->
        sql = """
        INSERT INTO required_element_report_instructions (required_element_id, content)
        VALUES ($(required_element_id), $(content))
        RETURNING id, required_element_id, content
        """

        case DbHelpers.run_sql(sql, %{
               "required_element_id" => Uuid.to_binary(required_element_id),
               "content" => d["content"]
             }) do
          {:error, _} = err -> err
          [row | _] -> {:ok, row}
          [] -> {:error, :not_found}
        end

      {:error, errors} ->
        {:error, {:validation, errors}}
    end
  end

  def update(id, attrs) do
    case validate(attrs) do
      {:ok, d} ->
        sql = """
        UPDATE required_element_report_instructions
        SET content    = $(content),
            updated_at = NOW()
        WHERE id = $(id)
        RETURNING id, required_element_id, content
        """

        case DbHelpers.run_sql(sql, %{
               "id" => Uuid.to_binary(id),
               "content" => d["content"]
             }) do
          {:error, _} = err -> err
          [row | _] -> {:ok, row}
          [] -> {:error, :not_found}
        end

      {:error, errors} ->
        {:error, {:validation, errors}}
    end
  end

  def delete(id) do
    sql = "DELETE FROM required_element_report_instructions WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(id)}) do
      {:error, _} = err -> err
      _ -> :ok
    end
  end
end
