defmodule SnowSeTools.TestSupport.Fakes.DeployedEndpoint do
  @moduledoc """
  Answers the one question `Phoenix.LiveView.static_changed?/1` asks an
  endpoint: which digested assets the running build serves. The test endpoint
  has no asset manifest, so it can never tell a stale client from a current one.
  """

  def config(:cache_static_manifest_latest),
    do: %{
      "assets/js/app.js" => "assets/js/app-new.js",
      "assets/css/app.css" => "assets/css/app-new.css"
    }
end
