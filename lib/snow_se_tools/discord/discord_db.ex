defmodule SnowSeTools.Discord.DiscordDb do
  alias SnowSeTools.Data.DbHelpers

  @discord_item_schema Zoi.object(%{
                         "id" => Zoi.string(),
                         "name" => Zoi.string(),
                         "data" => Zoi.map(),
                         "synced_at" => Zoi.string()
                       })

  @course_channel_assignment_schema Zoi.object(%{
                                      "crn" => Zoi.string(),
                                      "term_code" => Zoi.string(),
                                      "discord_channel_id" => Zoi.string(),
                                      "discord_role_id" => Zoi.string(),
                                      "created_at" => Zoi.string()
                                    })

  @student_discord_mapping_schema Zoi.object(%{
                                    "badger_id" => Zoi.string(),
                                    "discord_user_id" => Zoi.string()
                                  })

  @sync_summary_schema Zoi.object(%{
                         "resource" => Zoi.string(),
                         "record_count" => Zoi.integer(),
                         "last_synced_at" => Zoi.string()
                       })

  def bootstrap_discord_tables do
    statements = [
      """
      CREATE TABLE IF NOT EXISTS discord_guilds (
        id         TEXT        PRIMARY KEY,
        name       TEXT,
        data       JSONB       NOT NULL,
        synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS discord_bot_users (
        id         TEXT        PRIMARY KEY,
        name       TEXT,
        data       JSONB       NOT NULL,
        synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS discord_members (
        id         TEXT        PRIMARY KEY,
        name       TEXT,
        data       JSONB       NOT NULL,
        synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS discord_channels (
        id         TEXT        PRIMARY KEY,
        name       TEXT,
        data       JSONB       NOT NULL,
        synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS discord_roles (
        id         TEXT        PRIMARY KEY,
        name       TEXT,
        data       JSONB       NOT NULL,
        synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS discord_invites (
        id         TEXT        PRIMARY KEY,
        name       TEXT,
        data       JSONB       NOT NULL,
        synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS course_channel_assignments (
        crn                 TEXT        PRIMARY KEY,
        term_code           TEXT        NOT NULL,
        discord_channel_id  TEXT        NOT NULL,
        discord_role_id    TEXT        NOT NULL,
        created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS student_discord_mapping (
        badger_id        TEXT        PRIMARY KEY,
        discord_user_id   TEXT        NOT NULL,
        created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE INDEX IF NOT EXISTS discord_members_name_idx ON discord_members(name)
      """,
      """
      CREATE INDEX IF NOT EXISTS discord_channels_name_idx ON discord_channels(name)
      """,
      """
      CREATE INDEX IF NOT EXISTS discord_roles_name_idx ON discord_roles(name)
      """,
      """
      CREATE INDEX IF NOT EXISTS course_channel_assignments_channel_idx ON course_channel_assignments(discord_channel_id)
      """,
      """
      CREATE INDEX IF NOT EXISTS student_discord_mapping_discord_user_idx ON student_discord_mapping(discord_user_id)
      """
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case DbHelpers.run_sql(sql, %{}) do
        {:error, reason} -> {:halt, {:error, reason}}
        _ -> {:cont, :ok}
      end
    end)
  end

  def save_guild(guild: guild) when is_map(guild) do
    sql = """
    INSERT INTO discord_guilds (id, name, data, synced_at, updated_at)
    VALUES ($(id), $(name), $(data)::jsonb, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      data = EXCLUDED.data,
      synced_at = NOW(),
      updated_at = NOW()
    """

    params = %{
      "id" => Map.fetch!(guild, "id"),
      "name" => Map.get(guild, "name"),
      "data" => Jason.encode!(guild)
    }

    case DbHelpers.run_sql(sql, params) do
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  def save_bot_user(bot_user: bot_user) when is_map(bot_user) do
    sql = """
    INSERT INTO discord_bot_users (id, name, data, synced_at, updated_at)
    VALUES ($(id), $(name), $(data)::jsonb, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      data = EXCLUDED.data,
      synced_at = NOW(),
      updated_at = NOW()
    """

    params = %{
      "id" => Map.fetch!(bot_user, "id"),
      "name" => Map.get(bot_user, "username"),
      "data" => Jason.encode!(bot_user)
    }

    case DbHelpers.run_sql(sql, params) do
      {:error, reason} -> {:error, reason}
      _ -> :ok
    end
  end

  def save_members(members: members) when is_list(members) do
    rows =
      Enum.map(members, fn member ->
        user = Map.get(member, "user", %{})

        %{
          "id" => Map.fetch!(user, "id"),
          "name" => display_name(member),
          "data" => member
        }
      end)

    DbHelpers.transaction(fn ->
      case DbHelpers.run_sql("DELETE FROM discord_members", %{}) do
        {:error, reason} ->
          {:error, reason}

        _ ->
          if rows == [] do
            :ok
          else
            sql = """
            INSERT INTO discord_members (id, name, data, synced_at, updated_at)
            SELECT d.id, d.name, d.data::jsonb, NOW(), NOW()
            FROM UNNEST(
              $(ids)::text[],
              $(names)::text[],
              $(data_list)::text[]
            ) AS d(id, name, data)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              data = EXCLUDED.data,
              synced_at = NOW(),
              updated_at = NOW()
            """

            params = %{
              "ids" => Enum.map(rows, & &1["id"]),
              "names" => Enum.map(rows, & &1["name"]),
              "data_list" => Enum.map(rows, &Jason.encode!(&1["data"]))
            }

            case DbHelpers.run_sql(sql, params) do
              {:error, reason} -> {:error, reason}
              _ -> :ok
            end
          end
      end
    end)
  end

  def save_channels(channels: channels) when is_list(channels) do
    rows =
      Enum.map(channels, fn channel ->
        %{
          "id" => Map.fetch!(channel, "id"),
          "name" => Map.get(channel, "name"),
          "data" => channel
        }
      end)

    DbHelpers.transaction(fn ->
      case DbHelpers.run_sql("DELETE FROM discord_channels", %{}) do
        {:error, reason} ->
          {:error, reason}

        _ ->
          if rows == [] do
            :ok
          else
            sql = """
            INSERT INTO discord_channels (id, name, data, synced_at, updated_at)
            SELECT d.id, d.name, d.data::jsonb, NOW(), NOW()
            FROM UNNEST(
              $(ids)::text[],
              $(names)::text[],
              $(data_list)::text[]
            ) AS d(id, name, data)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              data = EXCLUDED.data,
              synced_at = NOW(),
              updated_at = NOW()
            """

            params = %{
              "ids" => Enum.map(rows, & &1["id"]),
              "names" => Enum.map(rows, & &1["name"]),
              "data_list" => Enum.map(rows, &Jason.encode!(&1["data"]))
            }

            case DbHelpers.run_sql(sql, params) do
              {:error, reason} -> {:error, reason}
              _ -> :ok
            end
          end
      end
    end)
  end

  def save_roles(roles: roles) when is_list(roles) do
    rows =
      Enum.map(roles, fn role ->
        %{
          "id" => Map.fetch!(role, "id"),
          "name" => Map.get(role, "name"),
          "data" => role
        }
      end)

    DbHelpers.transaction(fn ->
      case DbHelpers.run_sql("DELETE FROM discord_roles", %{}) do
        {:error, reason} ->
          {:error, reason}

        _ ->
          if rows == [] do
            :ok
          else
            sql = """
            INSERT INTO discord_roles (id, name, data, synced_at, updated_at)
            SELECT d.id, d.name, d.data::jsonb, NOW(), NOW()
            FROM UNNEST(
              $(ids)::text[],
              $(names)::text[],
              $(data_list)::text[]
            ) AS d(id, name, data)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              data = EXCLUDED.data,
              synced_at = NOW(),
              updated_at = NOW()
            """

            params = %{
              "ids" => Enum.map(rows, & &1["id"]),
              "names" => Enum.map(rows, & &1["name"]),
              "data_list" => Enum.map(rows, &Jason.encode!(&1["data"]))
            }

            case DbHelpers.run_sql(sql, params) do
              {:error, reason} -> {:error, reason}
              _ -> :ok
            end
          end
      end
    end)
  end

  def save_invites(invites: invites) when is_list(invites) do
    rows =
      Enum.map(invites, fn invite ->
        code = Map.fetch!(invite, "code")

        %{
          "id" => code,
          "name" => code,
          "data" => invite
        }
      end)

    DbHelpers.transaction(fn ->
      case DbHelpers.run_sql("DELETE FROM discord_invites", %{}) do
        {:error, reason} ->
          {:error, reason}

        _ ->
          if rows == [] do
            :ok
          else
            sql = """
            INSERT INTO discord_invites (id, name, data, synced_at, updated_at)
            SELECT d.id, d.name, d.data::jsonb, NOW(), NOW()
            FROM UNNEST(
              $(ids)::text[],
              $(names)::text[],
              $(data_list)::text[]
            ) AS d(id, name, data)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              data = EXCLUDED.data,
              synced_at = NOW(),
              updated_at = NOW()
            """

            params = %{
              "ids" => Enum.map(rows, & &1["id"]),
              "names" => Enum.map(rows, & &1["name"]),
              "data_list" => Enum.map(rows, &Jason.encode!(&1["data"]))
            }

            case DbHelpers.run_sql(sql, params) do
              {:error, reason} -> {:error, reason}
              _ -> :ok
            end
          end
      end
    end)
  end

  def list_guilds do
    sql = """
    SELECT
      id,
      COALESCE(name, '') AS name,
      CASE
        WHEN jsonb_typeof(data) = 'string' THEN (data #>> '{}')::jsonb
        ELSE data
      END AS data,
      synced_at::text
    FROM discord_guilds
    ORDER BY name NULLS LAST, id
    """

    DbHelpers.run_sql(sql, %{}, @discord_item_schema)
  end

  def list_bot_users do
    sql = """
    SELECT
      id,
      COALESCE(name, '') AS name,
      CASE
        WHEN jsonb_typeof(data) = 'string' THEN (data #>> '{}')::jsonb
        ELSE data
      END AS data,
      synced_at::text
    FROM discord_bot_users
    ORDER BY name NULLS LAST, id
    """

    DbHelpers.run_sql(sql, %{}, @discord_item_schema)
  end

  def list_members do
    sql = """
    SELECT id, COALESCE(name, '') AS name, data, synced_at::text
    FROM discord_members
    ORDER BY name NULLS LAST, id
    """

    DbHelpers.run_sql(sql, %{}, @discord_item_schema)
  end

  def list_channels do
    sql = """
    SELECT id, COALESCE(name, '') AS name, data, synced_at::text
    FROM discord_channels
    ORDER BY name NULLS LAST, id
    """

    DbHelpers.run_sql(sql, %{}, @discord_item_schema)
  end

  def list_roles do
    sql = """
    SELECT id, COALESCE(name, '') AS name, data, synced_at::text
    FROM discord_roles
    ORDER BY name NULLS LAST, id
    """

    DbHelpers.run_sql(sql, %{}, @discord_item_schema)
  end

  def list_invites do
    sql = """
    SELECT id, COALESCE(name, '') AS name, data, synced_at::text
    FROM discord_invites
    ORDER BY name NULLS LAST, id
    """

    DbHelpers.run_sql(sql, %{}, @discord_item_schema)
  end

  def list_course_channel_assignments do
    sql = """
    SELECT crn, term_code, discord_channel_id, discord_role_id, created_at::text AS created_at
    FROM course_channel_assignments
    ORDER BY term_code DESC, crn
    """

    DbHelpers.run_sql(sql, %{}, @course_channel_assignment_schema)
  end

  def get_course_channel_assignment(channel_id: channel_id) do
    sql = """
    SELECT crn, term_code, discord_channel_id, discord_role_id, created_at::text AS created_at
    FROM course_channel_assignments
    WHERE discord_channel_id = $(channel_id)
    LIMIT 1
    """

    case DbHelpers.run_sql(sql, %{"channel_id" => channel_id}, @course_channel_assignment_schema) do
      [assignment] -> assignment
      [] -> nil
      {:error, reason} -> {:error, reason}
    end
  end

  def get_course_channel_assignment_by_crn(crn: crn) do
    sql = """
    SELECT crn, term_code, discord_channel_id, discord_role_id, created_at::text AS created_at
    FROM course_channel_assignments
    WHERE crn = $(crn)
    LIMIT 1
    """

    case DbHelpers.run_sql(sql, %{"crn" => crn}, @course_channel_assignment_schema) do
      [assignment] -> assignment
      [] -> nil
      {:error, reason} -> {:error, reason}
    end
  end

  def save_course_channel_assignment(
        crn: crn,
        term_code: term_code,
        discord_channel_id: discord_channel_id,
        discord_role_id: discord_role_id
      ) do
    sql = """
    INSERT INTO course_channel_assignments (
      crn,
      term_code,
      discord_channel_id,
      discord_role_id,
      created_at,
      updated_at
    )
    VALUES ($(crn), $(term_code), $(discord_channel_id), $(discord_role_id), NOW(), NOW())
    ON CONFLICT (crn) DO UPDATE SET
      term_code = EXCLUDED.term_code,
      discord_channel_id = EXCLUDED.discord_channel_id,
      discord_role_id = EXCLUDED.discord_role_id,
      updated_at = NOW()
    """

    DbHelpers.run_sql(sql, %{
      "crn" => crn,
      "term_code" => term_code,
      "discord_channel_id" => discord_channel_id,
      "discord_role_id" => discord_role_id
    })
  end

  def delete_course_channel_assignment(crn: crn) do
    sql = "DELETE FROM course_channel_assignments WHERE crn = $(crn)"
    DbHelpers.run_sql(sql, %{"crn" => crn})
  end

  def delete_orphaned_course_channel_assignments do
    sql = """
    DELETE FROM course_channel_assignments
    WHERE discord_channel_id NOT IN (SELECT id FROM discord_channels)
       OR discord_role_id NOT IN (SELECT id FROM discord_roles)
    """

    DbHelpers.run_sql(sql, %{})
  end

  def list_student_discord_mappings do
    sql = """
    SELECT badger_id, discord_user_id
    FROM student_discord_mapping
    ORDER BY badger_id
    """

    DbHelpers.run_sql(sql, %{}, @student_discord_mapping_schema)
  end

  def save_student_discord_mapping(badger_id: badger_id, discord_user_id: discord_user_id) do
    sql = """
    INSERT INTO student_discord_mapping (badger_id, discord_user_id, created_at, updated_at)
    VALUES ($(badger_id), $(discord_user_id), NOW(), NOW())
    ON CONFLICT (badger_id) DO UPDATE SET
      discord_user_id = EXCLUDED.discord_user_id,
      updated_at = NOW()
    """

    DbHelpers.run_sql(sql, %{
      "badger_id" => badger_id,
      "discord_user_id" => discord_user_id
    })
  end

  def delete_student_discord_mapping(badger_id: badger_id) do
    sql = "DELETE FROM student_discord_mapping WHERE badger_id = $(badger_id)"
    DbHelpers.run_sql(sql, %{"badger_id" => badger_id})
  end

  def get_mapped_badger_id(discord_user_id: discord_user_id) do
    sql = """
    SELECT badger_id
    FROM student_discord_mapping
    WHERE discord_user_id = $(discord_user_id)
    LIMIT 1
    """

    case DbHelpers.run_sql(sql, %{"discord_user_id" => discord_user_id}) do
      [row] -> row["badger_id"]
      [] -> nil
      {:error, reason} -> {:error, reason}
    end
  end

  def get_server_status do
    with guilds when is_list(guilds) <- list_guilds(),
         bot_users when is_list(bot_users) <- list_bot_users() do
      %{
        guild: List.first(guilds),
        bot_user: List.first(bot_users)
      }
    else
      {:error, reason} -> {:error, reason}
      unexpected -> {:error, {:unexpected_server_status_result, unexpected}}
    end
  end

  def sync_summary do
    sql = """
    SELECT resource, record_count, last_synced_at
    FROM (
      SELECT 'guilds' AS resource, COUNT(*)::int AS record_count, COALESCE(MAX(synced_at)::text, '') AS last_synced_at FROM discord_guilds
      UNION ALL
      SELECT 'bot_users' AS resource, COUNT(*)::int AS record_count, COALESCE(MAX(synced_at)::text, '') AS last_synced_at FROM discord_bot_users
      UNION ALL
      SELECT 'members' AS resource, COUNT(*)::int AS record_count, COALESCE(MAX(synced_at)::text, '') AS last_synced_at FROM discord_members
      UNION ALL
      SELECT 'channels' AS resource, COUNT(*)::int AS record_count, COALESCE(MAX(synced_at)::text, '') AS last_synced_at FROM discord_channels
      UNION ALL
      SELECT 'roles' AS resource, COUNT(*)::int AS record_count, COALESCE(MAX(synced_at)::text, '') AS last_synced_at FROM discord_roles
      UNION ALL
      SELECT 'invites' AS resource, COUNT(*)::int AS record_count, COALESCE(MAX(synced_at)::text, '') AS last_synced_at FROM discord_invites
    ) summary
    ORDER BY resource
    """

    DbHelpers.run_sql(sql, %{}, @sync_summary_schema)
  end

  defp display_name(member) do
    user = Map.get(member, "user", %{})

    Map.get(member, "nick") ||
      Map.get(user, "global_name") ||
      Map.get(user, "username")
  end
end
