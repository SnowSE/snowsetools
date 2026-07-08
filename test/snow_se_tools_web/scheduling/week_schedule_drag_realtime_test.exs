defmodule SnowSeToolsWeb.Scheduling.WeekScheduleDragRealtimeTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.AcademicPrograms.{
    CourseAttrs,
    ProgramAttrs,
    ProgramDb,
    ProgramDomainManager,
    SemesterAttrs
  }

  alias SnowSeTools.Data.User

  alias SnowSeTools.Scheduling.{
    ScheduleChangeDb,
    ScheduleChangeDomainManager,
    ScheduleOwnerDomainManager
  }

  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}

  @course_name "Networking Concepts"
  @course_crn "70001"
  @source_room "Source Building 101"
  @target_room "Target Building 202"
  @conflict_course_name "Target Room Conflict"

  setup do
    delete_realtime_test_groups()

    program = insert_test_program()
    term_code = "202777#{System.unique_integer([:positive])}"

    insert_test_courses(term_code)
    start_supervised!(ProgramDomainManager)
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)

    on_exit(fn ->
      delete_realtime_test_groups()
      delete_test_program(program["id"])
    end)

    semester = List.first(program["semesters"])

    {:ok,
     term_code: term_code,
     academic_program_owner_key: "academic_program_semester:#{program["id"]}:#{semester["id"]}",
     academic_program_name: "#{program["name"]} Freshman first semester"}
  end

  test "dragging a course to another selected schedule updates both views in the active change group",
       %{conn: conn, term_code: term_code} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)
    create_change_group(view)
    select_schedule_owner(view, "room:#{@source_room}")
    select_schedule_owner(view, "room:#{@target_room}")
    wait_for_week_schedules(view)

    refute has_element?(
             view,
             course_card_selector("room:#{@target_room}", @course_crn)
           )

    render_hook(view, "week-schedule-grid:move_course", move_payload(term_code))
    wait_for_change_group_refresh(view)

    refute has_element?(
             view,
             course_card_selector("room:#{@source_room}", @course_crn)
           )

    assert has_element?(
             view,
             course_card_selector("room:#{@target_room}", @course_crn)
           )
  end

  test "dragging a course to a new time in a new building removes the old source-room card",
       %{conn: conn, term_code: term_code} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)
    create_change_group(view)
    select_schedule_owner(view, "room:#{@source_room}")
    select_schedule_owner(view, "room:#{@target_room}")
    wait_for_week_schedules(view)

    render_hook(view, "week-schedule-grid:move_course", move_payload(term_code))
    wait_for_change_group_refresh(view)

    refute has_element?(
             view,
             course_card_selector("room:#{@source_room}", @course_crn)
           )

    assert has_element?(
             view,
             course_card_selector("room:#{@target_room}", @course_crn)
           )

    assert has_element?(
             view,
             course_card_selector("room:#{@target_room}", @course_crn)
           )
  end

  test "dragging a changed course back to its original time and room removes the change",
       %{conn: conn, term_code: term_code} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)
    create_change_group(view)
    select_schedule_owner(view, "room:#{@source_room}")
    select_schedule_owner(view, "room:#{@target_room}")
    wait_for_week_schedules(view)

    render_hook(view, "week-schedule-grid:move_course", move_payload(term_code))
    wait_for_change_group_refresh(view)

    assert has_element?(view, "#schedule-change-groups", @course_name)
    refute has_element?(view, course_card_selector("room:#{@source_room}", @course_crn))
    assert has_element?(view, course_card_selector("room:#{@target_room}", @course_crn))

    render_hook(view, "week-schedule-grid:move_course", move_back_payload(term_code))
    wait_for_change_group_refresh(view)
    wait_for_week_schedules(view)

    refute has_element?(view, "#schedule-change-groups", @course_name)
    assert has_element?(view, course_card_selector("room:#{@source_room}", @course_crn))
    refute has_element?(view, course_card_selector("room:#{@target_room}", @course_crn))
  end

  test "change list can open related room schedule from the active change group",
       %{
         conn: conn,
         term_code: term_code,
         academic_program_owner_key: academic_program_owner_key
       } do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)
    wait_for_academic_programs(view)
    create_change_group(view)
    select_schedule_owner(view, "room:#{@source_room}")
    wait_for_week_schedules(view)

    render_hook(view, "week-schedule-grid:move_course", move_payload(term_code))
    wait_for_change_group_refresh(view)

    assert has_element?(view, "#schedule-change-groups", @course_name)

    change_id = active_change_id(view)

    assert has_element?(
             view,
             "#schedule-change-#{change_id} button[phx-value-key='room:#{@target_room}']",
             @target_room
           )

    assert has_element?(
             view,
             "#schedule-change-#{change_id} button[phx-value-key='#{academic_program_owner_key}']",
             "Freshman first semester"
           )

    assert has_element?(
             view,
             "#schedule-change-#{change_id} button[phx-value-key='professor:Professor Example']",
             "Professor: Professor Example"
           )

    view
    |> element("#schedule-change-#{change_id} button[phx-value-key='room:#{@target_room}']")
    |> render_click()

    wait_for_week_schedules(view)

    assert has_element?(
             view,
             "[data-schedule-key='room:#{@target_room}'] [data-week-schedule-course]",
             @course_name
           )

    view
    |> element(
      "#schedule-change-#{change_id} button[phx-value-key='#{academic_program_owner_key}']"
    )
    |> render_click()

    wait_for_week_schedules(view)

    assert has_element?(
             view,
             "[data-schedule-key='#{academic_program_owner_key}'] [data-week-schedule-course]",
             @course_name
           )

    view
    |> element(
      "#schedule-change-#{change_id} button[phx-value-key='professor:Professor Example']"
    )
    |> render_click()

    wait_for_week_schedules(view)

    assert has_element?(
             view,
             "[data-schedule-key='professor:Professor Example'] [data-week-schedule-course]",
             @course_name
           )
  end

  test "change card can delete a change",
       %{conn: conn, term_code: term_code} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)
    create_change_group(view)
    select_schedule_owner(view, "room:#{@source_room}")
    wait_for_week_schedules(view)

    render_hook(view, "week-schedule-grid:move_course", move_payload(term_code))
    wait_for_change_group_refresh(view)

    change_id = active_change_id(view)

    view
    |> element(
      "#schedule-change-#{change_id} button[phx-click='schedule-change-groups:delete_change']"
    )
    |> render_click()

    wait_for_change_group_refresh(view)

    refute has_element?(view, "#schedule-change-groups", @course_name)
  end

  test "change card shows only changed fields and describes room conflicts without selecting the target room",
       %{conn: conn, term_code: term_code} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")

    wait_for_schedule_metadata(view)
    create_change_group(view)
    select_schedule_owner(view, "room:#{@source_room}")
    wait_for_week_schedules(view)

    render_hook(view, "week-schedule-grid:move_course", move_payload(term_code))
    wait_for_change_group_refresh(view)

    change_id = active_change_id(view)
    change_selector = "#schedule-change-#{change_id}"

    assert has_element?(view, change_selector, "Time changed to 10:30-11:20")
    assert has_element?(view, change_selector, "Room changed to #{@target_room}")
    assert has_element?(view, "#{change_selector} button[phx-value-key='room:#{@target_room}']")
    assert has_element?(view, change_selector, @conflict_course_name)
    refute has_element?(view, change_selector, "Professor changed")
  end

  defp create_change_group(view) do
    view
    |> element("button[phx-click='schedule-change-groups:new_group']")
    |> render_click()

    view
    |> form("form[phx-submit='schedule-change-groups:save_new']", %{"name" => "Realtime Test"})
    |> render_submit()

    _ = :sys.get_state(ScheduleChangeDomainManager)
    render(view)
  end

  defp select_schedule_owner(view, owner_key) do
    search_query =
      owner_key
      |> String.split(":", parts: 2)
      |> List.last()

    view
    |> form("#scheduling-search-form")
    |> render_change(%{"query" => search_query})

    view
    |> element("button[phx-click='schedule-owner-search:select'][phx-value-key='#{owner_key}']")
    |> render_click()
  end

  defp wait_for_schedule_metadata(view) do
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)
  end

  defp wait_for_academic_programs(view) do
    _ = :sys.get_state(ProgramDomainManager)
    _ = :sys.get_state(view.pid)
    render(view)
  end

  defp wait_for_week_schedules(view) do
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    render(view)
  end

  defp wait_for_change_group_refresh(view) do
    _ = :sys.get_state(ScheduleChangeDomainManager)
    render(view)
    _ = :sys.get_state(ScheduleChangeDomainManager)
    render(view)
  end

  defp active_change_id(view) do
    state = :sys.get_state(view.pid)

    state.socket.assigns.schedule_change_groups_state.active_change_group
    |> Map.fetch!("changes")
    |> List.first()
    |> Map.fetch!("id")
  end

  defp move_payload(term_code) do
    meeting = %{
      "building" => "Source Building",
      "building_code" => "SRC",
      "days" => ["Monday", "Wednesday"],
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
      "instructors" => ["Professor Example"],
      "meet_info" => [meeting],
      "meeting" => meeting,
      "owner_key" => "room:#{@target_room}",
      "owner_name" => @target_room,
      "owner_type" => "room",
      "start_time" => "09:00:00",
      "subject_code" => "TEST",
      "target_day" => "Wednesday",
      "target_time" => "10:30",
      "term" => term_code
    }
  end

  defp move_back_payload(term_code) do
    meeting = %{
      "building" => "Target Building",
      "building_code" => "TGT",
      "days" => ["Monday", "Wednesday"],
      "end_time" => "11:20",
      "room" => "202",
      "start_time" => "10:30"
    }

    %{
      "course_name" => @course_name,
      "course_number" => "1130",
      "credit_hours" => 2,
      "crn" => @course_crn,
      "end_time" => "11:20",
      "instructors" => ["Professor Example"],
      "meet_info" => [meeting],
      "meeting" => meeting,
      "owner_key" => "room:#{@source_room}",
      "owner_name" => @source_room,
      "owner_type" => "room",
      "start_time" => "10:30",
      "subject_code" => "TEST",
      "target_day" => "Wednesday",
      "target_time" => "09:00",
      "term" => term_code
    }
  end

  defp log_in_test_user(conn) do
    {:ok, user} = User.find_or_create("week-schedule-drag-realtime@example.com")
    user_id = Map.get(user, :id) || Map.fetch!(user, "id")

    Plug.Test.init_test_session(conn, %{"current_user_id" => user_id})
  end

  defp insert_test_courses(term_code) do
    SnowCourseCacheDb.save_courses(
      term_code: term_code,
      term_name: "Realtime Test Term",
      courses: [
        %{
          "crn" => @course_crn,
          "subject_code" => "TEST",
          "course_number" => "1130",
          "section_number" => "01",
          "name" => @course_name,
          "credit_hours" => 2,
          "instructors" => [%{"name" => "Professor Example", "primary_instructor" => true}],
          "meet_info" => [
            %{
              "building" => "Source Building",
              "building_code" => "SRC",
              "days" => ["Monday", "Wednesday"],
              "end_time" => "09:50:00",
              "room" => "101",
              "start_time" => "09:00:00"
            }
          ]
        },
        %{
          "crn" => "70002",
          "subject_code" => "TEST",
          "course_number" => "2200",
          "section_number" => "01",
          "name" => "Target Room Anchor",
          "credit_hours" => 1,
          "instructors" => [%{"name" => "Professor Example", "primary_instructor" => true}],
          "meet_info" => [
            %{
              "building" => "Target Building",
              "building_code" => "TGT",
              "days" => ["Friday"],
              "end_time" => "12:50:00",
              "room" => "202",
              "start_time" => "12:00:00"
            }
          ]
        },
        %{
          "crn" => "70003",
          "subject_code" => "TEST",
          "course_number" => "3300",
          "section_number" => "01",
          "name" => @conflict_course_name,
          "credit_hours" => 1,
          "instructors" => [%{"name" => "Professor Alternate", "primary_instructor" => true}],
          "meet_info" => [
            %{
              "building" => "Target Building",
              "building_code" => "TGT",
              "days" => ["Wednesday"],
              "end_time" => "11:30:00",
              "room" => "202",
              "start_time" => "10:45:00"
            }
          ]
        }
      ]
    )
  end

  defp insert_test_program do
    program = %ProgramAttrs{
      name: "Realtime Program #{System.unique_integer([:positive])}",
      semesters: [
        %SemesterAttrs{
          courses: [
            %CourseAttrs{
              subject_code: "TEST",
              course_number: "1130"
            }
          ]
        }
      ]
    }

    {:ok, created_program} = ProgramDb.create_program(program: program)
    created_program
  end

  defp delete_test_program(nil), do: :ok

  defp delete_test_program(program_id) do
    _ = ProgramDb.delete_program(id: program_id)
    :ok
  end

  defp course_card_selector(owner_key, crn) do
    "[data-schedule-key='#{owner_key}'] [data-week-schedule-course][data-course-payload*='\"crn\":\"#{crn}\"']"
  end

  defp delete_realtime_test_groups do
    case ScheduleChangeDb.list_groups() do
      {:ok, groups} ->
        Enum.each(groups, fn group -> ScheduleChangeDb.delete_group(group["id"]) end)

      {:error, _reason} ->
        :ok
    end
  end
end
