defmodule SnowSeTools.TestSupport.Fakes.DiscordApi do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def calls do
    Agent.get(__MODULE__, & &1)
  end

  def fetch_guild, do: unexpected_call(:fetch_guild, %{})
  def fetch_current_user, do: unexpected_call(:fetch_current_user, %{})
  def fetch_members, do: unexpected_call(:fetch_members, %{})
  def fetch_channels, do: unexpected_call(:fetch_channels, %{})
  def fetch_roles, do: unexpected_call(:fetch_roles, %{})
  def fetch_invites, do: unexpected_call(:fetch_invites, %{})

  def add_role_to_member(member_id: member_id, role_id: role_id),
    do: expected_call(:add_role_to_member, %{member_id: member_id, role_id: role_id})

  def create_text_channel(name: name, parent_id: parent_id) do
    expected_call(:create_text_channel, %{name: name, parent_id: parent_id})

    {:ok,
     %{
       "id" => "created-channel-#{System.unique_integer([:positive])}",
       "name" => name,
       "type" => 0,
       "parent_id" => parent_id,
       "position" => 50,
       "permission_overwrites" => []
     }}
  end

  def delete_channel(channel_id: channel_id) do
    expected_call(:delete_channel, %{channel_id: channel_id})
  end

  defp expected_call(function_name, metadata) do
    Agent.update(__MODULE__, &[{function_name, metadata} | &1])
    {:ok, metadata}
  end

  defp unexpected_call(function_name, metadata) do
    Agent.update(__MODULE__, &[{function_name, metadata} | &1])
    {:error, {:unexpected_discord_api_call, function_name}}
  end
end
