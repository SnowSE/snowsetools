defmodule SimpleSyllabusReporter.Reports.RequiredElement do
  require Logger
  alias SimpleSyllabusReporter.Data.DbHelpers

  @schema Zoi.object(%{
            "name" => Zoi.string(),
            "description" => Zoi.default(Zoi.optional(Zoi.string()), "")
          })

  defp validate(attrs) do
    string_attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    Zoi.parse(@schema, string_attrs)
  end

  # ---------------------------------------------------------------------------
  # Public CRUD
  # ---------------------------------------------------------------------------

  def list_all do
    sql = """
    SELECT id, name, description
    FROM required_elements
    ORDER BY name ASC
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err -> err
      rows -> {:ok, rows}
    end
  end

  def get(id) do
    sql = """
    SELECT id, name, description
    FROM required_elements
    WHERE id = $(id)
    """

    case DbHelpers.run_sql(sql, %{"id" => id}) do
      {:error, _} = err -> err
      [row | _] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  def create(attrs) do
    case validate(attrs) do
      {:ok, d} ->
        sql = """
        INSERT INTO required_elements (name, description)
        VALUES ($(name), $(description))
        RETURNING id, name, description
        """

        case DbHelpers.run_sql(sql, %{
               "name" => d["name"],
               "description" => d["description"]
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
        UPDATE required_elements
        SET name        = $(name),
            description = $(description),
            updated_at  = NOW()
        WHERE id = $(id)
        RETURNING id, name, description
        """

        case DbHelpers.run_sql(sql, %{
               "id" => id,
               "name" => d["name"],
               "description" => d["description"]
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
    sql = "DELETE FROM required_elements WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => id}) do
      {:error, _} = err -> err
      _ -> :ok
    end
  end
end
