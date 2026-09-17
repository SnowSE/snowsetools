defmodule SnowSeToolsWeb.Auth.AccessTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.{Access, AccessControl, User}

  describe "Access" do
    test "super users can use every area; others need the area group" do
      admin = %{group_names: ["admin"]}
      discord = %{group_names: ["discord_admin"]}
      nobody = %{group_names: []}

      for area <- [:syllabi, :scheduling, :discord, :admin] do
        assert Access.can?(admin, area)
        refute Access.can?(nobody, area)
      end

      assert Access.can?(discord, :discord)
      refute Access.can?(discord, :scheduling)
      refute Access.can?(discord, :admin)

      assert Access.approved?(discord)
      refute Access.approved?(nobody)
    end

    test "scheduling has a read-only tier below its editor group" do
      viewer = %{group_names: ["scheduling_view"]}
      editor = %{group_names: ["scheduling_admin"]}
      admin = %{group_names: ["admin"]}

      assert Access.can?(viewer, :scheduling)
      refute Access.can_edit?(viewer, :scheduling)
      refute Access.can?(viewer, :syllabi)

      assert Access.can?(editor, :scheduling)
      assert Access.can_edit?(editor, :scheduling)

      assert Access.can_edit?(admin, :scheduling)
      assert Access.approved?(viewer)
    end

    test "areas with no read-only tier are all-or-nothing" do
      for area <- [:syllabi, :discord, :admin] do
        holder = %{group_names: [Access.edit_group_for(area)]}

        assert Access.can?(holder, area)
        assert Access.can_edit?(holder, area)
      end
    end

    test "a scheduling viewer sees the area once, at the level they hold" do
      viewer = %{group_names: ["scheduling_view"]}
      both = %{group_names: ["scheduling_view", "scheduling_admin"]}

      assert [%{area: :scheduling, level: :view}] = Access.accessible_areas(viewer)
      assert [%{area: :scheduling, level: :edit}] = Access.accessible_areas(both)
    end

    test "built-in groups are seeded and cannot be renamed or deleted" do
      {:ok, groups} = AccessControl.list_groups()
      names = Enum.map(groups, & &1.name)

      for name <- ~w(admin discord_admin scheduling_admin scheduling_view syllabus_admin) do
        assert name in names
        group = Enum.find(groups, &(&1.name == name))
        assert {:error, :protected_group_locked} = AccessControl.delete_group(group_id: group.id)

        assert {:error, :protected_group_locked} =
                 AccessControl.update_group(group_id: group.id, group_params: %{"name" => "x"})
      end
    end
  end

  describe "routes" do
    setup do
      start_supervised!(SnowSeTools.UserGroups.UserGroupDomainManager)
      :ok
    end

    test "a user with no groups is sent to the approval page", %{conn: conn} do
      conn = log_in_user(conn, "pending-user@example.com")

      assert {:error, {:redirect, %{to: "/pending"}}} = live(conn, ~p"/home")
      assert {:error, {:redirect, %{to: "/pending"}}} = live(conn, ~p"/discord")

      {:ok, _view, html} = live(conn, ~p"/pending")
      assert html =~ "Awaiting approval"
      assert html =~ "Jonathan Allen"
    end

    test "an approved user reaches home and only their own areas", %{conn: conn} do
      conn = log_in_user(conn, "discord-only@example.com", ["discord_admin"])

      {:ok, _view, html} = live(conn, ~p"/home")
      assert html =~ "Discord"
      refute html =~ ~s(href="/scheduling")
      refute html =~ ~s(href="/admin")

      assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/scheduling")
      assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/syllabi")
      assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/admin")
    end

    test "super users reach the admin page and see pending users", %{conn: conn} do
      {:ok, _} = User.find_or_create("someone-waiting@example.com")
      conn = log_in_user(conn, "super-user@example.com", ["admin"])

      {:ok, view, _html} = live(conn, ~p"/admin")
      # The dashboard is delivered asynchronously by the domain manager.
      _ = :sys.get_state(SnowSeTools.UserGroups.UserGroupDomainManager)
      html = render(view)
      assert html =~ "someone-waiting@example.com"
      assert html =~ "awaiting approval"
    end

    test "anonymous requests are redirected to login", %{conn: conn} do
      conn = get(conn, ~p"/home")
      assert redirected_to(conn) =~ "/auth/login"
    end
  end
end
