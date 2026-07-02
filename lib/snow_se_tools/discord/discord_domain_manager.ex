defmodule SnowSeTools.Discord.DiscordDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.Discord.{DiscordApi, DiscordDb, DiscordPubSub}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def request_dashboard(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_dashboard, pid})
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

  def handle_cast({:request_dashboard, pid}, state) do
    send_dashboard(pid)
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
      summary = load_summary()
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

    send_dashboard(pid)
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

  defp send_dashboard(pid) do
    send(pid, {:discord, {:dashboard_loaded, load_dashboard()}})
  end

  defp load_dashboard do
    %{
      summary: load_summary(),
      guilds: load_collection(&DiscordDb.list_guilds/0, "Discord guilds load failed"),
      bot_users: load_collection(&DiscordDb.list_bot_users/0, "Discord bot users load failed"),
      members: load_collection(&DiscordDb.list_members/0, "Discord members load failed"),
      channels: load_collection(&DiscordDb.list_channels/0, "Discord channels load failed"),
      roles: load_collection(&DiscordDb.list_roles/0, "Discord roles load failed"),
      invites: load_collection(&DiscordDb.list_invites/0, "Discord invites load failed")
    }
  end

  defp load_summary do
    case DiscordDb.sync_summary() do
      {:error, reason} ->
        Logger.error("Discord summary load failed reason=#{inspect(reason)}")
        []

      summary ->
        summary
    end
  end

  defp load_collection(fetch_function, message) do
    case fetch_function.() do
      {:error, reason} ->
        Logger.error("#{message} reason=#{inspect(reason)}")
        []

      rows ->
        rows
    end
  end
end
