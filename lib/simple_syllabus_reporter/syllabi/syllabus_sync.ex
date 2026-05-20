defmodule SimpleSyllabusReporter.Syllabi.SyllabusSync do
  @moduledoc """
  Downloads all Snow College syllabi from the SimpleSyllabus API and persists
  them to the local database.

  Triggered manually via `sync_all/0` (e.g. from the cache clear endpoint).
  A supervised task performs the work; errors are reported back to this
  GenServer and logged rather than silently dropped.
  """
  use GenServer
  require Logger

  alias SimpleSyllabusReporter.SimpleSyllabusApi
  alias SimpleSyllabusReporter.Syllabi.SyllabusDB
  alias SimpleSyllabusReporter.ConfigDB

  @type sync_state ::
          :idle
          | {:running, started_at :: DateTime.t(), task_ref :: reference()}
          | {:done, started_at :: DateTime.t(), finished_at :: DateTime.t(),
             count :: non_neg_integer()}
          | {:failed, started_at :: DateTime.t(), finished_at :: DateTime.t(), reason :: term()}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :idle, name: __MODULE__)

  @doc "Triggers a full sync in the background. No-ops if one is already running."
  def sync_all, do: GenServer.cast(__MODULE__, :sync_all)

  @doc "Returns the current sync state."
  def sync_status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(:idle), do: {:ok, :idle}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:sync_all, {:running, _, _} = state) do
    Logger.info("SyllabusSync already running, ignoring duplicate sync_all")
    {:noreply, state}
  end

  def handle_cast(:sync_all, _state) do
    Logger.info("SyllabusSync starting full institution sync")
    started_at = DateTime.utc_now()
    parent = self()
    ref = make_ref()

    spawn_monitor(fn ->
      result = do_sync()
      send(parent, {:sync_done, ref, result})
    end)

    {:noreply, {:running, started_at, ref}}
  end

  @impl true
  def handle_info({:sync_done, ref, result}, {:running, started_at, ref}) do
    Process.demonitor(ref, [:flush])
    finished_at = DateTime.utc_now()

    case result do
      {:ok, count} ->
        Logger.info(
          "SyllabusSync completed count=#{count} duration_s=#{duration_s(started_at, finished_at)}"
        )

        {:noreply, {:done, started_at, finished_at, count}}

      {:error, reason} ->
        Logger.error("SyllabusSync finished with error reason=#{inspect(reason)}")
        {:noreply, {:failed, started_at, finished_at, reason}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, {:running, started_at, ref}) do
    finished_at = DateTime.utc_now()
    Logger.error("SyllabusSync task crashed reason=#{inspect(reason)}")
    {:noreply, {:failed, started_at, finished_at, reason}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp do_sync do
    with {:ok, orgs} <- SimpleSyllabusApi.get_organizations() do
      schools = Enum.filter(orgs, &(&1["level"] == 2 && &1["is_self_active"]))
      active_term_id = ConfigDB.get_current_term()

      fetch_opts =
        if active_term_id do
          Logger.info(
            "SyllabusSync syncing #{length(schools)} schools for term_id=#{active_term_id}"
          )

          [term_statuses: [], term_id: active_term_id]
        else
          Logger.info("SyllabusSync syncing #{length(schools)} schools (all terms)")
          [term_statuses: []]
        end

      results =
        Task.async_stream(
          schools,
          fn org ->
            org_id = org["entity_id"]

            case SimpleSyllabusApi.fetch_syllabi_by_org(org_id, fetch_opts) do
              {:ok, %{items: docs}} ->
                SyllabusDB.upsert_list_items(docs, org_id: org_id)
                {:ok, length(docs)}

              {:error, reason} ->
                Logger.error(
                  "SyllabusSync failed for org=#{org["name"]} reason=#{inspect(reason)}"
                )

                {:error, reason}
            end
          end,
          timeout: 60_000,
          on_timeout: :kill_task
        )
        |> Enum.to_list()

      errors =
        Enum.filter(results, fn
          {:ok, {:error, _}} -> true
          {:exit, _} -> true
          _ -> false
        end)

      if errors != [] do
        Logger.warning("SyllabusSync completed with #{length(errors)} school errors")
      end

      total =
        results
        |> Enum.flat_map(fn
          {:ok, {:ok, count}} -> [count]
          _ -> []
        end)
        |> Enum.sum()

      {:ok, total}
    end
  end

  defp duration_s(started_at, finished_at) do
    DateTime.diff(finished_at, started_at, :second)
  end
end
