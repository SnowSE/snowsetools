defmodule SnowSeToolsWeb.Scheduling.TermConflictsDisplayTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Scheduling.{AcknowledgedConflictDomainManager, ScheduleOwnerDomainManager}
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCachePubSub}

  @term_code "20278899"
  @smith ~s([data-owner-key="professor:Dr. Smith"])

  setup do
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(AcknowledgedConflictDomainManager)

    # Insert two courses taught by the same professor at overlapping times
    # This should produce exactly 1 professor conflict
    SnowCourseCacheDb.save_courses(
      term_code: @term_code,
      term_name: "Conflict Test Term",
      courses: [
        %{
          "crn" => "50001",
          "subject_code" => "PSY",
          "course_number" => "1010",
          "section_number" => "01",
          "name" => "General Psychology",
          "credit_hours" => 3,
          "instructors" => [%{"name" => "Dr. Smith", "primary_instructor" => true}],
          "meet_info" => [
            %{
              "building" => "Science Hall",
              "building_code" => "SCI",
              "days" => ["Monday", "Wednesday"],
              "end_time" => "10:50:00",
              "room" => "201",
              "start_time" => "09:00:00"
            }
          ]
        },
        %{
          "crn" => "50002",
          "subject_code" => "BIO",
          "course_number" => "1100",
          "section_number" => "01",
          "name" => "Intro to Biology",
          "credit_hours" => 3,
          "instructors" => [%{"name" => "Dr. Smith", "primary_instructor" => true}],
          "meet_info" => [
            %{
              "building" => "Science Hall",
              "building_code" => "SCI",
              "days" => ["Monday", "Wednesday"],
              "end_time" => "10:50:00",
              "room" => "305",
              "start_time" => "09:00:00"
            }
          ]
        }
      ]
    )

    SnowCourseCachePubSub.broadcast_course_cache_updated(@term_code, "Conflict Test Term")
    :ok = ScheduleOwnerDomainManager.await_idle()

    {:ok, term_code: @term_code}
  end

  test "renders conflict count and details when professor teaches two courses at same time",
       %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{@term_code}")

    # Wait for schedule metadata and conflict detection to complete
    wait_for_conflicts(view)

    # Verify the conflict section exists and shows count of 1
    assert has_element?(view, "#schedule-term-conflicts")
    assert has_element?(view, "#schedule-term-conflicts", "1")

    # Verify professor conflict card is rendered
    assert has_element?(view, ~s([data-owner-key="professor:Dr. Smith"]))
    assert has_element?(view, ~s([data-owner-key="professor:Dr. Smith"]), "Dr. Smith")
    assert has_element?(view, ~s([data-owner-key="professor:Dr. Smith"]), "PSY 1010")
    assert has_element?(view, ~s([data-owner-key="professor:Dr. Smith"]), "BIO 1100")
  end

  describe "acknowledging a conflict" do
    test "takes it off the list until it is reset", %{conn: conn} do
      conn = log_in_user(conn, unique_email("conflict-ack"), ["scheduling_admin"])

      view = open_viewer(conn, @term_code)
      wait_for_conflict(view, @smith)

      acknowledge_conflict(view, @smith)

      refute has_element?(view, @smith)
      # Every copy of it goes, not just the card it was clicked on.
      refute has_element?(view, "button[phx-click='schedule-term-conflicts:acknowledge']")
      assert has_element?(view, "#schedule-conflicts-acknowledged", "1 acknowledged")
      assert has_element?(view, "#schedule-term-conflicts", "every conflict in this term")

      view |> element("#schedule-conflicts-reset-acknowledged") |> render_click()
      settle(view)

      assert has_element?(view, @smith)
      refute has_element?(view, "#schedule-conflicts-acknowledged")
    end

    test "is still acknowledged the next time the page is opened", %{conn: conn} do
      conn = log_in_user(conn, unique_email("conflict-ack-again"), ["scheduling_admin"])

      view = open_viewer(conn, @term_code)
      wait_for_conflict(view, @smith)
      acknowledge_conflict(view, @smith)

      {:ok, reopened, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{@term_code}")
      settle(reopened)

      refute has_element?(reopened, @smith)
      assert has_element?(reopened, "#schedule-conflicts-acknowledged", "1 acknowledged")
    end

    test "comes back on its own when one of the classes moves", %{conn: conn} do
      term_code = "2027#{System.unique_integer([:positive])}"
      owner = ~s([data-owner-key="professor:Dr. Moves"])
      seed_two_overlapping_courses(term_code, professor: "Dr. Moves", start_time: "13:00:00")

      conn = log_in_user(conn, unique_email("conflict-ack-moves"), ["scheduling_admin"])

      view = open_viewer(conn, term_code)
      wait_for_conflict(view, owner)
      acknowledge_conflict(view, owner)
      refute has_element?(view, owner)

      # The registrar moves the second class. The clash that comes back is a
      # different one than the one that was acknowledged.
      seed_two_overlapping_courses(term_code, professor: "Dr. Moves", start_time: "13:30:00")

      {:ok, reopened, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")
      wait_for_conflict(reopened, owner)

      assert has_element?(reopened, owner)
      refute has_element?(reopened, "#schedule-conflicts-acknowledged")
    end
  end

  defp open_viewer(conn, term_code) do
    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{term_code}")
    view
  end

  # One clash is listed under every owner it touches — the professor and both
  # rooms — so this clicks the copy on one card and the rest go with it.
  defp acknowledge_conflict(view, owner_selector) do
    view
    |> element("#{owner_selector} button[phx-click='schedule-term-conflicts:acknowledge']")
    |> render_click()

    settle(view)
  end

  # The domain manager answers by message, so both it and the page have to have
  # got through their mailboxes before the screen means anything.
  defp settle(view) do
    _ = :sys.get_state(AcknowledgedConflictDomainManager)
    _ = :sys.get_state(view.pid)
    render(view)
  end

  defp wait_for_conflict(view, owner_selector, attempts \\ 20) do
    :ok = ScheduleOwnerDomainManager.await_idle()
    settle(view)

    cond do
      has_element?(view, owner_selector) -> :ok
      attempts == 0 -> flunk("expected a conflict for #{owner_selector} to render")
      true -> Process.sleep(25) && wait_for_conflict(view, owner_selector, attempts - 1)
    end
  end

  defp seed_two_overlapping_courses(term_code, professor: professor, start_time: start_time) do
    SnowCourseCacheDb.save_courses(
      term_code: term_code,
      term_name: "Acknowledge Test Term",
      courses: [
        overlapping_course("60001", "ENG", professor, "101", "13:00:00"),
        overlapping_course("60002", "HIST", professor, "102", start_time)
      ]
    )

    SnowCourseCachePubSub.broadcast_course_cache_updated(term_code, "Acknowledge Test Term")
    :ok = ScheduleOwnerDomainManager.await_idle()
  end

  defp overlapping_course(crn, subject, professor, room, start_time) do
    %{
      "crn" => crn,
      "subject_code" => subject,
      "course_number" => "1010",
      "section_number" => "01",
      "name" => "#{subject} Survey",
      "credit_hours" => 3,
      "instructors" => [%{"name" => professor, "primary_instructor" => true}],
      "meet_info" => [
        %{
          "building" => "Moving Hall",
          "building_code" => "MOV",
          "days" => ["Tuesday"],
          "start_time" => start_time,
          "end_time" => "14:50:00",
          "room" => room
        }
      ]
    }
  end

  defp wait_for_conflicts(view) do
    wait_for_conflicts(view, 10)
  end

  defp wait_for_conflicts(view, attempts_remaining) when attempts_remaining > 0 do
    :ok = ScheduleOwnerDomainManager.await_idle()
    _ = :sys.get_state(view.pid)
    render(view)

    if has_element?(view, "#schedule-term-conflicts", "1") do
      :ok
    else
      wait_for_conflicts(view, attempts_remaining - 1)
    end
  end

  defp wait_for_conflicts(_view, 0) do
    flunk("expected schedule conflicts to render")
  end

  defp log_in_test_user(conn),
    do: log_in_user(conn, "conflict-display-test@example.com", ["scheduling_admin"])
end
