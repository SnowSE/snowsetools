defmodule SnowSeTools.AI.SettingsDb do
  @moduledoc """
  The one row that can override the AI endpoint, model and key set in the
  environment, so an admin can point the app at a different server without a
  redeploy.

  Every column is nullable and a NULL means "use the environment value". That
  keeps `prod.env` the source of truth until somebody deliberately overrides a
  field, and makes clearing an override a matter of writing NULL back rather
  than remembering what the environment said.

  The table holds at most one row: `id` is a boolean fixed to TRUE, so a second
  insert collides with the primary key instead of silently creating a rival set
  of settings.
  """

  require Logger

  alias SnowSeTools.Data.DbHelpers

  @fields ~w(endpoint model api_key)a

  def fields, do: @fields

  def bootstrap_tables do
    Enum.reduce_while(table_statements(), :ok, fn {step, sql}, :ok ->
      case DbHelpers.query(sql, %{}) do
        {:ok, _rows} ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.error("AI settings bootstrap failed step=#{step} reason=#{inspect(reason)}")
          {:halt, {:error, reason}}
      end
    end)
  end

  defp table_statements do
    [
      {"create ai settings",
       """
       CREATE TABLE IF NOT EXISTS ai_settings (
         id         BOOLEAN     PRIMARY KEY DEFAULT TRUE CHECK (id),
         endpoint   TEXT,
         model      TEXT,
         api_key    TEXT,
         updated_by TEXT,
         updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
       )
       """}
    ]
  end

  @doc """
  The stored overrides, or `nil` for every field when nothing has been saved.

  Answers `{:ok, map}` even when the table is empty so callers have one shape
  to handle.
  """
  def get do
    sql = """
    SELECT endpoint, model, api_key, updated_by,
      to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS updated_at
    FROM ai_settings
    WHERE id
    """

    case DbHelpers.query(sql, %{}) do
      {:ok, [row]} -> {:ok, row}
      {:ok, []} -> {:ok, empty()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp empty do
    %{
      "endpoint" => nil,
      "model" => nil,
      "api_key" => nil,
      "updated_by" => nil,
      "updated_at" => nil
    }
  end

  @doc """
  Writes the overrides in `changes`, leaving any field it does not mention
  alone.

  A field set to `nil` is cleared back to the environment value. That is the
  difference between "the admin left the API key box blank, so keep the key we
  already have" (omit it) and "the admin pressed Use environment value"
  (include it as nil) -- the form cannot tell those apart by content, because a
  stored key is never rendered back for it to resubmit.
  """
  def put(changes, updated_by: updated_by) when is_map(changes) do
    changes = Map.take(changes, @fields)

    {columns, params} =
      Enum.reduce(changes, {[], %{"updated_by" => updated_by}}, fn {field, value},
                                                                   {columns, params} ->
        name = Atom.to_string(field)
        {[name | columns], Map.put(params, name, blank_to_nil(value))}
      end)

    insert_columns = ["id", "updated_by", "updated_at" | columns]

    insert_values =
      ["TRUE", "$(updated_by)", "NOW()" | Enum.map(columns, &"$(#{&1})")]

    updates =
      ["updated_by = $(updated_by)", "updated_at = NOW()"] ++
        Enum.map(columns, &"#{&1} = $(#{&1})")

    sql = """
    INSERT INTO ai_settings (#{Enum.join(insert_columns, ", ")})
    VALUES (#{Enum.join(insert_values, ", ")})
    ON CONFLICT (id) DO UPDATE SET #{Enum.join(updates, ", ")}
    """

    case DbHelpers.query(sql, params) do
      {:ok, _rows} -> get()
      {:error, reason} -> {:error, reason}
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
