defmodule SnowSeToolsWeb.Discord.DiscordLive do
  use SnowSeToolsWeb, :live_view

  alias SnowSeToolsWeb.Discord.DiscordDashboard

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Discord")
     |> DiscordDashboard.assign_component()}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <DiscordDashboard.render
        state={@discord_dashboard}
        guild_name={item_name(@discord_dashboard.dashboard.guilds)}
      />
    </Layouts.app>
    """
  end

  defp item_name([item | _items]), do: item["name"] || item["id"] || "Discord"
  defp item_name([]), do: "Discord"
end
