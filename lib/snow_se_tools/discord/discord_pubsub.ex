defmodule SnowSeTools.Discord.DiscordPubSub do
  @topic "discord"

  def subscribe do
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @topic)
  end

  def broadcast_discord_data_synced(summary) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:discord, {:data_synced, summary}}
    )
  end
end
