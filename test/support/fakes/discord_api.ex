defmodule SnowSeTools.TestSupport.Fakes.DiscordApi do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{calls: [], created_channels: [], renamed_channels: %{}} end,
      name: __MODULE__
    )
  end

  def calls do
    Agent.get(__MODULE__, & &1.calls)
  end

  def fetch_guild, do: unexpected_call(:fetch_guild, %{})
  def fetch_current_user, do: unexpected_call(:fetch_current_user, %{})
  def fetch_members, do: unexpected_call(:fetch_members, %{})

  def fetch_channels do
    expected_call(:fetch_channels, %{})

    cached_channels =
      case SnowSeTools.Discord.DiscordDb.list_channels() do
        channels when is_list(channels) -> Enum.map(channels, &Map.get(&1, "data", &1))
        {:error, _reason} -> []
      end

    state = Agent.get(__MODULE__, & &1)
    renamed_channels = state.renamed_channels

    channels =
      (cached_channels ++ state.created_channels)
      |> Enum.map(fn channel ->
        case Map.fetch(renamed_channels, Map.get(channel, "id")) do
          {:ok, new_name} -> %{channel | "name" => new_name}
          :error -> channel
        end
      end)

    {:ok, channels}
  end

  def fetch_roles, do: unexpected_call(:fetch_roles, %{})
  def fetch_invites, do: unexpected_call(:fetch_invites, %{})

  def add_role_to_member(member_id: member_id, role_id: role_id),
    do: expected_call(:add_role_to_member, %{member_id: member_id, role_id: role_id})

  def create_text_channel(name: name, parent_id: parent_id) do
    channel_id = "created-channel-#{System.unique_integer([:positive])}"

    channel = %{
      "id" => channel_id,
      "name" => name,
      "type" => 0,
      "parent_id" => parent_id,
      "position" => 50,
      "permission_overwrites" => []
    }

    Agent.update(__MODULE__, fn state ->
      %{
        state
        | calls: [{:create_text_channel, %{name: name, parent_id: parent_id}} | state.calls],
          created_channels: [channel | state.created_channels]
      }
    end)

    {:ok, %{channel | "name" => channel_id}}
  end

  def rename_channel(channel_id: channel_id, new_name: new_name) do
    Agent.update(__MODULE__, fn state ->
      %{
        state
        | calls: [{:rename_channel, %{channel_id: channel_id, new_name: new_name}} | state.calls],
          renamed_channels: Map.put(state.renamed_channels, channel_id, new_name)
      }
    end)

    {:ok, %{"id" => channel_id, "name" => channel_id}}
  end

  def delete_channel(channel_id: channel_id) do
    expected_call(:delete_channel, %{channel_id: channel_id})
  end

  defp expected_call(function_name, metadata) do
    Agent.update(__MODULE__, fn state ->
      %{state | calls: [{function_name, metadata} | state.calls]}
    end)

    {:ok, metadata}
  end

  defp unexpected_call(function_name, metadata) do
    Agent.update(__MODULE__, fn state ->
      %{state | calls: [{function_name, metadata} | state.calls]}
    end)

    {:error, {:unexpected_discord_api_call, function_name}}
  end
end
