defmodule SnowSeToolsWeb.Scheduling.ScheduleLayoutsTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.User

  alias SnowSeTools.Scheduling.{
    ScheduleChangeDomainManager,
    ScheduleLayoutDb,
    ScheduleLayoutDomainManager,
    ScheduleOwnerDomainManager
  }

  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}

  @room_a "room:Layout Hall 101"
  @room_b "room:Layout Hall 202"
  @professor "professor:Layout Prof One"

  # The test database is reset once for the whole suite, not per test, so every
  # layout gets a name no other test can collide with.
  defp unique(name), do: "#{name} #{System.unique_integer([:positive])}"

  setup do
    term_code = "202777#{System.unique_integer([:positive])}"
    insert_test_courses(term_code)
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)
    start_supervised!(ScheduleLayoutDomainManager)
    {:ok, term_code: term_code}
  end

  describe "saving" do
    test "a saved layout shows up in the Load Layout list under its scope",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)
      name = unique("Room sweep")

      select_schedule_owner(view, @room_a)
      wait_for_week_schedules(view)

      save_current_layout(view, name: name, scope: "user")

      assert has_element?(view, "#schedule-layouts-load")
      open_load_menu(view)
      html = render(view)
      assert html =~ name
      assert html =~ "My account"
    end

    test "a saved layout reads as saved, and the primary button has nothing left to do",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)

      select_schedule_owner(view, @room_a)
      wait_for_week_schedules(view)
      save_current_layout(view, name: unique("Nothing pending"), scope: "user")

      assert has_element?(view, "#schedule-layouts-current", "· saved")
      assert has_element?(view, "#schedule-layouts-save[disabled]", "Saved")
    end

    test "the save dialog opens on a locally generated name when the model can't suggest one",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)

      select_schedule_owner(view, @room_a)
      select_schedule_owner(view, @professor)
      wait_for_week_schedules(view)

      render_click(view, "schedule-layouts:primary_save", %{})

      # Completions are mocked in test and return no name, so the dialog keeps
      # the name built from what is on screen rather than blocking or blanking.
      assert has_element?(view, "#schedule-layout-form")
      assert render(view) =~ "1 person · 1 room"
    end
  end

  describe "loading" do
    test "an overlay group round-trips, with a group key minted fresh on load",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)

      select_schedule_owner(view, @room_a)
      select_schedule_owner(view, @room_b)
      wait_for_week_schedules(view)

      render_click(view, "schedule-details-order:overlay", %{
        "key" => @room_a,
        "target" => @room_b
      })

      assert [saved_group_key] = group_keys(render(view))

      name = unique("Grouped rooms")
      save_current_layout(view, name: name, scope: "user")
      render_click(view, "schedule-details-order:clear_selected", %{})
      assert group_keys(render(view)) == []

      load_layout(view, name)
      wait_for_week_schedules(view)

      assert [loaded_group_key] = group_keys(render(view))
      refute loaded_group_key == saved_group_key
      assert render(view) =~ "Layout Hall 101"
      assert render(view) =~ "Layout Hall 202"
    end

    test "owners the term doesn't have are dropped and reported, not loaded as empty cards",
         %{conn: conn, term_code: term_code} do
      {:ok, user} = User.find_or_create(test_email())

      name = unique("Half missing")

      {:ok, _layout} =
        ScheduleLayoutDb.create(
          name: name,
          scope: "user",
          user_id: user.id,
          term_code: term_code,
          entries: [
            %{"kind" => "owner", "key" => @room_a, "size" => %{"width" => nil, "scale" => 1.0}},
            %{
              "kind" => "owner",
              "key" => "professor:Nobody At All",
              "size" => %{"width" => nil, "scale" => 1.0}
            }
          ]
        )

      view = open_viewer(conn, term_code)
      load_layout(view, name)
      wait_for_week_schedules(view)

      assert has_element?(view, "#schedule-layouts-note", "Loaded 1 of 2 cards")
      assert has_element?(view, "#schedule-layouts-note", "Nobody At All")
      assert has_element?(view, "[data-schedule-key='#{@room_a}']")
      refute has_element?(view, "[data-schedule-key='professor:Nobody At All']")
    end
  end

  describe "editing a loaded layout" do
    test "an edit is shown, never prompted about, and the primary button offers the update",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)

      select_schedule_owner(view, @room_a)
      select_schedule_owner(view, @room_b)
      wait_for_week_schedules(view)
      save_current_layout(view, name: unique("Two rooms"), scope: "user")

      render_click(view, "schedule-details-order:close_schedule", %{"key" => @room_b})

      assert has_element?(view, "#schedule-layouts-current", "· edited")
      assert has_element?(view, "#schedule-layouts-save", "Update")
      # The edit itself never raises a dialog.
      refute has_element?(view, "#schedule-layout-form")

      render_click(view, "schedule-layouts:update_loaded", %{})
      wait_for_layouts(view)

      assert has_element?(view, "#schedule-layouts-current", "· saved")
    end

    test "switching layouts mid-edit just switches, and Undo puts the edits back",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)

      select_schedule_owner(view, @room_a)
      wait_for_week_schedules(view)
      room_a_only = unique("Just room A")
      save_current_layout(view, name: room_a_only, scope: "user")

      select_schedule_owner(view, @professor)
      wait_for_week_schedules(view)
      with_professor = unique("Room A and a professor")
      save_current_layout(view, name: with_professor, scope: "user")

      # Edit, then load the other layout without being asked anything.
      render_click(view, "schedule-details-order:close_schedule", %{"key" => @professor})
      assert has_element?(view, "#schedule-layouts-current", "· edited")

      load_layout(view, room_a_only)
      wait_for_week_schedules(view)

      refute has_element?(view, "#schedule-layout-form")
      assert has_element?(view, "#schedule-layouts-undo", "Replaced your unsaved layout")
      assert has_element?(view, "#schedule-layouts-current", room_a_only)

      render_click(view, "schedule-layouts:undo_load", %{})
      wait_for_week_schedules(view)

      assert has_element?(view, "#schedule-layouts-current", with_professor)
      assert has_element?(view, "#schedule-layouts-current", "· edited")
      refute has_element?(view, "#schedule-layouts-undo")
    end

    test "the Undo offer retires once you touch the layout that replaced your edits",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)

      select_schedule_owner(view, @room_a)
      wait_for_week_schedules(view)
      base = unique("Undo base")
      save_current_layout(view, name: base, scope: "user")

      select_schedule_owner(view, @professor)
      wait_for_week_schedules(view)
      save_current_layout(view, name: unique("Undo other"), scope: "user")

      render_click(view, "schedule-details-order:close_schedule", %{"key" => @professor})
      load_layout(view, base)
      wait_for_week_schedules(view)

      assert has_element?(view, "#schedule-layouts-undo")

      # Undoing now would discard this newer work with nothing left to undo it
      # with, so the offer goes away the moment the loaded layout is touched.
      select_schedule_owner(view, @room_b)
      wait_for_week_schedules(view)

      refute has_element?(view, "#schedule-layouts-undo")
    end
  end

  describe "the layout in the URL" do
    test "loading a layout puts its name in the URL so the page can be bookmarked",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)
      name = unique("Bookmark me")

      select_schedule_owner(view, @room_a)
      wait_for_week_schedules(view)
      save_current_layout(view, name: name, scope: "user")

      assert_patch(view, ~p"/scheduling?mode=viewer&term=#{term_code}&layout=#{name}")
    end

    test "a bookmarked URL opens straight into that layout",
         %{conn: conn, term_code: term_code} do
      {:ok, user} = User.find_or_create(test_email())
      name = unique("Deep link")

      {:ok, _layout} =
        ScheduleLayoutDb.create(
          name: name,
          scope: "user",
          user_id: user.id,
          term_code: term_code,
          entries: [
            %{"kind" => "owner", "key" => @room_a, "size" => %{"width" => nil, "scale" => 1.0}}
          ]
        )

      {:ok, view, _html} =
        live(
          log_in_test_user(conn),
          ~p"/scheduling?mode=viewer&term=#{term_code}&layout=#{name}"
        )

      wait_for_schedule_metadata(view)
      wait_for_layouts(view)
      sync_local_layouts(view)
      wait_for_week_schedules(view)

      assert has_element?(view, "#schedule-layouts-current", name)
      assert has_element?(view, "[data-schedule-key='#{@room_a}']")
    end

    test "a URL naming a layout that no longer exists says so instead of failing quietly",
         %{conn: conn, term_code: term_code} do
      {:ok, view, _html} =
        live(
          log_in_test_user(conn),
          ~p"/scheduling?mode=viewer&term=#{term_code}&layout=Renamed+Away"
        )

      wait_for_schedule_metadata(view)
      wait_for_layouts(view)
      sync_local_layouts(view)

      assert has_element?(view, "#schedule-layouts-note", "No saved layout called")
      refute has_element?(view, "#schedule-layouts-current")
    end

    test "a URL for the layout already on screen never discards edits in progress",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)
      name = unique("Keep my edits")

      select_schedule_owner(view, @room_a)
      select_schedule_owner(view, @room_b)
      wait_for_week_schedules(view)
      save_current_layout(view, name: name, scope: "user")

      render_click(view, "schedule-details-order:close_schedule", %{"key" => @room_b})
      assert has_element?(view, "#schedule-layouts-current", "· edited")

      # Re-navigating to the same layout (a mode switch patches the URL) must
      # leave the canvas alone rather than reloading over the edit.
      render_click(view, "switch_mode", %{"mode" => "viewer"})

      assert has_element?(view, "#schedule-layouts-current", "· edited")
      refute has_element?(view, "[data-schedule-key='#{@room_b}']")
    end
  end

  describe "shared layouts" do
    test "editing someone else's shared layout detaches it into an unsaved copy",
         %{conn: conn, term_code: term_code} do
      {:ok, author} = User.find_or_create("layout-author@example.com")
      name = unique("Dept overview")

      {:ok, _layout} =
        ScheduleLayoutDb.create(
          name: name,
          scope: "shared",
          user_id: author.id,
          term_code: term_code,
          entries: [
            %{"kind" => "owner", "key" => @room_a, "size" => %{"width" => nil, "scale" => 1.0}},
            %{"kind" => "owner", "key" => @room_b, "size" => %{"width" => nil, "scale" => 1.0}}
          ]
        )

      view = open_viewer(conn, term_code)
      load_layout(view, name)
      wait_for_week_schedules(view)

      # Someone else's shared layout: copying is the only offer, even untouched.
      assert has_element?(view, "#schedule-layouts-save", "Save as my copy")

      render_click(view, "schedule-details-order:close_schedule", %{"key" => @room_b})

      assert has_element?(view, "#schedule-layouts-current", "Copy of #{name}")
      assert has_element?(view, "#schedule-layouts-current", "· unsaved copy")
      assert has_element?(view, "#schedule-layouts-save", "Save as my copy")
    end

    test "the server refuses to update a shared layout the user does not own",
         %{term_code: term_code} do
      {:ok, author} = User.find_or_create("layout-author@example.com")
      {:ok, other} = User.find_or_create("layout-bystander@example.com")
      not_yours = unique("Not yours")

      {:ok, layout} =
        ScheduleLayoutDb.create(
          name: not_yours,
          scope: "shared",
          user_id: author.id,
          term_code: term_code,
          entries: []
        )

      refute ScheduleLayoutDomainManager.can_edit?(layout, other)
      assert ScheduleLayoutDomainManager.can_edit?(layout, author)

      ScheduleLayoutDomainManager.update_layout(
        pid: self(),
        user: other,
        layout_id: layout["id"],
        attrs: %{name: "Hijacked", scope: nil, entries: nil}
      )

      assert_receive {:schedule_layouts, {:layout_error, :not_allowed}}, 2_000

      {:ok, unchanged} = ScheduleLayoutDb.get(layout["id"])
      assert unchanged["name"] == not_yours
    end

    test "a super user may update a shared layout somebody else saved", %{term_code: term_code} do
      {:ok, author} = User.find_or_create("layout-author@example.com")
      {:ok, admin} = admin_user()

      {:ok, layout} =
        ScheduleLayoutDb.create(
          name: unique("Shared by author"),
          scope: "shared",
          user_id: author.id,
          term_code: term_code,
          entries: []
        )

      assert ScheduleLayoutDomainManager.can_edit?(layout, admin)
      tidied = unique("Tidied up")

      ScheduleLayoutDomainManager.update_layout(
        pid: self(),
        user: admin,
        layout_id: layout["id"],
        attrs: %{name: tidied, scope: nil, entries: nil}
      )

      assert_receive {:schedule_layouts, {:layout_saved, saved}}, 2_000
      assert saved["name"] == tidied
    end
  end

  describe "name collisions" do
    test "saving over an existing name asks to replace or copy instead of guessing",
         %{conn: conn, term_code: term_code} do
      view = open_viewer(conn, term_code)

      name = unique("Same name")

      select_schedule_owner(view, @room_a)
      wait_for_week_schedules(view)
      save_current_layout(view, name: name, scope: "user")

      select_schedule_owner(view, @room_b)
      wait_for_week_schedules(view)

      render_click(view, "schedule-layouts:open_save_dialog", %{"mode" => "new"})
      submit_dialog(view, name: name, scope: "user")

      assert render(view) =~ "is already saved there"
      assert has_element?(view, "#schedule-layout-form input[name='collision'][value='replace']")

      # Choosing a copy keeps both, under distinct names.
      view
      |> form("#schedule-layout-form", %{"collision" => "copy"})
      |> render_change()

      submit_dialog(view, name: name, scope: "user")
      wait_for_layouts(view)

      open_load_menu(view)
      html = render(view)
      assert html =~ name
      assert html =~ "#{name} (2)"
    end
  end

  # -- Helpers ---------------------------------------------------------------

  defp open_viewer(conn, term_code) do
    {:ok, view, _html} =
      live(log_in_test_user(conn), ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)
    wait_for_layouts(view)
    sync_local_layouts(view)
    view
  end

  defp save_current_layout(view, name: name, scope: scope) do
    render_click(view, "schedule-layouts:open_save_dialog", %{"mode" => "new"})
    submit_dialog(view, name: name, scope: scope)
    wait_for_layouts(view)
  end

  defp submit_dialog(view, name: name, scope: scope) do
    view
    |> form("#schedule-layout-form", %{"name" => name, "scope" => scope})
    |> render_submit()
  end

  defp open_load_menu(view) do
    view |> element("#schedule-layouts-load") |> render_click()
  end

  defp load_layout(view, name) do
    open_load_menu(view)

    view
    |> element("#schedule-layouts-load ~ div button", name)
    |> render_click()
  end

  defp group_keys(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("[data-schedule-key^='overlay:']")
    |> LazyHTML.attribute("data-schedule-key")
  end

  defp select_schedule_owner(view, owner_key) do
    query = owner_key |> String.split(":", parts: 2) |> List.last()
    view |> form("#scheduling-search-form") |> render_change(%{"query" => query})

    view
    |> element("button[phx-click='schedule-owner-search:select'][phx-value-key='#{owner_key}']")
    |> render_click()
  end

  defp wait_for_schedule_metadata(view) do
    :ok = ScheduleOwnerDomainManager.await_idle()
    render(view)
  end

  defp wait_for_week_schedules(view) do
    :ok = ScheduleOwnerDomainManager.await_idle()
    render(view)
    :ok = ScheduleOwnerDomainManager.await_idle()
    render(view)
  end

  # The colocated hook reports browser-local layouts in a real session; tests
  # push the same event so the URL resolver knows that source has reported.
  defp sync_local_layouts(view) do
    render_hook(view, "schedule-layouts:local_synced", %{"layouts" => []})
  end

  defp wait_for_layouts(view) do
    _ = :sys.get_state(ScheduleLayoutDomainManager)
    render(view)
  end

  defp test_email, do: "schedule-layouts-live@example.com"

  defp log_in_test_user(conn), do: log_in_user(conn, test_email(), ["scheduling_admin"])

  defp admin_user do
    alias SnowSeTools.Data.AccessControl

    {:ok, user} = User.find_or_create("layout-admin@example.com")
    {:ok, groups} = AccessControl.list_groups()
    group = Enum.find(groups, &(&1.name == "admin"))
    :ok = AccessControl.add_user_group(user_id: user.id, group_id: group.id)
    User.get_by_id(user.id)
  end

  defp insert_test_courses(term_code) do
    SnowCourseCacheDb.save_courses(
      term_code: term_code,
      term_name: "Layout Test Term",
      courses: [
        course("81001", "Circuits", "Layout Prof One", "101", ["Monday"], "09:00:00", "09:50:00"),
        course("81002", "Networks", "Layout Prof Two", "202", ["Monday"], "09:30:00", "10:20:00")
      ]
    )
  end

  defp course(crn, name, professor, room, days, start_time, end_time) do
    %{
      "crn" => crn,
      "subject_code" => "TEST",
      "course_number" => crn,
      "section_number" => "01",
      "name" => name,
      "credit_hours" => 3,
      "instructors" => [%{"name" => professor, "primary_instructor" => true}],
      "meet_info" => [
        %{
          "building" => "Layout Hall",
          "building_code" => "LYH",
          "room" => room,
          "days" => days,
          "start_time" => start_time,
          "end_time" => end_time
        }
      ]
    }
  end
end
