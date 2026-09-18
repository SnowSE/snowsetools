defmodule SnowSeTools.UserGroups.UserGroupDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.Data.{Access, AccessControl, EmailList}
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
    emails = EmailList.parse(Map.get(user_params, "email", ""))
    group_ids = Map.get(user_params, "group_ids", []) |> List.wrap()

    case emails do
      [] ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, :invalid_email})

      emails ->
        {created, failed} = create_users(emails: emails, group_ids: group_ids)

        if created != [] do
          send_users(pid)
          send_groups(pid)
        end

        AdminUIMessages.send_action_result(
          pid: pid,
          result: create_users_result(created: created, failed: failed, group_ids: group_ids)
        )
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

  # Every address in the box is created, and each checked role is added on top
  # of whatever the person already holds. An address that is already a user is
  # an upsert, so re-pasting a list never costs anyone an existing role.
  defp create_users(emails: emails, group_ids: group_ids) do
    {created, failed} =
      Enum.reduce(emails, {[], []}, fn email, {created, failed} ->
        case create_user_with_groups(email: email, group_ids: group_ids) do
          {:ok, email} -> {[email | created], failed}
          {:error, reason} -> {created, [{email, reason} | failed]}
        end
      end)

    {Enum.reverse(created), Enum.reverse(failed)}
  end

  defp create_user_with_groups(email: email, group_ids: group_ids) do
    with {:ok, user} <- AccessControl.create_user(email: email),
         :ok <- add_groups(user_id: user.id, group_ids: group_ids) do
      {:ok, email}
    end
  end

  defp add_groups(user_id: user_id, group_ids: group_ids) do
    Enum.reduce_while(group_ids, :ok, fn group_id, :ok ->
      case AccessControl.add_user_group(user_id: user_id, group_id: group_id) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_users_result(created: created, failed: [], group_ids: group_ids) do
    {:ok, created_message(created: created, group_ids: group_ids)}
  end

  defp create_users_result(created: created, failed: failed, group_ids: group_ids) do
    Logger.error("Failed to create users: #{inspect(failed)}")

    could_not = "Could not add " <> Enum.map_join(failed, ", ", fn {email, _reason} -> email end)

    if created == [] do
      {:error, could_not <> "."}
    else
      {:error, created_message(created: created, group_ids: group_ids) <> " " <> could_not <> "."}
    end
  end

  defp created_message(created: created, group_ids: group_ids) do
    people =
      case created do
        [email] -> "Added #{email}"
        created -> "Added #{length(created)} users"
      end

    case role_names(group_ids) do
      [] -> people <> "."
      names -> people <> " with #{Enum.join(names, ", ")}."
    end
  end

  defp role_names([]), do: []

  defp role_names(group_ids) do
    case load_groups() do
      {:ok, groups} ->
        groups
        |> Enum.filter(&(&1.id in group_ids))
        |> Enum.map(&role_label(&1.name))

      {:error, _reason} ->
        []
    end
  end

  defp role_label(group_name) do
    case Access.area_for_group(group_name) do
      %{label: label} -> label
      nil -> group_name
    end
  end

  defp load_users, do: AccessControl.list_users_with_groups()

  defp load_groups, do: AccessControl.list_groups()

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
end
