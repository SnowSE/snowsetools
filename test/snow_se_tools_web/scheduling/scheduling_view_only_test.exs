defmodule SnowSeToolsWeb.Scheduling.SchedulingViewOnlyTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.User

  alias SnowSeTools.Scheduling.{
    ScheduleChangeDomainManager,
    ScheduleOwnerDomainManager
  }

  alias SnowSeTools.AcademicPrograms.ProgramDomainManager
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}
  alias SnowSeToolsWeb.Scheduling.SchedulingAccess

  @course_name "View Only Networking"
  @course_crn "80001"
  @room "View Hall 101"
  @professor "Professor Viewer"
  @denied "You have view-only access to scheduling."

  setup do
    # The first row in users is granted admin when access control bootstraps,
    # so make sure that is never the view-only account these tests rely on.
    {:ok, _bootstrap} = User.find_or_create("scheduling-view-bootstrap@example.com")

    term_code = "202888#{System.unique_integer([:positive])}"
    insert_test_courses(term_code)

    start_supervised!(ProgramDomainManager)
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)

    {:ok, term_code: term_code}
  end

  describe "classify/1" do
    test "reading the schedule is allowed and changing it is not" do
      assert SchedulingAccess.classify("schedule-owner-search:select") == :view
      assert SchedulingAccess.classify("schedule-viewer:set_term") == :view
      assert SchedulingAccess.classify("schedule-details-order:close_schedule") == :view
      assert SchedulingAccess.classify("schedule-layouts:save") == :view
      assert SchedulingAccess.classify("academic-programs:select") == :view
      assert SchedulingAccess.classify("week-schedule-grid:close_edit_course") == :view
      assert SchedulingAccess.classify("switch_mode") == :view

      assert SchedulingAccess.classify("week-schedule-grid:move_course") == :edit
      assert SchedulingAccess.classify("week-schedule-grid:save_edit_course") == :edit
      assert SchedulingAccess.classify("week-schedule-grid:delete_course") == :edit
      assert SchedulingAccess.classify("schedule-change-groups:new_group") == :edit
      assert SchedulingAccess.classify("academic-programs-editor:save") == :edit
    end

    test "an event nobody has classified is refused rather than allowed" do
      assert SchedulingAccess.classify("schedule-teleporter:launch") == :unknown
      assert SchedulingAccess.classify("wat") == :unknown
    end

    test "every namespace is classified exactly once" do
      overlap =
        MapSet.intersection(
          MapSet.new(SchedulingAccess.view_namespaces()),
          MapSet.new(SchedulingAccess.editor_namespaces())
        )

      assert MapSet.size(overlap) == 0
    end
  end

  describe "a view-only user" do
    test "reads the schedule without change groups or drag handles", %{
      conn: conn,
      term_code: term_code
    } do
      view = live_scheduling(conn, viewer_conn(conn), term_code)

      select_schedule_owner(view, "room:#{@room}")
      wait_for_week_schedules(view)

      assert has_element?(view, course_card_selector("room:#{@room}", @course_crn))
      assert render(view) =~ @course_name

      refute has_element?(view, "#schedule-change-groups")
      assert has_element?(view, "[data-week-schedule-course][draggable='false']")
      refute has_element?(view, "[data-week-schedule-course][draggable='true']")
      assert has_element?(view, "[data-editor='false']")
    end

    test "cannot move a course, and the schedule is unchanged", %{
      conn: conn,
      term_code: term_code
    } do
      view = live_scheduling(conn, viewer_conn(conn), term_code)

      select_schedule_owner(view, "room:#{@room}")
      wait_for_week_schedules(view)

      render_hook(view, "week-schedule-grid:move_course", move_payload(term_code))

      assert render(view) =~ @denied
      assert has_element?(view, course_card_selector("room:#{@room}", @course_crn))
      refute has_element?(view, "#schedule-change-groups")
    end

    test "cannot create a change group or edit a program", %{conn: conn, term_code: term_code} do
      view = live_scheduling(conn, viewer_conn(conn), term_code)

      render_hook(view, "schedule-change-groups:new_group", %{})
      assert render(view) =~ @denied

      render_hook(view, "academic-programs-editor:save", %{})
      assert render(view) =~ @denied
    end

    test "sees the programs list without the buttons that change it", %{
      conn: conn,
      term_code: term_code
    } do
      {:ok, view, _html} =
        live(viewer_conn(conn), ~p"/scheduling?mode=programs&term=#{term_code}")

      _ = :sys.get_state(ProgramDomainManager)
      render(view)

      refute has_element?(view, "#new-program-from-list")
      refute has_element?(view, "#edit-academic-program")
    end

    test "can save a personal layout but is not offered the shared scope", %{
      conn: conn,
      term_code: term_code
    } do
      view = live_scheduling(conn, viewer_conn(conn), term_code)

      select_schedule_owner(view, "room:#{@room}")
      wait_for_week_schedules(view)

      view |> element("#schedule-layouts-save") |> render_click()

      assert has_element?(view, "#schedule-layout-form input[name='scope'][value='user']")
      refute has_element?(view, "#schedule-layout-form input[name='scope'][value='shared']")

      render_hook(view, "schedule-layouts:save", %{"name" => "Viewer Layout", "scope" => "shared"})

      assert render(view) =~ "Only schedule editors can share a layout with everyone."
    end

    test "can still search, select and arrange schedules", %{conn: conn, term_code: term_code} do
      view = live_scheduling(conn, viewer_conn(conn), term_code)

      select_schedule_owner(view, "room:#{@room}")
      wait_for_week_schedules(view)
      assert has_element?(view, "[data-schedule-key='room:#{@room}']")

      view
      |> element("button[phx-click='schedule-details-order:close_schedule']")
      |> render_click()

      refute render(view) =~ @denied
      refute has_element?(view, "[data-schedule-key='room:#{@room}']")
    end
  end

  describe "an editor" do
    test "still gets change groups and drag handles", %{conn: conn, term_code: term_code} do
      view = live_scheduling(conn, editor_conn(conn), term_code)

      select_schedule_owner(view, "room:#{@room}")
      wait_for_week_schedules(view)

      assert has_element?(view, "#schedule-change-groups")
      assert has_element?(view, "[data-week-schedule-course][draggable='true']")
      assert has_element?(view, "[data-editor='true']")
      refute render(view) =~ @denied
    end
  end

  defp viewer_conn(conn),
    do: log_in_user(conn, "scheduling-viewer@example.com", ["scheduling_view"])

  defp editor_conn(conn),
    do: log_in_user(conn, "scheduling-editor@example.com", ["scheduling_admin"])

  defp live_scheduling(_conn, logged_in_conn, term_code) do
    {:ok, view, _html} = live(logged_in_conn, ~p"/scheduling?mode=viewer&term=#{term_code}")

    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)

    view
  end

  defp select_schedule_owner(view, owner_key) do
    search_query = owner_key |> String.split(":", parts: 2) |> List.last()

    view
    |> form("#scheduling-search-form")
    |> render_change(%{"query" => search_query})

    view
    |> element("button[phx-click='schedule-owner-search:select'][phx-value-key='#{owner_key}']")
    |> render_click()
  end

  defp wait_for_week_schedules(view) do
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)
  end

  defp course_card_selector(owner_key, crn) do
    "[data-schedule-key='#{owner_key}'] [data-week-schedule-course][data-course-payload*='\"crn\":\"#{crn}\"']"
  end

  defp move_payload(term_code) do
    meeting = %{
      "building" => "View Hall",
      "building_code" => "VWH",
      "days" => ["Monday"],
      "end_time" => "09:50:00",
      "room" => "101",
      "start_time" => "09:00:00"
    }

    %{
      "course_name" => @course_name,
      "course_number" => "1130",
      "credit_hours" => 2,
      "crn" => @course_crn,
      "end_time" => "09:50:00",
      "instructors" => [@professor],
      "meet_info" => [meeting],
      "meeting" => meeting,
      "owner_key" => "room:#{@room}",
      "owner_name" => @room,
      "owner_type" => "room",
      "start_time" => "09:00:00",
      "subject_code" => "TEST",
      "target_day" => "Wednesday",
      "target_time" => "13:00",
      "term" => term_code
    }
  end

  defp insert_test_courses(term_code) do
    SnowCourseCacheDb.save_courses(
      term_code: term_code,
      term_name: "View Only Test Term",
      courses: [
        %{
          "crn" => @course_crn,
          "subject_code" => "TEST",
          "course_number" => "1130",
          "section_number" => "01",
          "name" => @course_name,
          "credit_hours" => 2,
          "instructors" => [%{"name" => @professor, "primary_instructor" => true}],
          "meet_info" => [
            %{
              "building" => "View Hall",
              "building_code" => "VWH",
              "days" => ["Monday"],
              "end_time" => "09:50:00",
              "room" => "101",
              "start_time" => "09:00:00"
            }
          ]
        }
      ]
    )
  end
end
