defmodule SnowSeTools.Data.AccessControl do
  require Logger
  alias SnowSeTools.Data.{Access, DbHelpers, Uuid}

  @admin_group_name "admin"

  def bootstrap_access_control do
    sql = """
    CREATE TABLE IF NOT EXISTS groups (
      id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      name        TEXT        NOT NULL UNIQUE,
      inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """

    params = %{}
    DbHelpers.run_sql(sql, params)

    sql = """
    CREATE TABLE IF NOT EXISTS user_groups (
      user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      group_id    UUID        NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, group_id)
    )
    """

    DbHelpers.run_sql(sql, params)

    sql = """
    ALTER TABLE groups DROP COLUMN IF EXISTS is_admin
    """

    DbHelpers.run_sql(sql, params)

    # Seed every access group (admin, discord_admin, scheduling_admin, syllabus_admin).
    sql = """
    INSERT INTO groups (name)
    SELECT unnest($(names)::text[])
    ON CONFLICT (name) DO NOTHING
    """

    DbHelpers.run_sql(sql, %{"names" => Access.protected_group_names()})

    sql = """
    WITH admin_group AS (
      SELECT id
      FROM groups
      WHERE name = 'admin'
      LIMIT 1
    ),
    first_user AS (
      SELECT u.id
      FROM users u
      WHERE NOT EXISTS (
        SELECT 1
        FROM user_groups ug
        JOIN groups g ON g.id = ug.group_id
        WHERE g.name = 'admin'
      )
      ORDER BY u.inserted_at ASC
      LIMIT 1
    )
    INSERT INTO user_groups (user_id, group_id)
    SELECT first_user.id, admin_group.id
    FROM first_user
    CROSS JOIN admin_group
    ON CONFLICT (user_id, group_id) DO NOTHING
    """

    DbHelpers.run_sql(sql, params)
  end

  def list_users_with_groups do
    sql = """
    SELECT
      u.id,
      u.email,
      u.inserted_at,
      u.updated_at,
      COALESCE(
        array_agg(DISTINCT ug.group_id) FILTER (WHERE ug.group_id IS NOT NULL),
        '{}'::uuid[]
      ) AS group_ids,
      COALESCE(
        array_agg(DISTINCT g.name) FILTER (WHERE g.name IS NOT NULL),
        '{}'::text[]
      ) AS group_names
    FROM users u
    LEFT JOIN user_groups ug ON ug.user_id = u.id
    LEFT JOIN groups g ON g.id = ug.group_id
    GROUP BY u.id
    ORDER BY u.inserted_at ASC
    """

    params = %{}
    DbHelpers.run_sql(sql, params, user_schema())
  end

  def list_groups do
    sql = """
    SELECT
      g.id,
      g.name,
      g.inserted_at,
      g.updated_at,
      COUNT(ug.user_id)::int AS member_count,
      COALESCE(
        array_agg(DISTINCT ug.user_id) FILTER (WHERE ug.user_id IS NOT NULL),
        '{}'::uuid[]
      ) AS user_ids
    FROM groups g
    LEFT JOIN user_groups ug ON ug.group_id = g.id
    GROUP BY g.id
    ORDER BY (g.name = 'admin') DESC, g.name ASC
    """

    params = %{}
    DbHelpers.run_sql(sql, params, group_schema())
  end

  def create_group(group_params) when is_map(group_params) do
    attrs = normalize_group_params(group_params)

    with {:ok, _} <- validate_group_attrs(attrs) do
      sql = """
      INSERT INTO groups (name)
      VALUES ($(name))
      RETURNING id, name, inserted_at, updated_at, 0 AS member_count, '{}'::uuid[] AS user_ids
      """

      params = %{"name" => attrs["name"]}

      case DbHelpers.run_sql(sql, params, group_schema()) do
        {:error, reason} -> {:error, reason}
        [group | _] -> {:ok, group}
      end
    else
      error -> error
    end
  end

  def update_group(group_id: group_id, group_params: group_params) do
    attrs = normalize_group_params(group_params)

    with {:ok, _} <- validate_group_attrs(attrs),
         {:ok, current_group} <- fetch_group(group_id: group_id) do
      if Access.protected_group?(current_group.name) and attrs["name"] != current_group.name do
        {:error, :protected_group_locked}
      else
        sql = """
        UPDATE groups
        SET name = $(name),
            updated_at = NOW()
        WHERE id = $(group_id)
        RETURNING id, name, inserted_at, updated_at, 0 AS member_count, '{}'::uuid[] AS user_ids
        """

        params = Map.merge(attrs, %{"group_id" => Uuid.to_binary(group_id)})

        case DbHelpers.run_sql(sql, params, group_schema()) do
          {:error, reason} -> {:error, reason}
          [] -> {:error, :not_found}
          [group | _] -> {:ok, group}
        end
      end
    else
      error -> error
    end
  end

  def delete_group(group_id: group_id) do
    with {:ok, group} <- fetch_group(group_id: group_id) do
      if Access.protected_group?(group.name) do
        {:error, :protected_group_locked}
      else
        sql = """
        DELETE FROM groups
        WHERE id = $(group_id)
        RETURNING id
        """

        params = %{"group_id" => Uuid.to_binary(group_id)}

        case DbHelpers.run_sql(sql, params, group_id_schema()) do
          {:error, reason} -> {:error, reason}
          [] -> {:error, :not_found}
          [_ | _] -> :ok
        end
      end
    else
      error -> error
    end
  end

  def create_user(email: email) when is_binary(email) do
    email = String.trim(email)

    if email == "" do
      {:error, :invalid_email}
    else
      sql = """
      INSERT INTO users (email)
      VALUES ($(email))
      ON CONFLICT (email) DO UPDATE SET updated_at = NOW()
      RETURNING id, email, inserted_at, updated_at, '{}'::uuid[] AS group_ids, '{}'::text[] AS group_names
      """

      params = %{"email" => email}

      case DbHelpers.run_sql(sql, params, user_schema()) do
        {:error, reason} ->
          {:error, reason}

        [user | _] ->
          bootstrap_access_control()
          {:ok, user}
      end
    end
  end

  def add_user_group(user_id: user_id, group_id: group_id) do
    with {:ok, _group} <- fetch_group(group_id: group_id) do
      insert_user_group(user_id: user_id, group_id: group_id)
    else
      error -> error
    end
  end

  def remove_user_group(user_id: user_id, group_id: group_id) do
    with {:ok, group} <- fetch_group(group_id: group_id) do
      if group.name == @admin_group_name and
           user_has_group?(user_id: user_id, group_name: @admin_group_name) and
           Enum.count(group.user_ids) == 1 do
        {:error, :last_admin_user}
      else
        delete_user_group(user_id: user_id, group_id: group_id)
      end
    else
      error -> error
    end
  end

  def user_has_group?(user_id: user_id, group_name: group_name) when is_binary(group_name) do
    sql = """
    SELECT 1
    FROM user_groups ug
    JOIN groups g ON g.id = ug.group_id
    WHERE ug.user_id = $(user_id) AND g.name = $(group_name)
    LIMIT 1
    """

    params = %{
      "user_id" => Uuid.to_binary(user_id),
      "group_name" => group_name
    }

    case DbHelpers.run_sql(sql, params, existence_schema()) do
      [_ | _] ->
        true

      [] ->
        false

      {:error, reason} ->
        Logger.warning("AccessControl.user_has_group? failed reason=#{inspect(reason)}")
        false
    end
  end

  def user_group_ids(user_id: user_id) do
    sql = """
    SELECT group_id
    FROM user_groups
    WHERE user_id = $(user_id)
    ORDER BY inserted_at ASC
    """

    params = %{"user_id" => Uuid.to_binary(user_id)}

    case DbHelpers.run_sql(sql, params, user_group_schema()) do
      {:error, reason} -> {:error, reason}
      rows -> {:ok, Enum.map(rows, & &1.group_id)}
    end
  end

  defp fetch_group(group_id: group_id) do
    sql = """
    SELECT
      g.id,
      g.name,
      g.inserted_at,
      g.updated_at,
      COUNT(ug.user_id)::int AS member_count,
      COALESCE(
        array_agg(DISTINCT ug.user_id) FILTER (WHERE ug.user_id IS NOT NULL),
        '{}'::uuid[]
      ) AS user_ids
    FROM groups g
    LEFT JOIN user_groups ug ON ug.group_id = g.id
    WHERE g.id = $(group_id)
    GROUP BY g.id
    """

    params = %{"group_id" => Uuid.to_binary(group_id)}

    case DbHelpers.run_sql(sql, params, group_schema()) do
      [group | _] -> {:ok, group}
      [] -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_user_group(user_id: user_id, group_id: group_id) do
    sql = """
    INSERT INTO user_groups (user_id, group_id)
    VALUES ($(user_id), $(group_id))
    ON CONFLICT (user_id, group_id) DO NOTHING
    RETURNING user_id
    """

    params = %{
      "user_id" => Uuid.to_binary(user_id),
      "group_id" => Uuid.to_binary(group_id)
    }

    case DbHelpers.run_sql(sql, params, existence_schema()) do
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  defp delete_user_group(user_id: user_id, group_id: group_id) do
    sql = """
    DELETE FROM user_groups
    WHERE user_id = $(user_id) AND group_id = $(group_id)
    RETURNING user_id
    """

    params = %{
      "user_id" => Uuid.to_binary(user_id),
      "group_id" => Uuid.to_binary(group_id)
    }

    case DbHelpers.run_sql(sql, params, existence_schema()) do
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  defp validate_group_attrs(%{"name" => ""}), do: {:error, :invalid_group_name}
  defp validate_group_attrs(attrs), do: {:ok, attrs}

  defp normalize_group_params(group_params) do
    group_params = group_params || %{}

    %{"name" => String.trim(Map.get(group_params, "name", ""))}
  end

  defp user_schema do
    Zoi.object(%{
      id: Zoi.uuid(),
      email: Zoi.string(),
      inserted_at: Zoi.datetime(),
      updated_at: Zoi.datetime(),
      group_ids: Zoi.list(Zoi.uuid()),
      group_names: Zoi.list(Zoi.string())
    })
  end

  defp group_schema do
    Zoi.object(%{
      id: Zoi.uuid(),
      name: Zoi.string(),
      inserted_at: Zoi.datetime(),
      updated_at: Zoi.datetime(),
      member_count: Zoi.integer(),
      user_ids: Zoi.list(Zoi.uuid())
    })
  end

  defp user_group_schema do
    Zoi.object(%{group_id: Zoi.uuid()})
  end

  defp existence_schema do
    Zoi.object(%{})
  end

  defp group_id_schema do
    Zoi.object(%{id: Zoi.uuid()})
  end
end
