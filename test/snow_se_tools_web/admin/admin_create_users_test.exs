defmodule SnowSeToolsWeb.Admin.AdminCreateUsersTest do
  @moduledoc """
  The "Create users" box takes a whole pasted list, and the role checkboxes
  next to it apply to everyone in that list. The rule that matters most: a role
  can be added this way, but an address already on the books never loses one.
  """
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.AccessControl
  alias SnowSeTools.UserGroups.UserGroupDomainManager

  setup do
    start_supervised!(UserGroupDomainManager)
    :ok
  end

  test "a pasted Outlook list creates every address with the checked roles", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    settle(view)

    one = unique_email("one")
    two = unique_email("two")
    pasted = ~s("First Last" <#{String.upcase(one)}>; "Other Person" <#{two}>)

    check_role(view, "scheduling_view")
    check_role(view, "discord_admin")

    html = submit_users(view, pasted)

    assert html =~ "Added 2 users"
    assert group_names(one) == ["discord_admin", "scheduling_view"]
    assert group_names(two) == ["discord_admin", "scheduling_view"]
  end

  test "an address that is already a user keeps the roles it has", %{conn: conn} do
    existing = unique_email("existing")
    {:ok, user} = AccessControl.create_user(email: existing)
    :ok = add_group(user.id, "syllabus_admin")

    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    settle(view)

    check_role(view, "discord_admin")
    submit_users(view, existing)

    assert group_names(existing) == ["discord_admin", "syllabus_admin"]
  end

  test "checked roles clear once the users are added", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    settle(view)

    check_role(view, "discord_admin")
    assert checked?(view, "discord_admin")

    submit_users(view, unique_email("cleared"))

    refute checked?(view, "discord_admin")
  end

  test "text with no address in it is refused", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    settle(view)

    assert submit_users(view, "First Last") =~ "No email address found in that list."
  end

  defp submit_users(view, pasted) do
    view
    |> form("#admin-user-form", %{"user" => %{"email" => pasted}})
    |> render_submit()

    settle(view)
  end

  defp check_role(view, group_name) do
    view
    |> element("#new-user-group-#{group_id(group_name)}")
    |> render_click()
  end

  defp checked?(view, group_name) do
    has_element?(view, "#new-user-group-#{group_id(group_name)}[checked]")
  end

  defp group_id(group_name) do
    {:ok, groups} = AccessControl.list_groups()
    Enum.find(groups, &(&1.name == group_name)).id
  end

  defp add_group(user_id, group_name) do
    AccessControl.add_user_group(user_id: user_id, group_id: group_id(group_name))
  end

  defp group_names(email) do
    {:ok, users} = AccessControl.list_users_with_groups()

    users
    |> Enum.find(&(&1.email == String.downcase(email)))
    |> Map.fetch!(:group_names)
    |> Enum.sort()
  end

  # The create runs through a cast to the domain manager, which answers the
  # LiveView with a message of its own.
  defp settle(view) do
    _ = :sys.get_state(UserGroupDomainManager)
    _ = :sys.get_state(view.pid)
    render(view)
  end

  defp log_in_admin(conn), do: log_in_user(conn, unique_email("create-users-admin"), ["admin"])
end
