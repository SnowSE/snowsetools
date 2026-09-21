defmodule SnowSeTools.Scheduling.AcknowledgedConflictDb do
  @moduledoc """
  Conflicts a person has looked at and decided are fine.

  Private to whoever acknowledged them: it is a reading list, not a ruling on
  the schedule, so one person clearing their list never hides a conflict from
  anyone else. Kept on the server rather than in the browser so the list
  follows them between machines.

  A row names the clash by `ScheduleConflictDetector.fingerprint/1`, which
  covers the meeting times. A class that moves produces a different
  fingerprint, so the conflict comes back on its own without anything having to
  notice the schedule changed.
  """

  alias SnowSeTools.Data.{DbHelpers, Uuid}

  @acknowledgement_schema Zoi.object(%{
                            "fingerprint" => Zoi.string()
                          })

  def bootstrap_tables do
    statements = [
      """
      CREATE TABLE IF NOT EXISTS acknowledged_conflicts (
        id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        term_code   TEXT        NOT NULL,
        fingerprint TEXT        NOT NULL,
        created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
        UNIQUE (user_id, term_code, fingerprint)
      )
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_acknowledged_conflicts_user_term
        ON acknowledged_conflicts(user_id, term_code)
      """
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case DbHelpers.query(sql, %{}) do
        {:error, reason} -> {:halt, {:error, reason}}
        {:ok, _rows} -> {:cont, :ok}
      end
    end)
  end

  @doc "The fingerprints `user_id` has acknowledged in `term_code`."
  def list(user_id: user_id, term_code: term_code)
      when is_binary(user_id) and is_binary(term_code) do
    sql = """
    SELECT fingerprint
    FROM acknowledged_conflicts
    WHERE user_id = $(user_id) AND term_code = $(term_code)
    """

    params = %{"user_id" => Uuid.to_binary(user_id), "term_code" => term_code}

    case DbHelpers.query(sql, params, @acknowledgement_schema) do
      {:ok, rows} -> {:ok, Enum.map(rows, & &1["fingerprint"])}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Acknowledges one conflict. Acknowledging the same one twice is not an error —
  two tabs, or a double click, mean the same thing as one.
  """
  def acknowledge(user_id: user_id, term_code: term_code, fingerprint: fingerprint)
      when is_binary(user_id) and is_binary(term_code) and is_binary(fingerprint) do
    sql = """
    INSERT INTO acknowledged_conflicts (user_id, term_code, fingerprint)
    VALUES ($(user_id), $(term_code), $(fingerprint))
    ON CONFLICT (user_id, term_code, fingerprint) DO NOTHING
    """

    params = %{
      "user_id" => Uuid.to_binary(user_id),
      "term_code" => term_code,
      "fingerprint" => fingerprint
    }

    case DbHelpers.query(sql, params) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Brings every conflict `user_id` acknowledged in `term_code` back."
  def reset(user_id: user_id, term_code: term_code)
      when is_binary(user_id) and is_binary(term_code) do
    sql = """
    DELETE FROM acknowledged_conflicts
    WHERE user_id = $(user_id) AND term_code = $(term_code)
    """

    params = %{"user_id" => Uuid.to_binary(user_id), "term_code" => term_code}

    case DbHelpers.query(sql, params) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
