defmodule SnowSeToolsWeb.Auth.UserAuthTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.{Lifecycle, Socket}
  alias SnowSeToolsWeb.UserAuth

  describe "on_mount :ensure_session without a login" do
    test "sends a connected page through login with its path and query string" do
      socket = connected_socket(connect_params: %{"return_to" => "/scheduling?term=202660"})

      assert {:halt, socket} = UserAuth.on_mount(:ensure_session, %{}, %{}, socket)

      assert redirected_to(socket) ==
               "/auth/login?" <> URI.encode_query(%{"return_to" => "/scheduling?term=202660"})
    end

    test "sends a page with no path to plain login" do
      socket = connected_socket(connect_params: %{})

      assert {:halt, socket} = UserAuth.on_mount(:ensure_session, %{}, %{}, socket)
      assert redirected_to(socket) == "/auth/login"
    end

    test "sends a nested LiveView to plain login, since only the root has connect params" do
      socket = %{connected_socket(connect_params: nil) | parent_pid: self()}

      assert {:halt, socket} = UserAuth.on_mount(:ensure_session, %{}, %{}, socket)
      assert redirected_to(socket) == "/auth/login"
    end
  end

  defp connected_socket(connect_params: connect_params) do
    %Socket{
      transport_pid: self(),
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{connect_params: connect_params, lifecycle: %Lifecycle{}, live_temp: %{}}
    }
  end

  defp redirected_to(%Socket{redirected: {:redirect, %{to: to}}}), do: to
end
