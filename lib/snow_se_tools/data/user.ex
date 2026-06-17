defmodule SnowSeTools.Data.User do
  alias SnowSeTools.Data.{AccessControl, DbHelpers, Uuid}

  def schema do
    Zoi.object(%{
      id: Zoi.uuid(),
      email: Zoi.string(),
      inserted_at: Zoi.datetime(),
      updated_at: Zoi.datetime(),
      group_ids: Zoi.list(Zoi.uuid())
    })
  end

  def find_or_create(email) do
    AccessControl.create_user(email: email)
  end

  def get_by_id(user_id) when is_binary(user_id) do
    sql = """
    SELECT
      u.id,
      u.email,
      u.inserted_at,
      u.updated_at,
      COALESCE(
        array_agg(DISTINCT ug.group_id) FILTER (WHERE ug.group_id IS NOT NULL),
        '{}'::uuid[]
      ) AS group_ids
    FROM users u
    LEFT JOIN user_groups ug ON ug.user_id = u.id
    WHERE u.id = $(user_id)
    GROUP BY u.id
    """

    params = %{"user_id" => Uuid.to_binary(user_id)}

    case DbHelpers.run_sql(sql, params, schema()) do
      [user | _] ->
        {:ok, user}

      [] ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
