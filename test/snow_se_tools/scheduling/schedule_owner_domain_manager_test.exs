defmodule SnowSeTools.Scheduling.ScheduleOwnerDomainManagerTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Scheduling.ScheduleOwnerDomainManager
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}

  setup do
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    :ok
  end

  test "answers every waiter for a term that is still being loaded" do
    term_code = seed_term()

    for _reader <- 1..5 do
      ScheduleOwnerDomainManager.request_schedule_owner_course_list(
        pid: self(),
        term_code: term_code,
        owner_key: "room:Manager Hall 101"
      )
    end

    :ok = ScheduleOwnerDomainManager.await_idle()

    replies =
      for _reader <- 1..5 do
        assert_receive {:schedule_owner_course_list,
                        %{term_code: ^term_code, owner_key: "room:Manager Hall 101"} = reply}

        reply.course_list
      end

    assert length(replies) == 5
    assert Enum.all?(replies, &(&1 != []))
  end

  test "metadata and course lists come from one load of the term" do
    term_code = seed_term()

    ScheduleOwnerDomainManager.request_schedule_owners_metadata(
      pid: self(),
      term_code: term_code
    )

    :ok = ScheduleOwnerDomainManager.await_idle()

    assert_receive {:schedule_owners, %{term_code: ^term_code, schedule_owners: owners}}
    assert Enum.any?(owners, &(&1.key == "room:Manager Hall 101"))

    # The same load filled the course lists, so this one is already cached.
    state = :sys.get_state(ScheduleOwnerDomainManager)
    assert Map.has_key?(state.course_lists_by_owner_by_term, term_code)
    assert state.loading == %{}
  end

  test "keeps only the most recently used terms" do
    term_codes = for _index <- 1..4, do: seed_term()

    for term_code <- term_codes do
      ScheduleOwnerDomainManager.request_schedule_owners_metadata(
        pid: self(),
        term_code: term_code
      )

      :ok = ScheduleOwnerDomainManager.await_idle()
    end

    state = :sys.get_state(ScheduleOwnerDomainManager)
    cached = Map.keys(state.schedule_owner_metadata_by_term)

    assert length(cached) == 3
    refute hd(term_codes) in cached, "the least recently used term should have been evicted"
    assert List.last(term_codes) in cached
  end

  test "a request for a term with nothing in it still answers" do
    term_code = "empty-#{System.unique_integer([:positive])}"

    ScheduleOwnerDomainManager.request_schedule_owner_course_list(
      pid: self(),
      term_code: term_code,
      owner_key: "room:Nowhere 1"
    )

    :ok = ScheduleOwnerDomainManager.await_idle()

    assert_receive {:schedule_owner_course_list,
                    %{term_code: ^term_code, owner_key: "room:Nowhere 1", course_list: []}}
  end

  defp seed_term do
    term_code = "2029#{System.unique_integer([:positive])}"

    :ok =
      SnowCourseCacheDb.save_courses(
        term_code: term_code,
        term_name: "Manager Test Term",
        courses: [
          %{
            "crn" => "9#{System.unique_integer([:positive])}",
            "subject_code" => "TEST",
            "course_number" => "1010",
            "section_number" => "01",
            "name" => "Manager Test Course",
            "credit_hours" => 3,
            "instructors" => [%{"name" => "Manager Professor", "primary_instructor" => true}],
            "meet_info" => [
              %{
                "building" => "Manager Hall",
                "building_code" => "MGR",
                "days" => ["Monday"],
                "end_time" => "09:50:00",
                "room" => "101",
                "start_time" => "09:00:00"
              }
            ]
          }
        ]
      )

    term_code
  end
end
