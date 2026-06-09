defmodule SimpleSyllabusReporter.Syllabi.Syncing.SyllabusScraperAgent do
  use GenServer
  require Logger

  alias SimpleSyllabusReporter.Syllabi.SyncWorker
  alias SimpleSyllabusReporter.Syllabi.Syncing.SyllabusSyncPubsub

  def start_link(_opts),
    do: GenServer.start_link(__MODULE__, :idle, name: __MODULE__)

  def sync_term(term_id) do
    GenServer.cast(__MODULE__, {:sync_term, term_id})
    :ok
  end

  def sync_term_list do
    GenServer.cast(__MODULE__, :sync_term_list)
    :ok
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

  @impl true
  def init(:idle) do
    {:ok,
     %{
       term_list_sync: %{status: :idle, ref: nil},
       syllabus_sync: %{status: :idle, term_id: nil, ref: nil, total: 0, completed: 0}
     }}
  end

  @impl true
  def handle_cast({:sync_term, term_id}, state) do
    if state.syllabus_sync.status == :syncing do
      Logger.warning(
        "SyllabusScraperAgent syllabus sync already in progress, ignoring term sync request"
      )

      {:noreply, state}
    else
      parent = self()

      {_pid, ref} =
        spawn_monitor(fn ->
          result = SyncWorker.sync_term(term_id: term_id)
          send(parent, {:syllabus_sync_done, result})
        end)

      {:noreply,
       %{
         state
         | syllabus_sync: %{status: :syncing, term_id: term_id, ref: ref, total: 0, completed: 0}
       }}
    end
  end

  def handle_cast(:sync_term_list, state) do
    if state.term_list_sync.status == :syncing do
      Logger.warning(
        "SyllabusScraperAgent term list sync already in progress, ignoring term list sync request"
      )

      {:noreply, state}
    else
      parent = self()

      {_pid, ref} =
        spawn_monitor(fn ->
          result = SyncWorker.sync_term_list()
          send(parent, {:term_list_sync_done, result})
        end)

      {:noreply, %{state | term_list_sync: %{status: :syncing, ref: ref}}}
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

  @impl true
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
end
