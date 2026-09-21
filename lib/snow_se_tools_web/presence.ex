defmodule SnowSeToolsWeb.Presence do
  @moduledoc """
  Who is connected, tracked per LiveView process.

  `SnowSeToolsWeb.OnlineUsers` owns what goes in a presence entry and who is
  allowed to read it; this module is only the registry it is kept in.
  """

  use Phoenix.Presence,
    otp_app: :snow_se_tools,
    pubsub_server: SnowSeTools.PubSub
end
