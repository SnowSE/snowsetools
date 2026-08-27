defmodule SnowSeToolsWeb.Scheduling.ScheduleOverlayLiveTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.User
  alias SnowSeTools.Scheduling.{ScheduleChangeDomainManager, ScheduleOwnerDomainManager}
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}

  @room_a "room:Overlay Hall 101"
  @room_b "room:Overlay Hall 202"
  @room_c "room:Overlay Hall 303"
  @room_d "room:Overlay Hall 404"
  @professor "professor:Overlay Prof One"

  setup do
    term_code = "202888#{System.unique_integer([:positive])}"
    insert_test_courses(term_code)
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)
    {:ok, term_code: term_code}
  end

  test "overlay button appears only once a second card of the same kind is shown",
       %{conn: conn, term_code: term_code} do
    {:ok, view, _html} =
      live(log_in_test_user(conn), ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)

    select_schedule_owner(view, @room_a)
    wait_for_week_schedules(view)
    refute has_element?(view, "[id=\'overlay-menu-#{@room_a}\']")

    select_schedule_owner(view, @professor)
    wait_for_week_schedules(view)
    # a room and a person are different kinds: still nothing on either card
    refute has_element?(view, "[id=\'overlay-menu-#{@room_a}\']")
    refute has_element?(view, "[id=\'overlay-menu-#{@professor}\']")

    select_schedule_owner(view, @room_b)
    wait_for_week_schedules(view)
    assert has_element?(view, "[id=\'overlay-menu-#{@room_a}-button\']")
    assert has_element?(view, "[id=\'overlay-menu-#{@room_b}-button\']")
    refute has_element?(view, "[id=\'overlay-menu-#{@professor}\']")

    # the menu lists only the other room, never the professor
    view |> element("[id=\'overlay-menu-#{@room_a}-button\']") |> render_click()
    assert has_element?(view, "[id=\'overlay-menu-#{@room_a}-list\']", "Overlay Hall 202")
    refute has_element?(view, "[id=\'overlay-menu-#{@room_a}-list\']", "Overlay Prof One")
  end

  test "overlaying two rooms merges them into one colored group card and back",
       %{conn: conn, term_code: term_code} do
    {:ok, view, _html} =
      live(log_in_test_user(conn), ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)

    select_schedule_owner(view, @room_a)
    select_schedule_owner(view, @room_b)
    wait_for_week_schedules(view)

    view |> element("[id=\'overlay-menu-#{@room_a}-button\']") |> render_click()

    view
    |> element("[id=\'overlay-menu-#{@room_a}-list\'] button[phx-value-target='#{@room_b}']")
    |> render_click()

    html = render(view)
    assert [group_key] = group_keys(html)
    refute has_element?(view, "[data-schedule-key='#{@room_a}']")
    refute has_element?(view, "[data-schedule-key='#{@room_b}']")
    assert has_element?(view, "[data-schedule-key='#{group_key}']", "Overlay · 2 rooms")

    assert has_element?(
             view,
             "[data-schedule-key='#{group_key}'] [data-week-schedule-course][data-owner-key='#{@room_a}'].ring-sky-400\\/60"
           )

    assert has_element?(
             view,
             "[data-schedule-key='#{group_key}'] [data-week-schedule-course][data-owner-key='#{@room_b}'].ring-violet-400\\/60"
           )

    # the search still shows both rooms as selected
    view |> form("#scheduling-search-form") |> render_change(%{"query" => "Overlay Hall"})
    assert has_element?(view, "[id='schedule-owner-search-room-Overlay Hall 101'] .hero-check")
    assert has_element?(view, "[id='schedule-owner-search-room-Overlay Hall 202'] .hero-check")

    # popping a member out of a two-member group dissolves it into two solo cards
    view
    |> element(
      "[data-schedule-key='#{group_key}'] button[phx-click='schedule-details-order:pop_out'][phx-value-key='#{@room_b}']"
    )
    |> render_click()

    assert group_keys(render(view)) == []
    assert has_element?(view, "[data-schedule-key='#{@room_a}']")
    assert has_element?(view, "[data-schedule-key='#{@room_b}']")
  end

  test "separate and close work on a group", %{conn: conn, term_code: term_code} do
    {:ok, view, _html} =
      live(log_in_test_user(conn), ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)

    select_schedule_owner(view, @room_a)
    select_schedule_owner(view, @room_b)
    wait_for_week_schedules(view)
    render_click(view, "schedule-details-order:overlay", %{"key" => @room_b, "target" => @room_a})
    assert [group_key] = group_keys(render(view))

    view |> element("[id='overlay-separate-#{group_key}']") |> render_click()
    assert group_keys(render(view)) == []
    assert has_element?(view, "[data-schedule-key='#{@room_a}']")
    assert has_element?(view, "[data-schedule-key='#{@room_b}']")

    render_click(view, "schedule-details-order:overlay", %{"key" => @room_b, "target" => @room_a})
    assert [group_key] = group_keys(render(view))
    render_click(view, "schedule-details-order:close_schedule", %{"key" => group_key})
    assert has_element?(view, "#scheduling-empty-selection")
  end

  test "overlaying a group onto another group merges their members", %{
    conn: conn,
    term_code: term_code
  } do
    {:ok, view, _html} =
      live(log_in_test_user(conn), ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)

    for key <- [@room_a, @room_b, @room_c, @room_d], do: select_schedule_owner(view, key)
    wait_for_week_schedules(view)

    render_click(view, "schedule-details-order:overlay", %{"key" => @room_a, "target" => @room_b})
    render_click(view, "schedule-details-order:overlay", %{"key" => @room_c, "target" => @room_d})
    assert [group_ab, group_cd] = group_keys(render(view))

    render_click(view, "schedule-details-order:overlay", %{
      "key" => group_ab,
      "target" => group_cd
    })

    html = render(view)
    assert group_keys(html) == [group_cd]
    assert has_element?(view, "[data-schedule-key='#{group_cd}']", "Overlay · 4 rooms")

    for key <- [@room_a, @room_b, @room_c, @room_d] do
      assert has_element?(
               view,
               "[data-schedule-key='#{group_cd}'] [data-week-schedule-course][data-owner-key='#{key}']"
             )
    end

    # and a group onto a solo card flattens the same way
    render_click(view, "schedule-details-order:separate_all", %{"group" => group_cd})
    render_click(view, "schedule-details-order:overlay", %{"key" => @room_a, "target" => @room_b})
    assert [group] = group_keys(render(view))
    render_click(view, "schedule-details-order:overlay", %{"key" => group, "target" => @room_c})
    assert [merged] = group_keys(render(view))
    assert has_element?(view, "[data-schedule-key='#{merged}']", "Overlay · 3 rooms")
    refute render(view) =~ "overlay:#{String.replace(group, "overlay:", "")}\""
  end

  test "arrow keys and Enter pick a search result and clear the box", %{
    conn: conn,
    term_code: term_code
  } do
    {:ok, view, _html} =
      live(log_in_test_user(conn), ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)

    view |> form("#scheduling-search-form") |> render_change(%{"query" => "Overlay Hall"})
    # first result is highlighted by default
    assert has_element?(
             view,
             "[id='schedule-owner-search-room-Overlay Hall 101'][data-highlighted='true']"
           )

    render_hook(view, "schedule-viewer:search_key", %{"key" => "ArrowDown"})

    assert has_element?(
             view,
             "[id='schedule-owner-search-room-Overlay Hall 202'][data-highlighted='true']"
           )

    refute has_element?(
             view,
             "[id='schedule-owner-search-room-Overlay Hall 101'][data-highlighted='true']"
           )

    render_hook(view, "schedule-viewer:search_key", %{"key" => "ArrowUp"})
    render_hook(view, "schedule-viewer:search_key", %{"key" => "ArrowUp"})

    assert has_element?(
             view,
             "[id='schedule-owner-search-room-Overlay Hall 101'][data-highlighted='true']"
           )

    render_hook(view, "schedule-viewer:search_key", %{"key" => "ArrowDown"})
    render_hook(view, "schedule-viewer:search_key", %{"key" => "Enter"})
    wait_for_week_schedules(view)

    assert has_element?(view, "[data-schedule-key='#{@room_b}']")
    refute has_element?(view, "[data-schedule-key='#{@room_a}']")
    assert has_element?(view, "#scheduling-search-input[value='']")
    refute has_element?(view, "#schedule-owner-search-results")
  end

  test "cards can be resized, maximized and restored", %{conn: conn, term_code: term_code} do
    {:ok, view, _html} =
      live(log_in_test_user(conn), ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)
    select_schedule_owner(view, @room_a)
    wait_for_week_schedules(view)

    card = "[data-schedule-key='#{@room_a}']"
    assert has_element?(view, "#{card}.w-\\[700px\\]")
    assert has_element?(view, "#{card} [data-resize-grip].cursor-nwse-resize")
    assert has_element?(view, "#{card} [data-minute-scale='1.0']")

    render_click(view, "schedule-details-order:resize", %{
      "key" => @room_a,
      "width" => 900,
      "scale" => 1.5
    })

    assert has_element?(view, "#{card}[style='width: 900px']")
    assert has_element?(view, "#{card} [data-minute-scale='1.5']")

    # width below the minimum and scale above the maximum are clamped
    render_click(view, "schedule-details-order:resize", %{
      "key" => @room_a,
      "width" => 100,
      "scale" => 9
    })

    assert has_element?(view, "#{card}[style='width: 480px']")
    assert has_element?(view, "#{card} [data-minute-scale='3.0']")

    render_click(view, "schedule-details-order:maximize", %{"key" => @room_a})
    assert has_element?(view, "#{card}.w-full")

    view
    |> element("#{card} button[phx-click='schedule-details-order:restore_size']")
    |> render_click()

    assert has_element?(view, "#{card}.w-\\[700px\\]")
    assert has_element?(view, "#{card} [data-minute-scale='1.0']")
  end

  test "the sidebar can be unpinned to an auto-hide rail", %{conn: conn, term_code: term_code} do
    {:ok, view, _html} =
      live(log_in_test_user(conn), ~p"/scheduling?mode=viewer&term=#{term_code}")

    assert has_element?(view, "#scheduling-sidebar[data-pinned='true']")
    refute has_element?(view, "#scheduling-sidebar-rail")

    view |> element("#scheduling-sidebar-pin-true") |> render_click()
    assert has_element?(view, "#scheduling-sidebar[data-pinned='false']")
    assert has_element?(view, "#scheduling-sidebar-rail")
    assert has_element?(view, "#scheduling-sidebar-flyout #scheduling-search-input")

    render_hook(view, "schedule-viewer:set_sidebar_pinned", %{"pinned" => true})
    assert has_element?(view, "#scheduling-sidebar[data-pinned='true']")
    refute has_element?(view, "#scheduling-sidebar-rail")
  end

  test "overlay across kinds is refused", %{conn: conn, term_code: term_code} do
    {:ok, view, _html} =
      live(log_in_test_user(conn), ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)

    select_schedule_owner(view, @room_a)
    select_schedule_owner(view, @professor)
    wait_for_week_schedules(view)

    render_click(view, "schedule-details-order:overlay", %{
      "key" => @room_a,
      "target" => @professor
    })

    assert group_keys(render(view)) == []
    assert has_element?(view, "[data-schedule-key='#{@room_a}']")
    assert has_element?(view, "[data-schedule-key='#{@professor}']")
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
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)
  end

  defp wait_for_week_schedules(view) do
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)
  end

  defp log_in_test_user(conn) do
    {:ok, user} = User.find_or_create("schedule-overlay-live@example.com")
    user_id = Map.get(user, :id) || Map.fetch!(user, "id")
    Plug.Test.init_test_session(conn, %{"current_user_id" => user_id})
  end

  defp insert_test_courses(term_code) do
    SnowCourseCacheDb.save_courses(
      term_code: term_code,
      term_name: "Overlay Test Term",
      courses: [
        course(
          "80001",
          "Circuits",
          "Overlay Prof One",
          "101",
          ["Monday"],
          "09:00:00",
          "09:50:00"
        ),
        course(
          "80002",
          "Networks",
          "Overlay Prof Two",
          "202",
          ["Monday"],
          "09:30:00",
          "10:20:00"
        ),
        course(
          "80003",
          "Databases",
          "Overlay Prof Three",
          "303",
          ["Tuesday"],
          "09:00:00",
          "09:50:00"
        ),
        course(
          "80004",
          "Compilers",
          "Overlay Prof Four",
          "404",
          ["Wednesday"],
          "09:00:00",
          "09:50:00"
        )
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
          "building" => "Overlay Hall",
          "building_code" => "OVH",
          "room" => room,
          "days" => days,
          "start_time" => start_time,
          "end_time" => end_time
        }
      ]
    }
  end
end
