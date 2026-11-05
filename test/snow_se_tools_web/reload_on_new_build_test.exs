defmodule SnowSeToolsWeb.ReloadOnNewBuildTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias SnowSeTools.TestSupport.Fakes.DeployedEndpoint
  alias SnowSeToolsWeb.ReloadOnNewBuild

  test "a tab still running the previous deploy's assets reloads the page it was on" do
    socket =
      connected_socket(
        assets: ["/assets/js/app-old.js?vsn=d"],
        return_to: "/scheduling?term=202640"
      )

    assert {:halt, %Socket{redirected: {:redirect, %{to: "/scheduling?term=202640"}}}} =
             ReloadOnNewBuild.on_mount(:default, %{}, %{}, socket)
  end

  test "a tab running this deploy's assets carries on" do
    socket = connected_socket(assets: ["/assets/js/app-new.js?vsn=d"], return_to: "/scheduling")

    assert {:cont, %Socket{redirected: nil}} =
             ReloadOnNewBuild.on_mount(:default, %{}, %{}, socket)
  end

  test "a return path that would leave the site reloads the landing page instead" do
    socket =
      connected_socket(assets: ["/assets/js/app-old.js?vsn=d"], return_to: "//elsewhere.example")

    assert {:halt, %Socket{redirected: {:redirect, %{to: "/"}}}} =
             ReloadOnNewBuild.on_mount(:default, %{}, %{}, socket)
  end

  test "a nested LiveView is left to its parent" do
    socket = %{
      connected_socket(assets: ["/assets/js/app-old.js"], return_to: "/")
      | parent_pid: self()
    }

    assert {:cont, _socket} = ReloadOnNewBuild.on_mount(:default, %{}, %{}, socket)
  end

  defp connected_socket(assets: assets, return_to: return_to) do
    %Socket{
      endpoint: DeployedEndpoint,
      transport_pid: self(),
      parent_pid: nil,
      private: %{connect_params: %{"_track_static" => assets, "return_to" => return_to}}
    }
  end
end
