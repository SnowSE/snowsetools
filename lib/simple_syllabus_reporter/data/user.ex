defmodule SimpleSyllabusReporter.Data.User do
  require Logger
  alias SimpleSyllabusReporter.Data.DbHelpers

  def schema do
    Zoi.object(%{
      id: Zoi.uuid(),
      email: Zoi.string(),
      inserted_at: Zoi.datetime(),
      updated_at: Zoi.datetime()
    })
  end

  def find_or_create(email) do
    sql = """
    INSERT INTO users (email)
    VALUES ($(email))
    ON CONFLICT (email) DO UPDATE SET updated_at = NOW()
    RETURNING id, email, inserted_at, updated_at
    """

    case DbHelpers.run_sql(sql, %{"email" => email}, schema()) do
      {:error, reason} -> {:error, reason}
      [] -> {:error, :not_found}
      [user | _] -> {:ok, user}
    end
  end

  def get_by_id(user_id) when is_binary(user_id) do
    sql = """
    SELECT id, email, inserted_at, updated_at
    FROM users
    WHERE id = $(user_id)
    """

    user_id_binary =
      user_id
      |> String.replace("-", "")
      |> Base.decode16!(case: :lower)

    case DbHelpers.run_sql(sql, %{"user_id" => user_id_binary}, schema()) do
      [user | _] -> {:ok, user}
      [] -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
