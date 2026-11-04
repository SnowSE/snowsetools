defmodule SnowSeToolsWeb.PageController do
  use SnowSeToolsWeb, :controller
  alias SnowSeTools.Data.User

  def home(conn, _params) do
    current_user =
      case get_session(conn, "current_user_id") do
        nil ->
          nil

        id ->
          case User.get_by_id(id) do
            {:ok, user} -> user
            _ -> nil
          end
      end

    cond do
      current_user ->
        redirect(conn, to: "/home")

      # A failed login or a logout lands here with something to say. Sending
      # those straight back to the login would loop on a broken login, and
      # would sign someone straight back in through Microsoft after logging
      # out. Everyone else has no reason to see this page.
      conn.assigns.flash != %{} ->
        render(conn, :home, current_user: nil)

      true ->
        redirect(conn, to: "/auth/login?" <> URI.encode_query(%{"return_to" => "/home"}))
    end
  end
end
