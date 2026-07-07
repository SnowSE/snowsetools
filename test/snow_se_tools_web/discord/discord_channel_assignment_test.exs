defmodule SnowSeToolsWeb.Discord.DiscordChannelAssignmentTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.{DbHelpers, User}
  alias SnowSeTools.Discord.{DiscordDb, DiscordDomainManager}
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}
  alias SnowSeTools.TestSupport.Fakes.DiscordApi

  setup do
    delete_course_channel_assignments()
    delete_student_discord_mappings()
    seed_course_cache()
    seed_discord_cache()

    start_supervised!(DiscordApi)
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(DiscordDomainManager)

    :ok
  end

  test "user assigns a Discord channel to a course for a term", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    assert has_element?(view, "[id='discord-channel-row-discord-channel-row:channel-100']")

    view
    |> element("button[phx-click='discord-channel-assign-modal:open']")
    |> render_click()

    assert has_element?(view, "#discord-channel-assign-modal-channel-100")

    view
    |> element("#discord-assign-form")
    |> render_change(%{"assign_form" => %{"selected_term" => "202640", "course_query" => ""}})

    assert has_element?(view, "#discord-assign-course-option-12345")

    view
    |> element("#discord-assign-course-option-12345")
    |> render_click()

    view
    |> element("#discord-assign-save")
    |> render_click()

    flush_assignment_flow(view)
    render(view)

    refute has_element?(view, "#discord-channel-assign-modal-channel-100")

    assignment = DiscordDb.get_course_channel_assignment(channel_id: "channel-100")

    assert %{
             "crn" => "12345",
             "term_code" => "202640",
             "discord_channel_id" => "channel-100",
             "discord_role_id" => "role-course",
             "created_at" => created_at
           } = assignment

    assert is_binary(created_at)

    assert has_element?(
             view,
             "[id='discord-channel-row-discord-channel-row:channel-100'] span",
             "202640 12345 Intro to Engineering"
           )

    view
    |> element("button[phx-click='discord-channel-sync-modal:open']")
    |> render_click()

    assert has_element?(view, "#discord-channel-sync-form-discord-channel-row\\:channel-100")

    assert has_element?(
             view,
             "#discord-channel-sync-jwt-discord-channel-row\\:channel-100-copy-button"
           )

    assert has_element?(
             view,
             "#discord-channel-sync-jwt-discord-channel-row\\:channel-100-input[name='snow_sync[jwt_token]']"
           )

    assert DiscordApi.calls() == []
  end

  test "professor adds a course by creating a Discord channel in a selected group", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    view
    |> element("#discord-add-my-courses-open")
    |> render_click()

    assert has_element?(view, "#discord-add-my-courses-modal")
    assert has_element?(view, "#discord-add-my-courses-term option[value='202640'][selected]")
    refute has_element?(view, "#discord-add-my-courses-channel-group")

    view
    |> element("#discord-add-my-courses-form")
    |> render_change(%{
      "_target" => ["add_my_courses", "course_query"],
      "add_my_courses" => %{"course_query" => "engr1010"}
    })

    assert has_element?(view, "#discord-add-my-courses-option-12345")
    refute has_element?(view, "#discord-add-my-courses-option-99999")

    view
    |> element("#discord-add-my-courses-option-12345")
    |> render_click()

    assert has_element?(
             view,
             "#discord-add-my-courses-channel-name[value='engr-1010-2026-fall']"
           )

    assert has_element?(view, "#discord-add-my-courses-channel-group")
    assert has_element?(view, "#discord-add-my-courses-channel-group option[value='category-10']")

    refute has_element?(view, "#discord-add-my-courses-role")

    view
    |> element("#discord-add-my-courses-create")
    |> render_click()

    flush_created_channel_flow(view)
    render(view)

    refute has_element?(view, "#discord-add-my-courses-modal")

    assert {:create_text_channel, %{name: "engr-1010-2026-fall", parent_id: "category-10"}} in DiscordApi.calls()

    assignment = DiscordDb.get_course_channel_assignment_by_crn(crn: "12345")

    assert %{
             "crn" => "12345",
             "term_code" => "202640",
             "discord_role_id" => "role-course",
             "discord_channel_id" => created_channel_id
           } = assignment

    assert is_binary(created_channel_id)

    assert has_element?(view, "[id^='discord-channel-row-discord-channel-row:created-channel-']")

    assert has_element?(
             view,
             "[id^='discord-channel-row-discord-channel-row:created-channel-'] span",
             "engr-1010-2026-fall"
           )
  end

  test "selecting a different course re-auto-selects the matching channel group", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    view
    |> element("#discord-add-my-courses-open")
    |> render_click()

    view
    |> element("#discord-add-my-courses-form")
    |> render_change(%{
      "_target" => ["add_my_courses", "course_query"],
      "add_my_courses" => %{"course_query" => "engr1010"}
    })

    view
    |> element("#discord-add-my-courses-option-12345")
    |> render_click()

    assert has_element?(view, "#discord-add-my-courses-channel-group option[value='category-10']")

    view
    |> element("#discord-add-my-courses-form")
    |> render_change(%{
      "_target" => ["add_my_courses", "course_query"],
      "add_my_courses" => %{"course_query" => "cs1410"}
    })

    view
    |> element("#discord-add-my-courses-option-14100")
    |> render_click()

    assert has_element?(view, "#discord-add-my-courses-selection-14100")

    assert has_element?(
             view,
             "#discord-add-my-courses-channel-group option[value='category-2030'][selected]"
           )

    assert has_element?(view, "#discord-add-my-courses-channel-name[value='cs-1410-2026-fall']")

    view
    |> element("#discord-add-my-courses-create")
    |> render_click()

    flush_created_channel_flow(view)

    assert {:create_text_channel, %{name: "cs-1410-2026-fall", parent_id: "category-2030"}} in DiscordApi.calls()

    assert %{
             "crn" => "14100",
             "discord_role_id" => "role-may-30"
           } = DiscordDb.get_course_channel_assignment_by_crn(crn: "14100")
  end

  test "course search preserves the selected term and matches name code or subject", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    view
    |> element("button[phx-click='discord-channel-assign-modal:open']")
    |> render_click()

    view
    |> element("#discord-assign-form")
    |> render_change(%{"assign_form" => %{"selected_term" => "202640", "course_query" => ""}})

    assert has_element?(view, "#discord-assign-course-option-12345")
    assert has_element?(view, "#discord-assign-course-option-99999")

    view
    |> element("#discord-assign-form")
    |> render_change(%{
      "_target" => ["assign_form", "course_query"],
      "assign_form" => %{"course_query" => "college"}
    })

    assert has_element?(view, "#discord-assign-course-option-99999")
    refute has_element?(view, "#discord-assign-course-option-12345")

    view
    |> element("#discord-assign-form")
    |> render_change(%{
      "_target" => ["assign_form", "course_query"],
      "assign_form" => %{"course_query" => "engr1010"}
    })

    assert has_element?(view, "#discord-assign-course-option-12345")
    refute has_element?(view, "#discord-assign-course-option-99999")

    view
    |> element("#discord-assign-form")
    |> render_change(%{
      "_target" => ["assign_form", "course_query"],
      "assign_form" => %{"course_query" => "math"}
    })

    assert has_element?(view, "#discord-assign-course-option-99999")
    refute has_element?(view, "#discord-assign-course-option-12345")

    assert has_element?(view, "#discord-assign-course-query[phx-debounce='200']")
    assert DiscordApi.calls() == []
  end

  test "assign modal pre-populates term and search from the Discord channel name", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    view
    |> element("button[phx-click='discord-channel-assign-modal:open']")
    |> render_click()

    assert has_element?(view, "#discord-assign-term-select option[value='202640'][selected]")
    assert has_element?(view, "#discord-assign-course-query[value='distributed']")
    assert has_element?(view, "#discord-assign-course-option-55555")
    refute has_element?(view, "#discord-assign-course-option-12345")
  end

  test "user renames a Discord channel and refreshes the cached name from Discord", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    view
    |> element("[id='discord-channel-rename-discord-channel-row:channel-100']")
    |> render_click()

    assert has_element?(
             view,
             "[id='discord-channel-rename-input-discord-channel-row:channel-100'][value='distributed']"
           )

    view
    |> element("[id='discord-channel-rename-form-discord-channel-row:channel-100']")
    |> render_submit(%{"key" => "discord-channel-row:channel-100", "channel_name" => "Survey"})

    flush_renamed_channel_flow(view, "survey")
    render(view)

    assert {:rename_channel, %{channel_id: "channel-100", new_name: "survey"}} in DiscordApi.calls()

    assert Enum.any?(DiscordDb.list_channels(), fn channel ->
             channel["id"] == "channel-100" and channel["name"] == "survey"
           end)

    assert has_element?(
             view,
             "[id='discord-channel-row-discord-channel-row:channel-100'] span",
             "survey"
           )

    refute has_element?(
             view,
             "[id='discord-channel-rename-form-discord-channel-row:channel-100']"
           )
  end

  test "rename form pre-populates a plain channel name with the assigned term suffix", %{
    conn: conn
  } do
    :ok =
      DiscordDb.save_channel(
        channel: %{
          "id" => "channel-100",
          "name" => "survey",
          "type" => 0,
          "parent_id" => "category-10",
          "position" => 1,
          "permission_overwrites" => []
        }
      )

    DiscordDb.save_course_channel_assignment(
      crn: "12345",
      term_code: "202640",
      discord_channel_id: "channel-100",
      discord_role_id: "role-course"
    )

    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    flush_assignment_flow(view)
    render(view)

    view
    |> element("[id='discord-channel-rename-discord-channel-row:channel-100']")
    |> render_click()

    assert has_element?(
             view,
             "[id='discord-channel-rename-input-discord-channel-row:channel-100'][value='survey-2026-fall']"
           )
  end

  test "channel rendering prefers the raw Discord name when cached name is the channel id", %{
    conn: conn
  } do
    :ok =
      DiscordDb.save_channel(
        channel: %{
          "id" => "channel-100",
          "name" => "survey",
          "type" => 0,
          "parent_id" => "category-10",
          "position" => 1,
          "permission_overwrites" => []
        }
      )

    case DbHelpers.run_sql(
           "UPDATE discord_channels SET name = $(name) WHERE id = $(id)",
           %{"name" => "channel-100", "id" => "channel-100"}
         ) do
      {:error, reason} -> raise "Failed to seed bad channel name: #{inspect(reason)}"
      _result -> :ok
    end

    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    render(view)

    assert has_element?(
             view,
             "[id='discord-channel-row-discord-channel-row:channel-100'] span",
             "survey"
           )

    refute has_element?(
             view,
             "[id='discord-channel-row-discord-channel-row:channel-100'] span",
             "channel-100"
           )
  end

  test "user removes a Discord channel course assignment from course details", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    view
    |> element("button[phx-click='discord-channel-assign-modal:open']")
    |> render_click()

    view
    |> element("#discord-assign-form")
    |> render_change(%{"assign_form" => %{"selected_term" => "202640", "course_query" => ""}})

    view
    |> element("#discord-assign-course-option-12345")
    |> render_click()

    view
    |> element("#discord-assign-save")
    |> render_click()

    flush_assignment_flow(view)
    render(view)

    assert DiscordDb.get_course_channel_assignment(channel_id: "channel-100")

    assert has_element?(
             view,
             "button[phx-click='discord-channel-sync-modal:open']",
             "Sync roster"
           )

    assert has_element?(
             view,
             "[id='discord-channel-remove-assignment-discord-channel-row:channel-100']",
             "Remove course assignment"
           )

    view
    |> element("[id='discord-channel-remove-assignment-discord-channel-row:channel-100']")
    |> render_click()

    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    render(view)

    refute DiscordDb.get_course_channel_assignment(channel_id: "channel-100")

    assert has_element?(view, "button[phx-click='discord-channel-assign-modal:open']")

    refute has_element?(
             view,
             "button[phx-click='discord-channel-sync-modal:open']",
             "Sync roster"
           )

    refute has_element?(
             view,
             "[id='discord-channel-remove-assignment-discord-channel-row:channel-100']"
           )

    assert DiscordApi.calls() == []
  end

  test "user confirms Discord channel deletion from course details", %{conn: conn} do
    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    view
    |> element("button[phx-click='discord-channel-assign-modal:open']")
    |> render_click()

    view
    |> element("#discord-assign-form")
    |> render_change(%{"assign_form" => %{"selected_term" => "202640", "course_query" => ""}})

    view
    |> element("#discord-assign-course-option-12345")
    |> render_click()

    view
    |> element("#discord-assign-save")
    |> render_click()

    flush_assignment_flow(view)
    render(view)

    assert DiscordDb.get_course_channel_assignment(channel_id: "channel-100")
    assert has_element?(view, "[id='discord-channel-delete-discord-channel-row:channel-100']")

    view
    |> element("[id='discord-channel-delete-discord-channel-row:channel-100']")
    |> render_click()

    assert has_element?(view, "#discord-channel-delete-modal-discord-channel-row\\:channel-100")

    view
    |> element("[id='discord-channel-delete-cancel-discord-channel-row:channel-100']")
    |> render_click()

    refute has_element?(view, "#discord-channel-delete-modal-discord-channel-row\\:channel-100")

    view
    |> element("[id='discord-channel-delete-discord-channel-row:channel-100']")
    |> render_click()

    view
    |> element("[id='discord-channel-delete-confirm-discord-channel-row:channel-100']")
    |> render_click()

    flush_deleted_channel_flow(view)
    render(view)

    refute DiscordDb.get_course_channel_assignment(channel_id: "channel-100")

    refute Enum.any?(DiscordDb.list_channels(), fn channel ->
             channel["id"] == "channel-100"
           end)

    refute has_element?(view, "#discord-channel-delete-modal-discord-channel-row\\:channel-100")

    assert {:delete_channel, %{channel_id: "channel-100"}} in DiscordApi.calls()
  end

  test "synced student rosters render from cached database rows", %{conn: conn} do
    :ok =
      SnowCourseCacheDb.save_section_students(
        term_code: "202640",
        crn: "12345",
        students: [
          %{
            "badgerid" => "b00000001",
            "first_name" => "Grace",
            "last_name" => "Hopper",
            "email" => "grace@example.com"
          }
        ]
      )

    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    view
    |> element("button[phx-click='discord-channel-assign-modal:open']")
    |> render_click()

    view
    |> element("#discord-assign-form")
    |> render_change(%{"assign_form" => %{"selected_term" => "202640", "course_query" => ""}})

    view
    |> element("#discord-assign-course-option-12345")
    |> render_click()

    view
    |> element("#discord-assign-save")
    |> render_click()

    flush_assignment_flow(view)
    render(view)

    assert has_element?(
             view,
             "[id='discord-channel-row-discord-channel-row:channel-100']",
             "Roster 1"
           )

    assert has_element?(
             view,
             "[id='discord-student-row-b00000001-discord-student-row:discord-student-mapping:discord-channel-row:channel-100:b00000001']",
             "Grace Hopper"
           )

    assert DiscordApi.calls() == []
  end

  test "match to Discord user opens inline search panel and assigns a member", %{conn: conn} do
    :ok =
      SnowCourseCacheDb.save_section_students(
        term_code: "202640",
        crn: "12345",
        students: [
          %{
            "badgerid" => "b00000001",
            "first_name" => "Grace",
            "last_name" => "Hopper",
            "email" => "grace@example.com"
          }
        ]
      )

    :ok =
      DiscordDb.save_members(
        members: [
          %{
            "nick" => "Grace H",
            "roles" => [],
            "user" => %{
              "id" => "discord-user-1",
              "username" => "gracehopper",
              "global_name" => "Grace Hopper"
            }
          },
          %{
            "nick" => nil,
            "roles" => [],
            "user" => %{
              "id" => "discord-user-2",
              "username" => "alan",
              "global_name" => "Alan Turing"
            }
          }
        ]
      )

    conn = log_in_test_user(conn)

    {:ok, view, _html} = live(conn, ~p"/discord")

    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(DiscordDomainManager)
    render(view)

    view
    |> element("button[phx-click='discord-channel-assign-modal:open']")
    |> render_click()

    view
    |> element("#discord-assign-form")
    |> render_change(%{"assign_form" => %{"selected_term" => "202640", "course_query" => ""}})

    view
    |> element("#discord-assign-course-option-12345")
    |> render_click()

    view
    |> element("#discord-assign-save")
    |> render_click()

    flush_assignment_flow(view)
    render(view)

    row_key =
      "discord-student-row:discord-student-mapping:discord-channel-row:channel-100:b00000001"

    view
    |> element("button[phx-click='discord-student-row:toggle_assign_panel']")
    |> render_click()

    assert has_element?(view, "[id='discord-student-row-assign-panel-#{row_key}']")
    assert has_element?(view, "[id='discord-student-row-search-input-#{row_key}'][value='Grace']")

    assert has_element?(
             view,
             "[id='discord-student-row-member-option-#{row_key}-discord-user-1']"
           )

    refute has_element?(
             view,
             "[id='discord-student-row-member-option-#{row_key}-discord-user-2']"
           )

    view
    |> element("[id='discord-student-row-search-form-#{row_key}']")
    |> render_change(%{"search_text" => "grace"})

    assert has_element?(
             view,
             "[id='discord-student-row-member-option-#{row_key}-discord-user-1']"
           )

    refute has_element?(
             view,
             "[id='discord-student-row-member-option-#{row_key}-discord-user-2']"
           )

    view
    |> element("[id='discord-student-row-member-option-#{row_key}-discord-user-1']")
    |> render_click()

    flush_student_mapping_flow(view)

    assert Enum.any?(DiscordDb.list_student_discord_mappings(), fn mapping ->
             mapping["badger_id"] == "b00000001" and
               mapping["discord_user_id"] == "discord-user-1"
           end)

    assert has_element?(
             view,
             "[id='discord-student-row-b00000001-#{row_key}']",
             "Grace H"
           )

    assert has_element?(
             view,
             "[id='discord-student-row-b00000001-#{row_key}']",
             "discord user"
           )

    assert has_element?(
             view,
             "button[phx-click='discord-student-row:add_role'][phx-value-role-id='role-course']",
             "Add ENGR 1010"
           )

    refute has_element?(
             view,
             "button[phx-click='discord-student-row:add_role'][phx-value-role-id='role-bot']"
           )

    view
    |> element(
      "button[phx-click='discord-student-row:add_role'][phx-value-role-id='role-course']"
    )
    |> render_click()

    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)

    assert {:add_role_to_member, %{member_id: "discord-user-1", role_id: "role-course"}} in DiscordApi.calls()
  end

  test "cached roster students are returned as normalized maps" do
    :ok =
      SnowCourseCacheDb.save_section_students(
        term_code: "202640",
        crn: "12345",
        students: [
          %{
            "badgerid" => "b00000001",
            "first_name" => "Grace",
            "last_name" => "Hopper",
            "email" => "grace@example.com"
          }
        ]
      )

    assert {:ok, [student]} =
             SnowCourseCacheDb.get_section_students(term_code: "202640", crn: "12345")

    assert %{
             "badger_id" => "b00000001",
             "badgerid" => "b00000001",
             "first_name" => "Grace",
             "last_name" => "Hopper",
             "email" => "grace@example.com"
           } = student
  end

  defp log_in_test_user(conn) do
    {:ok, user} = User.find_or_create("discord-channel-assignment@example.com")
    user_id = Map.get(user, :id) || Map.fetch!(user, "id")

    Plug.Test.init_test_session(conn, %{"current_user_id" => user_id})
  end

  defp delete_course_channel_assignments do
    case DbHelpers.run_sql("DELETE FROM course_channel_assignments", %{}) do
      {:error, reason} -> raise "Failed to clean course channel assignments: #{inspect(reason)}"
      _result -> :ok
    end
  end

  defp delete_student_discord_mappings do
    case DbHelpers.run_sql("DELETE FROM student_discord_mapping", %{}) do
      {:error, reason} -> raise "Failed to clean student Discord mappings: #{inspect(reason)}"
      _result -> :ok
    end
  end

  defp seed_course_cache do
    :ok =
      SnowCourseCacheDb.save_courses(
        term_code: "202640",
        term_name: "Fall 2026",
        courses: [
          %{
            "crn" => "12345",
            "subject_code" => "ENGR",
            "course_number" => "1010",
            "section_number" => "01",
            "name" => "Intro to Engineering",
            "instructors" => [%{"name" => "Ada Lovelace", "primary_instructor" => true}]
          },
          %{
            "crn" => "99999",
            "subject_code" => "MATH",
            "course_number" => "1050",
            "section_number" => "01",
            "name" => "College Algebra",
            "instructors" => []
          },
          %{
            "crn" => "55555",
            "subject_code" => "CS",
            "course_number" => "4500",
            "section_number" => "01",
            "name" => "Distributed Systems",
            "instructors" => []
          },
          %{
            "crn" => "14100",
            "subject_code" => "CS",
            "course_number" => "1410",
            "section_number" => "01",
            "name" => "Introduction to Programming",
            "instructors" => []
          }
        ]
      )
  end

  defp seed_discord_cache do
    :ok =
      DiscordDb.save_channels(
        channels: [
          %{
            "id" => "category-10",
            "name" => "Courses",
            "type" => 4,
            "position" => 1,
            "permission_overwrites" => [
              %{"id" => "role-course", "type" => 0, "allow" => "1024", "deny" => "0"}
            ]
          },
          %{
            "id" => "category-2030",
            "name" => "class of 2030(MAY)",
            "type" => 4,
            "position" => 2,
            "permission_overwrites" => [
              %{"id" => "role-may-30", "type" => 0, "allow" => "1024", "deny" => "0"}
            ]
          },
          %{
            "id" => "channel-100",
            "name" => "distributed-2026-fall",
            "type" => 0,
            "parent_id" => "category-10",
            "position" => 1,
            "permission_overwrites" => [
              %{"id" => "role-bot", "type" => 0, "allow" => "2048", "deny" => "0"},
              %{"id" => "role-course", "type" => 0, "allow" => "1024", "deny" => "0"}
            ]
          }
        ]
      )

    :ok =
      DiscordDb.save_roles(
        roles: [
          %{"id" => "guild-id", "name" => "@everyone", "position" => 0},
          %{"id" => "role-course", "name" => "ENGR 1010", "position" => 10},
          %{"id" => "role-may-30", "name" => "may_30", "position" => 11},
          %{
            "id" => "role-bot",
            "name" => "Syllabus Bot",
            "position" => 99
          }
        ]
      )
  end

  defp flush_assignment_flow(view) do
    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(view.pid)
  end

  defp flush_student_mapping_flow(view) do
    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
  end

  defp flush_created_channel_flow(view) do
    wait_for_created_channel_row(view, 20)
  end

  defp flush_renamed_channel_flow(view, channel_name) do
    wait_for_channel_name(view, channel_name, 20)
  end

  defp wait_for_created_channel_row(view, attempts_remaining) when attempts_remaining > 0 do
    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    _ = :sys.get_state(SnowCourseCacheDomainManager)
    _ = :sys.get_state(view.pid)
    render(view)

    if has_element?(view, "[id^='discord-channel-row-discord-channel-row:created-channel-']") do
      :ok
    else
      wait_for_created_channel_row(view, attempts_remaining - 1)
    end
  end

  defp wait_for_created_channel_row(_view, 0) do
    :ok
  end

  defp wait_for_channel_name(view, channel_name, attempts_remaining)
       when attempts_remaining > 0 do
    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    render(view)

    if has_element?(
         view,
         "[id='discord-channel-row-discord-channel-row:channel-100'] span",
         channel_name
       ) do
      :ok
    else
      wait_for_channel_name(view, channel_name, attempts_remaining - 1)
    end
  end

  defp wait_for_channel_name(view, _channel_name, 0) do
    html = render(view)
    document = LazyHTML.from_fragment(html)
    row = LazyHTML.filter(document, "[id='discord-channel-row-discord-channel-row:channel-100']")
    flunk("Timed out waiting for Discord channel name to render: #{inspect(row)}")
  end

  defp flush_deleted_channel_flow(view) do
    wait_for_deleted_channel(view, "channel-100", 20)
  end

  defp wait_for_deleted_channel(view, channel_id, attempts_remaining)
       when attempts_remaining > 0 do
    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    _ = :sys.get_state(DiscordDomainManager)
    _ = :sys.get_state(view.pid)
    render(view)

    if Enum.any?(DiscordDb.list_channels(), fn channel -> channel["id"] == channel_id end) do
      wait_for_deleted_channel(view, channel_id, attempts_remaining - 1)
    else
      :ok
    end
  end

  defp wait_for_deleted_channel(_view, channel_id, 0) do
    flunk("Timed out waiting for Discord channel #{channel_id} to be deleted")
  end
end
