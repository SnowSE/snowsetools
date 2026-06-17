defmodule SnowSeTools.UserGroups.UserGroupDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.Data.AccessControl
  alias SnowSeToolsWeb.Admin.AdminUIMessages

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def request_dashboard(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_dashboard, pid})
  end

  def create_group(pid: pid, group_params: group_params) do
    GenServer.cast(__MODULE__, {:create_group, pid, group_params})
  end

  def update_group(pid: pid, group_id: group_id, group_params: group_params) do
    GenServer.cast(__MODULE__, {:update_group, pid, group_id, group_params})
  end

  def delete_group(pid: pid, group_id: group_id) do
    GenServer.cast(__MODULE__, {:delete_group, pid, group_id})
  end

  def create_user(pid: pid, user_params: user_params) do
    GenServer.cast(__MODULE__, {:create_user, pid, user_params})
  end

  def add_user_group(pid: pid, user_id: user_id, group_id: group_id) do
    GenServer.cast(__MODULE__, {:add_user_group, pid, user_id, group_id})
  end

  def remove_user_group(pid: pid, user_id: user_id, group_id: group_id) do
    GenServer.cast(__MODULE__, {:remove_user_group, pid, user_id, group_id})
  end

  @impl true
  def init(:ok) do
    case AccessControl.bootstrap_access_control() do
      {:error, reason} ->
        Logger.error("AccessControl bootstrap failed reason=#{inspect(reason)}")
        {:stop, reason}

      _ ->
        {:ok, %{}}
    end
  end

  @impl true
  def handle_cast({:request_dashboard, pid}, state) do
    send_users(pid)
    send_groups(pid)
    {:noreply, state}
  end

  def handle_cast({:create_group, pid, group_params}, state) do
    case AccessControl.create_group(group_params) do
      {:ok, _group} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:ok, "Group created."})
        send_users(pid)
        send_groups(pid)

      {:error, reason} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, reason})
    end

    {:noreply, state}
  end

  def handle_cast({:update_group, pid, group_id, group_params}, state) do
    case AccessControl.update_group(group_id: group_id, group_params: group_params) do
      {:ok, _group} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:ok, "Group updated."})
        send_users(pid)
        send_groups(pid)

      {:error, reason} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, reason})
    end

    {:noreply, state}
  end

  def handle_cast({:delete_group, pid, group_id}, state) do
    case AccessControl.delete_group(group_id: group_id) do
      :ok ->
        AdminUIMessages.send_action_result(pid: pid, result: {:ok, "Group deleted."})
        send_users(pid)
        send_groups(pid)

      {:error, reason} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, reason})
    end

    {:noreply, state}
  end

  def handle_cast({:create_user, pid, user_params}, state) do
    case AccessControl.create_user(email: Map.get(user_params, "email", "")) do
      {:ok, _user} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:ok, "User created."})
        send_users(pid)
        send_groups(pid)

      {:error, reason} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, reason})
    end

    {:noreply, state}
  end

  def handle_cast({:add_user_group, pid, user_id, group_id}, state) do
    case AccessControl.add_user_group(user_id: user_id, group_id: group_id) do
      :ok ->
        AdminUIMessages.send_action_result(pid: pid, result: {:ok, "Group membership added."})
        send_users(pid)
        send_groups(pid)

      {:error, reason} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, reason})
    end

    {:noreply, state}
  end

  def handle_cast({:remove_user_group, pid, user_id, group_id}, state) do
    case AccessControl.remove_user_group(user_id: user_id, group_id: group_id) do
      :ok ->
        AdminUIMessages.send_action_result(pid: pid, result: {:ok, "Group membership removed."})
        send_users(pid)
        send_groups(pid)

      {:error, reason} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, reason})
    end

    {:noreply, state}
  end

  defp load_users do
    normalize_rows(AccessControl.list_users_with_groups())
  end

  defp load_groups do
    normalize_rows(AccessControl.list_groups())
  end

  defp send_users(pid) do
    case load_users() do
      {:ok, users} ->
        AdminUIMessages.send_users(pid: pid, users: users)

      {:error, reason} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, reason})
    end
  end

  defp send_groups(pid) do
    case load_groups() do
      {:ok, groups} ->
        AdminUIMessages.send_groups(pid: pid, groups: groups)

      {:error, reason} ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, reason})
    end
  end

  defp normalize_rows(rows) when is_list(rows), do: {:ok, rows}
  defp normalize_rows({:error, reason}), do: {:error, reason}
  defp normalize_rows(other), do: {:error, other}
end
