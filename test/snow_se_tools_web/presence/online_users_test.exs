defmodule SnowSeToolsWeb.OnlineUsersTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.User
  alias SnowSeToolsWeb.{OnlineUsers, Presence}

  # Presence is one list for the whole node, so a test that counts who is on it
  # has to start from an empty one: LiveViews from earlier tests are still
  # being reaped when this one begins.
  setup do
    wait_for_an_empty_site()
    :ok
  end

  describe "the online banner" do
    test "tells a super user who else is here, and what page they are on", %{conn: conn} do
      other = put_online(unique_email("online-other"), path: "/scheduling", on_page_for: 300)

      widget = open_banner(conn)

      assert has_element?(widget, "#online-users-banner", "1 other user online")
      assert has_element?(widget, "#online-users-tooltip", other.email)
      assert has_element?(widget, "#online-users-tooltip", "Scheduling")
      assert has_element?(widget, "#online-users-tooltip", "5 min")
    end

    test "counts several people in the banner", %{conn: conn} do
      put_online(unique_email("online-first"), path: "/syllabi")
      put_online(unique_email("online-second"), path: "/discord")

      widget = open_banner(conn)

      assert has_element?(widget, "#online-users-banner", "2 other users online")
    end

    test "leaves out someone who stopped using the site", %{conn: conn} do
      idle = put_online(unique_email("online-idle"), path: "/discord", idle_for: 600)
      here = put_online(unique_email("online-here"), path: "/discord")

      widget = open_banner(conn)

      assert has_element?(widget, "#online-users-banner", "1 other user online")
      assert has_element?(widget, "#online-users-tooltip", here.email)
      refute has_element?(widget, "#online-users-tooltip", idle.email)
    end

    test "goes away once the last of them closes the page", %{conn: conn} do
      other = put_online(unique_email("online-leaver"), path: "/home")

      widget = open_banner(conn)
      assert has_element?(widget, "#online-users-banner", "1 other user online")

      leave(other)

      eventually(fn -> !has_element?(widget, "#online-users-banner") end)
    end

    test "never shows itself to someone who is not a super user", %{conn: conn} do
      put_online(unique_email("online-other"), path: "/home")

      {:ok, view, _html} =
        live(log_in_user(conn, unique_email("online-viewer"), ["syllabus_admin"]), ~p"/syllabi")

      refute has_element?(view, "#online-users-banner")
    end

    test "does not count the super user's own page", %{conn: conn} do
      email = unique_email("online-admin")
      conn = log_in_user(conn, email, ["admin"])

      {:ok, view, _html} = live(conn, ~p"/home")

      # Their own page tracked them; the banner is about everyone else.
      assert [_viewer] = Enum.filter(online_emails(), &(&1 == email))
      refute has_element?(view, "#online-users-banner")
    end
  end

  defp open_banner(conn) do
    {:ok, view, _html} =
      live(log_in_user(conn, unique_email("online-admin"), ["admin"]), ~p"/home")

    find_live_child(view, "online-users-widget")
  end

  # Someone else's open page, held by a process of its own so the test can put
  # it down again.
  defp put_online(email, opts) do
    {:ok, user} = User.find_or_create(email)
    now = System.system_time(:second)
    test_pid = self()

    meta = %{
      email: email,
      path: Keyword.fetch!(opts, :path),
      page_since: now - Keyword.get(opts, :on_page_for, 0),
      active_at: now - Keyword.get(opts, :idle_for, 0)
    }

    pid =
      spawn(fn ->
        {:ok, _ref} = Presence.track(self(), OnlineUsers.topic(), to_string(user.id), meta)
        send(test_pid, :tracked)

        receive do
          :leave -> :ok
        end
      end)

    assert_receive :tracked
    on_exit(fn -> Process.exit(pid, :kill) end)

    %{email: email, id: user.id, pid: pid}
  end

  defp leave(%{pid: pid}), do: send(pid, :leave)

  defp wait_for_an_empty_site(attempts \\ 100) do
    cond do
      Presence.list(OnlineUsers.topic()) == %{} -> :ok
      attempts == 0 -> flunk("someone from an earlier test is still online")
      true -> Process.sleep(10) && wait_for_an_empty_site(attempts - 1)
    end
  end

  defp online_emails do
    OnlineUsers.topic()
    |> Presence.list()
    |> Enum.flat_map(fn {_id, %{metas: metas}} -> Enum.map(metas, & &1.email) end)
  end

  defp eventually(condition, attempts \\ 40) do
    cond do
      condition.() -> :ok
      attempts == 0 -> flunk("the banner never went away")
      true -> Process.sleep(25) && eventually(condition, attempts - 1)
    end
  end
end
