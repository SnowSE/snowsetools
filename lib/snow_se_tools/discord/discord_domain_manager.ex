defmodule SnowSeTools.Discord.DiscordDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.Discord.{DiscordApi, DiscordDb, DiscordPubSub}
  alias SnowSeTools.Snow.{MySnowApi, SnowCourseCacheDb}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def request_sync_summary(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_sync_summary, pid, key})
  end

  def request_server_status(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_server_status, pid, key})
  end

  def request_channels(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_channels, pid, key})
  end

  def request_members(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_members, pid, key})
  end

  def request_roles(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_roles, pid, key})
  end

  def request_invites(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_invites, pid, key})
  end

  def request_course_channel_assignment(pid: pid, key: key, channel_id: channel_id)
      when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_course_channel_assignment, pid, key, channel_id})
  end

  def request_student_discord_mappings(pid: pid, key: key) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_student_discord_mappings, pid, key})
  end

  def request_student_mappings_for_course(
        pid: pid,
        key: key,
        term_code: term_code,
        crn: crn
      )
      when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_student_mappings_for_course, pid, key, term_code, crn})
  end

  def sync_all(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:sync_all, pid})
  end

  def save_course_channel_assignment(
        pid: pid,
        key: key,
        crn: crn,
        term_code: term_code,
        discord_channel_id: discord_channel_id,
        discord_role_id: discord_role_id
      ) do
    GenServer.cast(
      __MODULE__,
      {:save_course_channel_assignment, pid, key, crn, term_code, discord_channel_id,
       discord_role_id}
    )
  end

  def create_course_channel(
        pid: pid,
        key: key,
        crn: crn,
        term_code: term_code,
        channel_name: channel_name,
        parent_id: parent_id,
        discord_role_id: discord_role_id
      ) do
    GenServer.cast(
      __MODULE__,
      {:create_course_channel, pid, key, crn, term_code, channel_name, parent_id, discord_role_id}
    )
  end

  def delete_course_channel_assignment(pid: pid, key: key, crn: crn) do
    GenServer.cast(__MODULE__, {:delete_course_channel_assignment, pid, key, crn})
  end

  def save_student_discord_mapping(
        pid: pid,
        key: key,
        badger_id: badger_id,
        discord_user_id: discord_user_id
      ) do
    GenServer.cast(
      __MODULE__,
      {:save_student_discord_mapping, pid, key, badger_id, discord_user_id}
    )
  end

  def delete_student_discord_mapping(pid: pid, key: key, badger_id: badger_id) do
    GenServer.cast(__MODULE__, {:delete_student_discord_mapping, pid, key, badger_id})
  end

  def add_role_to_member(pid: pid, key: key, member_id: member_id, role_id: role_id) do
    GenServer.cast(__MODULE__, {:add_role_to_member, pid, key, member_id, role_id})
  end

  def sync_course_roster(
        pid: pid,
        key: key,
        term_code: term_code,
        crn: crn,
        jwt_token: jwt_token
      ) do
    GenServer.cast(__MODULE__, {:sync_course_roster, pid, key, term_code, crn, jwt_token})
  end

  def init(:ok) do
    case DiscordDb.bootstrap_discord_tables() do
      {:error, reason} ->
        Logger.error("Discord domain bootstrap failed reason=#{inspect(reason)}")
        {:stop, reason}

      _ ->
        {:ok, %{}}
    end
  end

  def handle_cast({:request_sync_summary, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:sync_summary_loaded, key},
      fetch: &DiscordDb.sync_summary/0,
      error_context: "Discord sync summary load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_server_status, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:server_status_loaded, key},
      fetch: &DiscordDb.get_server_status/0,
      error_context: "Discord server status load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_channels, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:channels_loaded, key},
      fetch: &DiscordDb.list_channels/0,
      error_context: "Discord channels load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_members, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:members_loaded, key},
      fetch: &DiscordDb.list_members/0,
      error_context: "Discord members load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_roles, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:roles_loaded, key},
      fetch: &DiscordDb.list_roles/0,
      error_context: "Discord roles load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_invites, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:invites_loaded, key},
      fetch: &DiscordDb.list_invites/0,
      error_context: "Discord invites load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_course_channel_assignment, pid, key, channel_id}, state) do
    send_db_result(
      pid: pid,
      message: {:course_channel_assignment_loaded, key},
      fetch: fn -> DiscordDb.get_course_channel_assignment(channel_id: channel_id) end,
      error_context: "Discord course channel assignment load failed"
    )

    {:noreply, state}
  end

  def handle_cast({:request_student_discord_mappings, pid, key}, state) do
    send_db_result(
      pid: pid,
      message: {:student_discord_mappings_loaded, key},
      fetch: &DiscordDb.list_student_discord_mappings/0,
      error_context: "Discord student discord mappings load failed"
    )

    {:noreply, state}
  end

  def handle_cast(
        {:request_student_mappings_for_course, pid, key, term_code, crn},
        state
      ) do
    with all_mappings when is_list(all_mappings) <- DiscordDb.list_student_discord_mappings(),
         {:ok, students} <- SnowCourseCacheDb.get_section_students(term_code: term_code, crn: crn) do
      course_badger_ids =
        students
        |> Enum.map(&Map.get(&1, "badger_id"))
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      filtered =
        Enum.filter(
          all_mappings,
          fn mapping -> MapSet.member?(course_badger_ids, mapping["badger_id"]) end
        )

      send(pid, {:discord, {:student_mappings_for_course_loaded, key, {:ok, filtered}}})
    else
      {:error, reason} ->
        Logger.error("Discord student mappings for course load failed reason=#{inspect(reason)}")
        send(pid, {:discord, {:student_mappings_for_course_loaded, key, {:error, reason}}})

      unexpected ->
        Logger.error(
          "Discord student mappings for course load returned unexpected result=#{inspect(unexpected)}"
        )

        send(
          pid,
          {:discord,
           {:student_mappings_for_course_loaded, key, {:error, {:unexpected, unexpected}}}}
        )
    end

    {:noreply, state}
  end

  def handle_cast(
        {:save_course_channel_assignment, pid, key, crn, term_code, discord_channel_id,
         discord_role_id},
        state
      ) do
    case DiscordDb.save_course_channel_assignment(
           crn: crn,
           term_code: term_code,
           discord_channel_id: discord_channel_id,
           discord_role_id: discord_role_id
         ) do
      {:error, reason} ->
        Logger.error(
          "Discord course channel assignment save failed crn=#{crn} channel_id=#{discord_channel_id} reason=#{inspect(reason)}"
        )

        send(pid, {:discord, {:course_channel_assignment_saved, key, {:error, reason}}})

      _ ->
        send(pid, {:discord, {:course_channel_assignment_saved, key, {:ok, %{crn: crn}}}})
    end

    {:noreply, state}
  end

  def handle_cast(
        {:create_course_channel, pid, key, crn, term_code, channel_name, parent_id,
         discord_role_id},
        state
      ) do
    create_course_channel_async(
      pid: pid,
      key: key,
      crn: crn,
      term_code: term_code,
      channel_name: channel_name,
      parent_id: parent_id,
      discord_role_id: discord_role_id
    )

    {:noreply, state}
  end

  def handle_cast({:delete_course_channel_assignment, pid, key, crn}, state) do
    case DiscordDb.delete_course_channel_assignment(crn: crn) do
      {:error, reason} ->
        Logger.error(
          "Discord course channel assignment delete failed crn=#{crn} reason=#{inspect(reason)}"
        )

        send(pid, {:discord, {:course_channel_assignment_deleted, key, {:error, reason}}})

      _ ->
        send(pid, {:discord, {:course_channel_assignment_deleted, key, {:ok, crn}}})
    end

    {:noreply, state}
  end

  def handle_cast({:save_student_discord_mapping, pid, key, badger_id, discord_user_id}, state) do
    case DiscordDb.save_student_discord_mapping(
           badger_id: badger_id,
           discord_user_id: discord_user_id
         ) do
      {:error, reason} ->
        Logger.error(
          "Discord student mapping save failed badger_id=#{badger_id} discord_user_id=#{discord_user_id} reason=#{inspect(reason)}"
        )

        send(pid, {:discord, {:student_discord_mapping_saved, key, {:error, reason}}})

      _ ->
        send(
          pid,
          {:discord,
           {:student_discord_mapping_saved, key,
            {:ok, %{badger_id: badger_id, discord_user_id: discord_user_id}}}}
        )
    end

    {:noreply, state}
  end

  def handle_cast({:delete_student_discord_mapping, pid, key, badger_id}, state) do
    case DiscordDb.delete_student_discord_mapping(badger_id: badger_id) do
      {:error, reason} ->
        Logger.error(
          "Discord student mapping delete failed badger_id=#{badger_id} reason=#{inspect(reason)}"
        )

        send(pid, {:discord, {:student_discord_mapping_deleted, key, {:error, reason}}})

      _ ->
        send(pid, {:discord, {:student_discord_mapping_deleted, key, {:ok, badger_id}}})
    end

    {:noreply, state}
  end

  def handle_cast({:add_role_to_member, pid, key, member_id, role_id}, state) do
    case discord_api().add_role_to_member(member_id: member_id, role_id: role_id) do
      {:error, reason} ->
        Logger.error(
          "Discord add role failed member_id=#{member_id} role_id=#{role_id} reason=#{inspect(reason)}"
        )

        send(pid, {:discord, {:member_role_added, key, {:error, reason}}})

      _ ->
        send(
          pid,
          {:discord, {:member_role_added, key, {:ok, %{member_id: member_id, role_id: role_id}}}}
        )
    end

    {:noreply, state}
  end

  def handle_cast({:sync_course_roster, pid, key, term_code, crn, jwt_token}, state) do
    Task.start(fn -> sync_course_roster_async(pid, key, term_code, crn, jwt_token) end)
    {:noreply, state}
  end

  def handle_cast({:sync_all, pid}, state) do
    Task.start(fn -> sync_all_async(pid) end)
    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.debug("DiscordDomainManager ignored message=#{inspect(message)}")
    {:noreply, state}
  end

  defp sync_all_async(pid) do
    sync_results =
      [
        {:guild, fn -> sync_guild() end},
        {:bot_user, fn -> sync_bot_user() end},
        {:members, fn -> sync_members() end},
        {:channels, fn -> sync_channels() end},
        {:roles, fn -> sync_roles() end},
        {:invites, fn -> sync_invites() end}
      ]
      |> Task.async_stream(
        fn {resource, sync_function} -> {resource, sync_function.()} end,
        timeout: :infinity,
        max_concurrency: 4
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:task, {:error, reason}}
      end)

    failed_results =
      Enum.filter(sync_results, fn
        {_resource, :ok} -> false
        {_resource, {:error, _reason}} -> true
      end)

    if failed_results == [] do
      case DiscordDb.delete_orphaned_course_channel_assignments() do
        {:error, reason} ->
          Logger.error("Discord orphan assignment cleanup failed reason=#{inspect(reason)}")

          send(
            pid,
            {:discord, {:sync_finished, {:error, ["orphan_cleanup: #{inspect(reason)}"]}}}
          )

        _ ->
          summary = safe_sync_summary()
          DiscordPubSub.broadcast_discord_data_synced(summary)
          send(pid, {:discord, {:sync_finished, {:ok, summary}}})
      end
    else
      reasons =
        Enum.map(failed_results, fn {resource, {:error, reason}} ->
          "#{resource}: #{inspect(reason)}"
        end)

      Logger.error("Discord sync failed reasons=#{Enum.join(reasons, "; ")}")
      send(pid, {:discord, {:sync_finished, {:error, reasons}}})
    end
  end

  defp create_course_channel_async(
         pid: pid,
         key: key,
         crn: crn,
         term_code: term_code,
         channel_name: channel_name,
         parent_id: parent_id,
         discord_role_id: discord_role_id
       ) do
    with {:ok, channel} <-
           discord_api().create_text_channel(name: channel_name, parent_id: parent_id),
         :ok <- DiscordDb.save_channel(channel: channel),
         save_result <-
           DiscordDb.save_course_channel_assignment(
             crn: crn,
             term_code: term_code,
             discord_channel_id: Map.fetch!(channel, "id"),
             discord_role_id: discord_role_id
           ),
         :ok <- normalize_db_result(save_result) do
      summary = safe_sync_summary()
      DiscordPubSub.broadcast_discord_data_synced(summary)

      send(
        pid,
        {:discord,
         {:course_channel_created, key,
          {:ok, %{channel_id: Map.fetch!(channel, "id"), crn: crn, term_code: term_code}}}}
      )
    else
      {:error, reason} ->
        Logger.error(
          "Discord course channel create failed crn=#{crn} term_code=#{term_code} parent_id=#{parent_id} role_id=#{discord_role_id} reason=#{inspect(reason)}"
        )

        send(pid, {:discord, {:course_channel_created, key, {:error, reason}}})

      unexpected ->
        Logger.error(
          "Discord course channel create returned unexpected result=#{inspect(unexpected)}"
        )

        send(pid, {:discord, {:course_channel_created, key, {:error, unexpected}}})
    end
  end

  defp normalize_db_result({:error, reason}), do: {:error, reason}
  defp normalize_db_result(_result), do: :ok

  defp sync_guild do
    with {:ok, guild} <- discord_api().fetch_guild(),
         :ok <- DiscordDb.save_guild(guild: guild) do
      :ok
    end
  end

  defp sync_bot_user do
    with {:ok, bot_user} <- discord_api().fetch_current_user(),
         :ok <- DiscordDb.save_bot_user(bot_user: bot_user) do
      :ok
    end
  end

  defp sync_members do
    with {:ok, members} <- discord_api().fetch_members(),
         :ok <- DiscordDb.save_members(members: members) do
      :ok
    end
  end

  defp sync_channels do
    with {:ok, channels} <- discord_api().fetch_channels(),
         :ok <- DiscordDb.save_channels(channels: channels) do
      :ok
    end
  end

  defp sync_roles do
    with {:ok, roles} <- discord_api().fetch_roles(),
         :ok <- DiscordDb.save_roles(roles: roles) do
      :ok
    end
  end

  defp sync_invites do
    with {:ok, invites} <- discord_api().fetch_invites(),
         :ok <- DiscordDb.save_invites(invites: invites) do
      :ok
    end
  end

  defp sync_course_roster_async(pid, key, term_code, crn, jwt_token) do
    with {:ok, students} <-
           MySnowApi.fetch_section_students(term_code: term_code, crn: crn, jwt_token: jwt_token),
         :ok <-
           SnowCourseCacheDb.save_section_students(
             term_code: term_code,
             crn: crn,
             students: students
           ) do
      assignment = DiscordDb.get_course_channel_assignment_by_crn(crn: crn)

      case assignment do
        {:error, reason} ->
          Logger.error(
            "Discord course roster sync assignment load failed term_code=#{term_code} crn=#{crn} reason=#{inspect(reason)}"
          )

          send(pid, {:discord, {:course_roster_synced, key, {:error, reason}}})

        nil ->
          send(
            pid,
            {:discord,
             {:course_roster_synced, key,
              {:error, "No course-channel assignment found for #{crn}."}}}
          )

        assignment ->
          role_id = assignment["discord_role_id"]
          mappings = safe_student_mappings()
          members = safe_members()

          role_assignment_results =
            Enum.map(students, fn student ->
              badger_id = Map.get(student, "badgerid") || Map.get(student, "badger_id")

              discord_user_id =
                badger_id
                |> mapped_discord_user_id(mappings)

              if is_binary(discord_user_id) do
                if member_present?(members, discord_user_id) do
                  discord_api().add_role_to_member(member_id: discord_user_id, role_id: role_id)
                else
                  {:ok, :member_missing}
                end
              else
                {:ok, :unmapped}
              end
            end)

          failed_role_assignments =
            Enum.with_index(role_assignment_results)
            |> Enum.filter(fn
              {{:error, _reason}, _idx} -> true
              _ -> false
            end)

          if failed_role_assignments == [] do
            send(
              pid,
              {:discord,
               {:course_roster_synced, key,
                {:ok, %{term_code: term_code, crn: crn, student_count: length(students)}}}}
            )
          else
            reasons =
              Enum.map(failed_role_assignments, fn {{:error, reason}, idx} ->
                "student_#{idx + 1}: #{inspect(reason)}"
              end)

            Logger.error(
              "Discord course roster sync role assignment failed term_code=#{term_code} crn=#{crn} reasons=#{Enum.join(reasons, "; ")}"
            )

            send(
              pid,
              {:discord,
               {:course_roster_synced, key,
                {:error, %{term_code: term_code, crn: crn, reason: reasons}}}}
            )
          end
      end
    else
      {:error, reason} ->
        Logger.error(
          "Discord course roster sync failed term_code=#{term_code} crn=#{crn} reason=#{inspect(reason)}"
        )

        send(pid, {:discord, {:course_roster_synced, key, {:error, reason}}})
    end
  end

  defp safe_student_mappings do
    case DiscordDb.list_student_discord_mappings() do
      {:error, reason} ->
        Logger.error("Discord student mappings load failed reason=#{inspect(reason)}")
        []

      mappings ->
        mappings
    end
  end

  defp safe_members do
    case DiscordDb.list_members() do
      {:error, reason} ->
        Logger.error("Discord members load failed while syncing roster reason=#{inspect(reason)}")
        []

      members ->
        members
    end
  end

  defp mapped_discord_user_id(badger_id, mappings) when is_binary(badger_id) do
    mappings
    |> Enum.find_value(fn mapping ->
      if mapping["badger_id"] == badger_id do
        mapping["discord_user_id"]
      end
    end)
  end

  defp mapped_discord_user_id(_badger_id, _mappings), do: nil

  defp member_present?(members, discord_user_id) do
    Enum.any?(members, fn member ->
      member["id"] == discord_user_id
    end)
  end

  defp safe_sync_summary do
    case DiscordDb.sync_summary() do
      {:error, reason} ->
        Logger.error("Discord summary load failed reason=#{inspect(reason)}")
        []

      summary ->
        summary
    end
  end

  defp send_db_result(pid: pid, message: {event, key}, fetch: fetch, error_context: error_context) do
    case fetch.() do
      {:error, reason} ->
        Logger.error("#{error_context} reason=#{inspect(reason)}")
        send(pid, {:discord, {event, key, {:error, reason}}})

      data ->
        send(pid, {:discord, {event, key, {:ok, data}}})
    end
  end

  defp discord_api do
    Application.get_env(:snow_se_tools, :discord_api_module, DiscordApi)
  end
end
