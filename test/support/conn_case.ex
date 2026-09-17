defmodule SnowSeToolsWeb.ConnCase do
  @moduledoc """
  The test case for tests that need a connection: `Phoenix.ConnTest`,
  `Phoenix.LiveViewTest` and the login helper below.

  **There is no SQL sandbox.** `SnowSeTools.TestDatabase.reset!/0` runs once in
  `test_helper.exs`, so every test in every file shares one database and rows
  written by one test are still there for the next. Three rules follow:

    * Name fixtures uniquely — `unique_email/1`, or anything carrying
      `System.unique_integer([:positive])`. Two files that both insert
      "Test Program" will fight.
    * Never assert on absence or on a global count ("no layouts exist yet").
      Assert on rows your own test made.
    * `async: true` is only safe for tests that do not touch the database.
      Render-only and pure-function tests qualify; anything that writes a row
      does not.

  The suite seeds a throwaway account before any test runs, so the admin group
  that `AccessControl.create_user/1` grants to the first user in the table
  never lands on a test account by accident.
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
  An email nothing else in the suite will use.
  """
  def unique_email(prefix \\ "user"),
    do: "#{prefix}-#{System.unique_integer([:positive])}@example.com"

  @doc """
  Creates (or finds) a user with `email`, adds them to the given access groups
  (names such as `"discord_admin"` or `"admin"`) and logs them in.

  A user with no groups is "pending approval" and can only reach `/pending`.
  """
  def log_in_user(conn, email, groups \\ []) do
    alias SnowSeTools.Data.{AccessControl, User}

    {:ok, user} = User.find_or_create(email)

    {:ok, all_groups} = AccessControl.list_groups()

    for group_name <- groups do
      group = Enum.find(all_groups, &(&1.name == group_name))
      :ok = AccessControl.add_user_group(user_id: user.id, group_id: group.id)
    end

    Plug.Test.init_test_session(conn, %{"current_user_id" => user.id})
  end
end
