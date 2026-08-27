defmodule SnowSeToolsWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use SnowSeToolsWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint SnowSeToolsWeb.Endpoint

      use SnowSeToolsWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import SnowSeToolsWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Creates (or finds) a user with `email`, adds them to the given access groups
  (names such as `"discord_admin"` or `"admin"`) and logs them in.

  A user with no groups is "pending approval" and can only reach `/pending`.
  """
  def log_in_user(conn, email, groups \\ []) do
    alias SnowSeTools.Data.{AccessControl, User}

    {:ok, user} = User.find_or_create(email)

    for group_name <- groups do
      group = Enum.find(AccessControl.list_groups(), &(&1.name == group_name))
      :ok = AccessControl.add_user_group(user_id: user.id, group_id: group.id)
    end

    Plug.Test.init_test_session(conn, %{"current_user_id" => user.id})
  end
end
