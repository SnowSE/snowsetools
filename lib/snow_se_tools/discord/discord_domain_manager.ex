defmodule SnowSeTools.Discord.DiscordDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.Discord.{DiscordApi, DiscordDb, DiscordPubSub}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def request_sync_summary(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_sync_summary, pid, key})
  end

  def request_server_status(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_server_status, pid, key})
  end

  def request_channels(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_channels, pid, key})
  end

  def request_members(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_members, pid, key})
  end

  def request_roles(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_roles, pid, key})
  end

  def request_invites(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_invites, pid, key})
  end

  def sync_all(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:sync_all, pid})
  end

  def init(:ok) do
    case DiscordDb.bootstrap_discord_tables() do
      {:error, reason} ->
        Logger.error("Discord domain bootstrap failed reason=#{inspect(reason)}")
        {:stop, reason}

      _ ->
        {:ok, %{}}
    end
  end

  def handle_cast({:request_sync_summary, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:sync_summary_loaded, key},
      fetch: &DiscordDb.sync_summary/0,
      error_context: "Discord sync summary load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_server_status, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:server_status_loaded, key},
      fetch: &DiscordDb.get_server_status/0,
      error_context: "Discord server status load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_channels, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:channels_loaded, key},
      fetch: &DiscordDb.list_channels/0,
      error_context: "Discord channels load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_members, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:members_loaded, key},
      fetch: &DiscordDb.list_members/0,
      error_context: "Discord members load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_roles, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:roles_loaded, key},
      fetch: &DiscordDb.list_roles/0,
      error_context: "Discord roles load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_invites, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:invites_loaded, key},
      fetch: &DiscordDb.list_invites/0,
      error_context: "Discord invites load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:sync_all, pid}, state) do
    Task.start(fn -> sync_all_async(pid) end)
    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.debug("DiscordDomainManager ignored message=#{inspect(message)}")
    {:noreply, state}
  end

  defp sync_all_async(pid) do
    sync_results =
      [
        {:guild, fn -> sync_guild() end},
        {:bot_user, fn -> sync_bot_user() end},
        {:members, fn -> sync_members() end},
        {:channels, fn -> sync_channels() end},
        {:roles, fn -> sync_roles() end},
        {:invites, fn -> sync_invites() end}
      ]
      |> Task.async_stream(
        fn {resource, sync_function} -> {resource, sync_function.()} end,
        timeout: :infinity,
        max_concurrency: 4
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:task, {:error, reason}}
      end)

    failed_results =
      Enum.filter(sync_results, fn
        {_resource, :ok} -> false
        {_resource, {:error, _reason}} -> true
      end)

    if failed_results == [] do
      summary = safe_sync_summary()
      DiscordPubSub.broadcast_discord_data_synced(summary)
      send(pid, {:discord, {:sync_finished, {:ok, summary}}})
    else
      reasons =
        Enum.map(failed_results, fn {resource, {:error, reason}} ->
          "#{resource}: #{inspect(reason)}"
        end)

      Logger.error("Discord sync failed reasons=#{Enum.join(reasons, "; ")}")
      send(pid, {:discord, {:sync_finished, {:error, reasons}}})
    end
  end

  defp sync_guild do
    with {:ok, guild} <- DiscordApi.fetch_guild(),
         :ok <- DiscordDb.save_guild(guild: guild) do
      :ok
    end
  end

  defp sync_bot_user do
    with {:ok, bot_user} <- DiscordApi.fetch_current_user(),
         :ok <- DiscordDb.save_bot_user(bot_user: bot_user) do
      :ok
    end
  end

  defp sync_members do
    with {:ok, members} <- DiscordApi.fetch_members(),
         :ok <- DiscordDb.save_members(members: members) do
      :ok
    end
  end

  defp sync_channels do
    with {:ok, channels} <- DiscordApi.fetch_channels(),
         :ok <- DiscordDb.save_channels(channels: channels) do
      :ok
    end
  end

  defp sync_roles do
    with {:ok, roles} <- DiscordApi.fetch_roles(),
         :ok <- DiscordDb.save_roles(roles: roles) do
      :ok
    end
  end

  defp sync_invites do
    with {:ok, invites} <- DiscordApi.fetch_invites(),
         :ok <- DiscordDb.save_invites(invites: invites) do
      :ok
    end
  end

  defp safe_sync_summary do
    case DiscordDb.sync_summary() do
      {:error, reason} ->
        Logger.error("Discord summary load failed reason=#{inspect(reason)}")
        []

      summary ->
        summary
    end
  end

  defp send_db_result(pid: pid, message: {event, key}, fetch: fetch, error_context: error_context) do
    case fetch.() do
      {:error, reason} ->
        Logger.error("#{error_context} reason=#{inspect(reason)}")
        send(pid, {:discord, {event, key, {:error, reason}}})

      data ->
        send(pid, {:discord, {event, key, {:ok, data}}})
    end
  end
end
