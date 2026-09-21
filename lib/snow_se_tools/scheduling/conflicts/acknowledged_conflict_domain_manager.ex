defmodule SnowSeTools.Scheduling.AcknowledgedConflictDomainManager do
  @moduledoc """
  Owns the conflicts each person has acknowledged: listing them for a term,
  adding one, and putting them all back.

  The user comes from the signed-in socket rather than the event, so a forged
  event cannot acknowledge a conflict on someone else's behalf. Every answer
  goes back to the page that asked, as
  `{:acknowledged_conflicts, {_what, payload}}`.
  """

  use GenServer
  require Logger

  alias SnowSeTools.Scheduling.AcknowledgedConflictDb

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def list(pid: pid, user: user, term_code: term_code) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:list, pid, user, term_code})
  end

  def acknowledge(pid: pid, user: user, term_code: term_code, fingerprint: fingerprint)
      when is_pid(pid) do
    GenServer.cast(__MODULE__, {:acknowledge, pid, user, term_code, fingerprint})
  end

  def reset(pid: pid, user: user, term_code: term_code) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:reset, pid, user, term_code})
  end

  @impl true
  def init(:ok) do
    case AcknowledgedConflictDb.bootstrap_tables() do
      :ok ->
        {:ok, %{}}

      {:error, reason} ->
        Logger.error(
          "AcknowledgedConflictDomainManager could not bootstrap tables: #{inspect(reason)}"
        )

        {:stop, {:bootstrap_failed, reason}}
    end
  end

  @impl true
  def handle_cast({:list, pid, user, term_code}, state) do
    with_user(pid, user, term_code, fn user_id ->
      case AcknowledgedConflictDb.list(user_id: user_id, term_code: term_code) do
        {:ok, fingerprints} ->
          send(
            pid,
            {:acknowledged_conflicts,
             {:listed, %{term_code: term_code, fingerprints: fingerprints}}}
          )

        {:error, reason} ->
          fail(pid, "list acknowledged conflicts", reason)
      end
    end)

    {:noreply, state}
  end

  def handle_cast({:acknowledge, pid, user, term_code, fingerprint}, state) do
    with_user(pid, user, term_code, fn user_id ->
      case AcknowledgedConflictDb.acknowledge(
             user_id: user_id,
             term_code: term_code,
             fingerprint: fingerprint
           ) do
        :ok ->
          send(
            pid,
            {:acknowledged_conflicts,
             {:acknowledged, %{term_code: term_code, fingerprint: fingerprint}}}
          )

        {:error, reason} ->
          fail(pid, "acknowledge a conflict", reason)
      end
    end)

    {:noreply, state}
  end

  def handle_cast({:reset, pid, user, term_code}, state) do
    with_user(pid, user, term_code, fn user_id ->
      case AcknowledgedConflictDb.reset(user_id: user_id, term_code: term_code) do
        :ok ->
          send(pid, {:acknowledged_conflicts, {:reset, %{term_code: term_code}}})

        {:error, reason} ->
          fail(pid, "reset acknowledged conflicts", reason)
      end
    end)

    {:noreply, state}
  end

  defp with_user(_pid, %{id: user_id}, term_code, work) when is_binary(term_code),
    do: work.(user_id)

  defp with_user(pid, user, term_code, _work) do
    Logger.error(
      "Refusing an acknowledged-conflicts request without a signed-in user and term " <>
        "user=#{inspect(user)} term=#{inspect(term_code)}"
    )

    send(pid, {:acknowledged_conflicts, {:error, :not_signed_in}})
  end

  defp fail(pid, what, reason) do
    Logger.error("Could not #{what}: #{inspect(reason)}")
    send(pid, {:acknowledged_conflicts, {:error, reason}})
  end
end
