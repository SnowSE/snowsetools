defmodule SnowSeTools.Syllabi.Syncing.SyllabusScraperAgent do
  use GenServer
  require Logger

  alias SnowSeTools.Syllabi.SyncWorker
  alias SnowSeTools.Syllabi.Syncing.SyllabusSyncPubsub

  def start_link(_opts),
    do: GenServer.start_link(__MODULE__, :idle, name: __MODULE__)

  def sync_term(term_id) do
    GenServer.call(__MODULE__, {:sync_term, term_id})
  end

  def sync_term_list do
    GenServer.call(__MODULE__, :sync_term_list)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  def report_syllabi_to_sync(total) do
    GenServer.cast(__MODULE__, {:sync_updates, {:syllabi_to_sync, total}})
  end

  def report_syllabus_synced do
    GenServer.cast(__MODULE__, {:sync_updates, :syllabus_synced})
  end

  def report_sync_error(reason) do
    GenServer.cast(__MODULE__, {:sync_error, reason})
  end

  def init(:idle) do
    {:ok,
     %{
       term_list_sync: %{status: :idle, ref: nil},
       syllabus_sync: %{status: :idle, term_id: nil, ref: nil, total: 0, completed: 0}
     }}
  end

  def handle_call(:status, _from, state) do
    {:reply, sync_status(state), state}
  end

  def handle_call({:sync_term, term_id}, _from, state) do
    if syncing?(state) do
      Logger.warning(
        "SyllabusScraperAgent syllabus sync already in progress, ignoring term sync request"
      )

      {:reply, {:error, :sync_in_progress}, state}
    else
      parent = self()

      {_pid, ref} =
        spawn_monitor(fn ->
          result = SyncWorker.sync_term(term_id: term_id)
          send(parent, {:syllabus_sync_done, result})
        end)

      new_state = %{
        state
        | syllabus_sync: %{status: :syncing, term_id: term_id, ref: ref, total: 0, completed: 0}
      }

      {:reply, :ok, new_state}
    end
  end

  def handle_call(:sync_term_list, _from, state) do
    if syncing?(state) do
      Logger.warning(
        "SyllabusScraperAgent term list sync already in progress, ignoring term list sync request"
      )

      {:reply, {:error, :sync_in_progress}, state}
    else
      parent = self()

      {_pid, ref} =
        spawn_monitor(fn ->
          result = SyncWorker.sync_term_list()
          send(parent, {:term_list_sync_done, result})
        end)

      {:reply, :ok, %{state | term_list_sync: %{status: :syncing, ref: ref}}}
    end
  end

  def handle_cast({:sync_updates, {:syllabi_to_sync, total}}, state) do
    new_sync = %{state.syllabus_sync | total: total}
    SyllabusSyncPubsub.broadcast_sync_progress(%{total: total, completed: 0})
    {:noreply, %{state | syllabus_sync: new_sync}}
  end

  def handle_cast({:sync_updates, :syllabus_synced}, state) do
    current = state.syllabus_sync.completed
    new_completed = current + 1
    total = state.syllabus_sync.total
    new_sync = %{state.syllabus_sync | completed: new_completed}
    SyllabusSyncPubsub.broadcast_sync_progress(%{total: total, completed: new_completed})
    {:noreply, %{state | syllabus_sync: new_sync}}
  end

  def handle_cast({:sync_error, reason}, state) do
    error_msg = to_string(reason)
    Logger.error("SyllabusScraperAgent sync error reason=#{error_msg}")
    SyllabusSyncPubsub.broadcast_sync_error(nil, error_msg)

    {:noreply,
     %{state | syllabus_sync: %{status: :idle, term_id: nil, ref: nil, total: 0, completed: 0}}}
  end

  def handle_info({:term_list_sync_done, result}, state) do
    case result do
      {:ok, term_count} ->
        Logger.info("SyllabusScraperAgent term list sync completed term_count=#{term_count}")
        SyllabusSyncPubsub.broadcast_sync_complete(nil)

      {:error, reason} ->
        error_msg = to_string(reason)
        Logger.error("SyllabusScraperAgent term list sync failed reason=#{error_msg}")
        SyllabusSyncPubsub.broadcast_sync_error(nil, error_msg)
    end

    {:noreply, %{state | term_list_sync: %{status: :idle, ref: nil}}}
  end

  def handle_info({:syllabus_sync_done, result}, state) do
    case result do
      :ok ->
        Logger.info("SyllabusScraperAgent syllabus sync completed")
        SyllabusSyncPubsub.broadcast_sync_complete(nil)

      {:error, reason} ->
        error_msg = to_string(reason)
        Logger.error("SyllabusScraperAgent syllabus sync failed reason=#{error_msg}")
        SyllabusSyncPubsub.broadcast_sync_error(nil, error_msg)
    end

    {:noreply,
     %{state | syllabus_sync: %{status: :idle, term_id: nil, ref: nil, total: 0, completed: 0}}}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    cond do
      state.term_list_sync.ref == ref ->
        {:noreply, %{state | term_list_sync: %{state.term_list_sync | ref: nil}}}

      state.syllabus_sync.ref == ref ->
        {:noreply, %{state | syllabus_sync: %{state.syllabus_sync | ref: nil}}}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    cond do
      state.term_list_sync.ref == ref ->
        error_msg = to_string(reason)
        Logger.error("SyllabusScraperAgent term list sync task crashed reason=#{error_msg}")
        SyllabusSyncPubsub.broadcast_sync_error(nil, "Term list sync task crashed: #{error_msg}")
        {:noreply, %{state | term_list_sync: %{status: :idle, ref: nil}}}

      state.syllabus_sync.ref == ref ->
        error_msg = to_string(reason)
        Logger.error("SyllabusScraperAgent syllabus sync task crashed reason=#{error_msg}")
        SyllabusSyncPubsub.broadcast_sync_error(nil, "Syllabus sync task crashed: #{error_msg}")

        {:noreply,
         %{
           state
           | syllabus_sync: %{status: :idle, term_id: nil, ref: nil, total: 0, completed: 0}
         }}

      true ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp syncing?(state) do
    state.term_list_sync.status == :syncing || state.syllabus_sync.status == :syncing
  end

  defp sync_status(state) do
    %{
      syncing?: syncing?(state),
      term_list_syncing?: state.term_list_sync.status == :syncing,
      syllabus_syncing?: state.syllabus_sync.status == :syncing,
      term_id: state.syllabus_sync.term_id,
      total: state.syllabus_sync.total,
      completed: state.syllabus_sync.completed
    }
  end
end
