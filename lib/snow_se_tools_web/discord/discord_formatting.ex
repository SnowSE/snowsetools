defmodule SnowSeToolsWeb.Discord.DiscordFormatting do
  def item_name(nil), do: "Not synced"
  def item_name(item), do: item["name"] || item["id"] || "Not synced"

  def member_username(member) do
    member
    |> Map.get("data", %{})
    |> Map.get("user", %{})
    |> Map.get("username", member["id"])
  end

  def invite_url(invite) do
    data = Map.get(invite, "data", %{})
    Map.get(data, "url") || "https://discord.gg/#{invite["id"]}"
  end

  def invite_channel_name(invite) do
    invite
    |> Map.get("data", %{})
    |> Map.get("channel", %{})
    |> Map.get("name", "unknown")
  end

  def role_color(role) do
    color =
      role
      |> Map.get("data", %{})
      |> Map.get("color", 0)

    "#" <> String.pad_leading(Integer.to_string(color, 16), 6, "0")
  end

  def format_synced_at(nil), do: "never"
  def format_synced_at(""), do: "never"

  def format_synced_at(synced_at) when is_binary(synced_at) do
    synced_at
    |> String.replace("T", " ")
    |> String.replace(~r/\.\d+.*/, "")
  end
end
