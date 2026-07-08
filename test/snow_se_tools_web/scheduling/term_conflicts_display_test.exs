defmodule SnowSeToolsWeb.Scheduling.TermConflictsDisplayTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.User
  alias SnowSeTools.Scheduling.{ScheduleOwnerDomainManager}
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCachePubSub}

  @term_code "20278899"

  setup do
    start_supervised!(ScheduleOwnerDomainManager)

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
    _ = :sys.get_state(ScheduleOwnerDomainManager)

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

  defp wait_for_conflicts(view) do
    wait_for_conflicts(view, 10)
  end

  defp wait_for_conflicts(view, attempts_remaining) when attempts_remaining > 0 do
    _ = :sys.get_state(ScheduleOwnerDomainManager)
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

  defp log_in_test_user(conn) do
    {:ok, user} = User.find_or_create("conflict-display-test@example.com")
    user_id = Map.get(user, :id) || Map.fetch!(user, "id")
    Plug.Test.init_test_session(conn, %{"current_user_id" => user_id})
  end
end
