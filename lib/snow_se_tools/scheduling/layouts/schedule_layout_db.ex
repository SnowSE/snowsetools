defmodule SnowSeTools.Scheduling.ScheduleLayoutDb do
  @moduledoc """
  Saved schedule viewer layouts: which owners and overlay groups are open, in
  what order, at what card size.

  Only the server-backed scopes live here. A `"user"` layout is private to the
  person who saved it; a `"shared"` layout is readable by anyone with
  scheduling access. Browser-local layouts never reach the server.

  `term_code` is provenance, not a filter — a layout records the term it was
  built in so the list can show it, but loading applies it to whatever term is
  selected.
  """

  require Logger

  alias SnowSeTools.Data.{DbHelpers, Uuid}

  @layout_schema Zoi.object(%{
                   "id" => Zoi.uuid(),
                   "name" => Zoi.string(),
                   "scope" => Zoi.string(),
                   "user_id" => Zoi.uuid(),
                   "owner_email" => Zoi.string(),
                   "term_code" => Zoi.optional(Zoi.string()),
                   "entries" => Zoi.any(),
                   "created_at" => Zoi.string(),
                   "updated_at" => Zoi.string()
                 })

  @columns """
    l.id,
    l.name,
    l.scope,
    l.user_id,
    u.email AS owner_email,
    l.term_code,
    l.entries,
    to_char(l.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
    to_char(l.updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS updated_at
  """

  def bootstrap_tables do
    statements = [
      """
      CREATE TABLE IF NOT EXISTS schedule_layouts (
        id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        name        TEXT        NOT NULL,
        scope       TEXT        NOT NULL DEFAULT 'user' CHECK (scope IN ('user', 'shared')),
        user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        term_code   TEXT,
        entries     JSONB       NOT NULL DEFAULT '[]'::jsonb,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
        inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_schedule_layouts_user_id ON schedule_layouts(user_id)
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_schedule_layouts_scope ON schedule_layouts(scope)
      """
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case DbHelpers.run_sql(sql, %{}) do
        {:error, reason} -> {:halt, {:error, reason}}
        _rows -> {:cont, :ok}
      end
    end)
  end

  @doc """
  Every layout `user_id` may load: their own private layouts plus every shared
  layout, whoever saved it.
  """
  def list_visible_to(user_id: user_id) when is_binary(user_id) do
    sql = """
    SELECT
    #{@columns}
    FROM schedule_layouts l
    JOIN users u ON u.id = l.user_id
    WHERE l.scope = 'shared' OR l.user_id = $(user_id)
    ORDER BY l.scope, lower(l.name)
    """

    case DbHelpers.run_sql(sql, %{"user_id" => Uuid.to_binary(user_id)}, @layout_schema) do
      {:error, _reason} = error -> error
      layouts -> {:ok, Enum.map(layouts, &decode_entries/1)}
    end
  end

  def get(layout_id) when is_binary(layout_id) do
    sql = """
    SELECT
    #{@columns}
    FROM schedule_layouts l
    JOIN users u ON u.id = l.user_id
    WHERE l.id = $(id)
    """

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(layout_id)}, @layout_schema) do
      [layout] -> {:ok, decode_entries(layout)}
      [] -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_select_result, other}}
    end
  end

  def create(name: name, scope: scope, user_id: user_id, term_code: term_code, entries: entries) do
    sql = """
    WITH inserted AS (
      INSERT INTO schedule_layouts (name, scope, user_id, term_code, entries)
      VALUES ($(name), $(scope), $(user_id), $(term_code), $(entries)::jsonb)
      RETURNING *
    )
    SELECT
    #{@columns}
    FROM inserted l
    JOIN users u ON u.id = l.user_id
    """

    params = %{
      "name" => name,
      "scope" => scope,
      "user_id" => Uuid.to_binary(user_id),
      "term_code" => term_code,
      "entries" => Jason.encode!(entries)
    }

    case DbHelpers.run_sql(sql, params, @layout_schema) do
      [layout] -> {:ok, decode_entries(layout)}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_insert_result, other}}
    end
  end

  @doc """
  Updates a layout in place. Any of `name`, `scope` and `entries` may be nil,
  which leaves that column as it was.
  """
  def update(layout_id: layout_id, name: name, scope: scope, entries: entries) do
    sql = """
    WITH updated AS (
      UPDATE schedule_layouts
      SET name = COALESCE($(name)::text, name),
          scope = COALESCE($(scope)::text, scope),
          entries = COALESCE($(entries)::jsonb, entries),
          updated_at = now()
      WHERE id = $(id)
      RETURNING *
    )
    SELECT
    #{@columns}
    FROM updated l
    JOIN users u ON u.id = l.user_id
    """

    params = %{
      "id" => Uuid.to_binary(layout_id),
      "name" => name,
      "scope" => scope,
      "entries" => entries && Jason.encode!(entries)
    }

    case DbHelpers.run_sql(sql, params, @layout_schema) do
      [layout] -> {:ok, decode_entries(layout)}
      [] -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_update_result, other}}
    end
  end

  # Postgrex hands jsonb back as the raw JSON text, so every read decodes it and
  # callers only ever see a list of entries.
  defp decode_entries(%{"entries" => entries} = layout) when is_binary(entries) do
    case Jason.decode(entries) do
      {:ok, decoded} when is_list(decoded) ->
        %{layout | "entries" => decoded}

      other ->
        Logger.error(
          "Saved layout #{layout["id"]} has unreadable entries, loading it as empty: #{inspect(other)}"
        )

        %{layout | "entries" => []}
    end
  end

  defp decode_entries(%{"entries" => entries} = layout) when is_list(entries), do: layout

  defp decode_entries(layout) do
    Logger.error("Saved layout #{layout["id"]} has no entries column; loading it as empty")
    Map.put(layout, "entries", [])
  end

  def delete(layout_id) when is_binary(layout_id) do
    sql = "DELETE FROM schedule_layouts WHERE id = $(id)"

    case DbHelpers.run_sql(sql, %{"id" => Uuid.to_binary(layout_id)}) do
      {:error, _reason} = error -> error
      _rows -> :ok
    end
  end
end
