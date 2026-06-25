defmodule SnowSeTools.Scheduling.ScheduleChangeDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.Scheduling.{ScheduleChangeDb, ScheduleChangePubSub}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def create_group(name) do
    GenServer.cast(__MODULE__, {:create_group, name})
  end

  def delete_group(group_id) do
    GenServer.cast(__MODULE__, {:delete_group, group_id})
  end

  def rename_group(group_id, new_name) do
    GenServer.cast(__MODULE__, {:rename_group, group_id, new_name})
  end

  def add_or_update_change(group_id, change_attrs) do
    GenServer.cast(__MODULE__, {:add_or_update_change, group_id, change_attrs})
  end

  def remove_change(change_id) do
    GenServer.cast(__MODULE__, {:remove_change, change_id})
  end

  def list_groups(pid: pid) do
    GenServer.cast(__MODULE__, {:list_groups, pid})
  end

  def list_changes(pid: pid, group_id: group_id) do
    GenServer.cast(__MODULE__, {:list_changes, pid, group_id})
  end

  def init(:ok) do
    case ScheduleChangeDb.bootstrap_tables() do
      :ok ->
        groups = load_groups()
        changes_by_group = load_changes_by_group(groups)

        {:ok,
         %{
           groups: groups,
           changes_by_group: changes_by_group
         }}

      {:error, reason} ->
        Logger.error("Schedule change bootstrap failed reason=#{inspect(reason)}")
        {:stop, reason}
    end
  end

  def handle_cast({:create_group, name}, state) do
    case ScheduleChangeDb.create_group(name) do
      {:ok, group} ->
        ScheduleChangePubSub.broadcast_group_created(group)
        {:noreply, %{state | groups: [group | state.groups]}}

      {:error, reason} ->
        Logger.error("Failed to create schedule change group: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:delete_group, group_id}, state) do
    case ScheduleChangeDb.delete_group(group_id) do
      :ok ->
        ScheduleChangePubSub.broadcast_group_deleted(group_id)

        {:noreply,
         %{
           state
           | groups: Enum.reject(state.groups, &(&1["id"] == group_id)),
             changes_by_group: Map.delete(state.changes_by_group, group_id)
         }}

      {:error, reason} ->
        Logger.error("Failed to delete schedule change group: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:rename_group, group_id, new_name}, state) do
    case ScheduleChangeDb.rename_group(group_id, new_name) do
      {:ok, group} ->
        ScheduleChangePubSub.broadcast_group_updated(group)

        {:noreply,
         %{
           state
           | groups:
               Enum.map(state.groups, fn g ->
                 if g["id"] == group_id, do: group, else: g
               end)
         }}

      {:error, reason} ->
        Logger.error("Failed to rename schedule change group: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:add_or_update_change, group_id, change_attrs}, state) do
    case ScheduleChangeDb.add_or_update_change(group_id, change_attrs) do
      {:ok, change} ->
        ScheduleChangePubSub.broadcast_change_updated(group_id, change)

        changes = Map.get(state.changes_by_group, group_id, [])
        updated_changes = upsert_change(changes, change)

        {:noreply,
         %{state | changes_by_group: Map.put(state.changes_by_group, group_id, updated_changes)}}

      {:error, reason} ->
        Logger.error("Failed to add/update schedule change: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:remove_change, change_id}, state) do
    case ScheduleChangeDb.remove_change(change_id) do
      :ok ->
        group_id = find_change_group_id(state, change_id)

        if group_id do
          ScheduleChangePubSub.broadcast_change_removed(group_id, change_id)

          changes = Map.get(state.changes_by_group, group_id, [])
          updated_changes = Enum.reject(changes, &(&1["id"] == change_id))

          {:noreply,
           %{state | changes_by_group: Map.put(state.changes_by_group, group_id, updated_changes)}}
        else
          ScheduleChangePubSub.broadcast_change_removed(nil, change_id)
          {:noreply, state}
        end

      {:error, reason} ->
        Logger.error("Failed to remove schedule change: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:list_groups, pid}, state) do
    send(pid, {:schedule_change_groups, state.groups})
    {:noreply, state}
  end

  def handle_cast({:list_changes, pid, group_id}, state) do
    changes = Map.get(state.changes_by_group, group_id, [])
    send(pid, {:schedule_change_changes, group_id, changes})
    {:noreply, state}
  end

  defp load_groups do
    case ScheduleChangeDb.list_groups() do
      {:ok, groups} ->
        groups

      {:error, reason} ->
        Logger.error("Failed to load groups: #{inspect(reason)}")
        []
    end
  end

  defp load_changes_by_group(groups) do
    Enum.reduce(groups, %{}, fn group, acc ->
      group_id = group["id"]

      case ScheduleChangeDb.list_changes_for_group(group_id) do
        {:ok, changes} ->
          Map.put(acc, group_id, changes)

        {:error, reason} ->
          Logger.error("Failed to load changes for group #{group_id}: #{inspect(reason)}")
          acc
      end
    end)
  end

  defp upsert_change(changes, %{"id" => id} = change) do
    idx = Enum.find_index(changes, &(&1["id"] == id))

    if idx do
      List.replace_at(changes, idx, change)
    else
      [change | changes]
    end
  end

  defp find_change_group_id(state, change_id) do
    Enum.find_value(state.changes_by_group, fn {group_id, changes} ->
      if Enum.any?(changes, &(&1["id"] == change_id)), do: group_id
    end)
  end
end
