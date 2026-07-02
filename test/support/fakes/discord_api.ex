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
    do: unexpected_call(:add_role_to_member, %{member_id: member_id, role_id: role_id})

  defp unexpected_call(function_name, metadata) do
    Agent.update(__MODULE__, &[{function_name, metadata} | &1])
    {:error, {:unexpected_discord_api_call, function_name}}
  end
end
