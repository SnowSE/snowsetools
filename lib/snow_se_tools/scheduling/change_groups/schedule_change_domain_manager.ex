defmodule SnowSeTools.Scheduling.ScheduleChangeDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.Scheduling.{
    ScheduleChangeDb,
    ScheduleChangePubSub,
    ScheduleConflictDetector,
    ScheduleOwnerDomainManager,
    ScheduleUtils
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def create_group(name) do
    GenServer.cast(__MODULE__, {:create_group, name})
  end

  def delete_group(group_id) do
    GenServer.cast(__MODULE__, {:delete_group, group_id})
  end

  def rename_group(group_id, new_name) do
    GenServer.cast(__MODULE__, {:rename_group, group_id, new_name})
  end

  def add_or_update_change(group_id, change_attrs) do
    GenServer.cast(__MODULE__, {:add_or_update_change, group_id, change_attrs})
  end

  def remove_change(change_id) do
    GenServer.cast(__MODULE__, {:remove_change, change_id})
  end

  def list_groups(pid: pid) do
    GenServer.cast(__MODULE__, {:list_groups, pid})
  end

  def list_changes(pid: pid, group_id: group_id) do
    GenServer.cast(__MODULE__, {:list_changes, pid, group_id})
  end

  def init(:ok) do
    case ScheduleChangeDb.bootstrap_tables() do
      :ok ->
        groups = load_groups()
        changes_by_group = load_changes_by_group(groups)
        conflict_check_status_by_group = initial_conflict_check_statuses(changes_by_group)

        Enum.each(changes_by_group, fn {group_id, changes} ->
          if changes != [] do
            send(self(), {:start_conflict_check, group_id})
          end
        end)

        {:ok,
         %{
           groups: groups,
           changes_by_group: changes_by_group,
           conflicts_by_change_id_by_group: %{},
           conflict_check_status_by_group: conflict_check_status_by_group,
           conflict_check_error_by_group: %{}
         }}

      {:error, reason} ->
        Logger.error("Schedule change bootstrap failed reason=#{inspect(reason)}")
        {:stop, reason}
    end
  end

  def handle_cast({:create_group, name}, state) do
    case ScheduleChangeDb.create_group(name) do
      {:ok, group} ->
        ScheduleChangePubSub.broadcast_group_created(group)
        {:noreply, %{state | groups: [group | state.groups]}}

      {:error, reason} ->
        Logger.error("Failed to create schedule change group: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:delete_group, group_id}, state) do
    case ScheduleChangeDb.delete_group(group_id) do
      :ok ->
        ScheduleChangePubSub.broadcast_group_deleted(group_id)

        {:noreply,
         %{
           state
           | groups: Enum.reject(state.groups, &(&1["id"] == group_id)),
             changes_by_group: Map.delete(state.changes_by_group, group_id),
             conflicts_by_change_id_by_group:
               Map.delete(state.conflicts_by_change_id_by_group, group_id),
             conflict_check_status_by_group:
               Map.delete(state.conflict_check_status_by_group, group_id),
             conflict_check_error_by_group:
               Map.delete(state.conflict_check_error_by_group, group_id)
         }}

      {:error, reason} ->
        Logger.error("Failed to delete schedule change group: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:rename_group, group_id, new_name}, state) do
    case ScheduleChangeDb.rename_group(group_id, new_name) do
      {:ok, group} ->
        ScheduleChangePubSub.broadcast_group_updated(group)

        {:noreply,
         %{
           state
           | groups:
               Enum.map(state.groups, fn g ->
                 if g["id"] == group_id, do: group, else: g
               end)
         }}

      {:error, reason} ->
        Logger.error("Failed to rename schedule change group: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:add_or_update_change, group_id, change_attrs}, state) do
    case change_returns_to_original(change_attrs: change_attrs) do
      true ->
        remove_existing_change_for_attrs(
          group_id: group_id,
          change_attrs: change_attrs,
          state: state
        )

      false ->
        add_or_update_changed_course(group_id: group_id, change_attrs: change_attrs, state: state)
    end
  end

  def handle_cast({:remove_change, change_id}, state) do
    case ScheduleChangeDb.remove_change(change_id) do
      :ok ->
        group_id = find_change_group_id(state, change_id)

        if group_id do
          ScheduleChangePubSub.broadcast_change_removed(group_id, change_id)

          changes = Map.get(state.changes_by_group, group_id, [])
          updated_changes = Enum.reject(changes, &(&1["id"] == change_id))

          updated_state =
            state
            |> put_in([:changes_by_group, group_id], updated_changes)
            |> schedule_conflict_check(group_id: group_id)

          {:noreply, updated_state}
        else
          ScheduleChangePubSub.broadcast_change_removed(nil, change_id)
          {:noreply, state}
        end

      {:error, reason} ->
        Logger.error("Failed to remove schedule change: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:list_groups, pid}, state) do
    send(pid, {:schedule_change_groups, groups_with_changes(state)})
    {:noreply, state}
  end

  def handle_cast({:list_changes, pid, group_id}, state) do
    changes = changes_with_conflicts(group_id: group_id, state: state)
    send(pid, {:schedule_change_changes, group_id, changes})
    {:noreply, state}
  end

  def handle_info({:start_conflict_check, group_id}, state) do
    start_conflict_check_task(group_id: group_id, state: state)
    {:noreply, state}
  end

  def handle_info({:conflict_check_complete, group_id, {:ok, conflicts_by_change_id}}, state) do
    updated_state =
      state
      |> put_in([:conflicts_by_change_id_by_group, group_id], conflicts_by_change_id)
      |> put_in([:conflict_check_status_by_group, group_id], :not_checking)
      |> update_in([:conflict_check_error_by_group], &Map.delete(&1, group_id))

    ScheduleChangePubSub.broadcast_conflict_check_updated(group_id)
    {:noreply, updated_state}
  end

  def handle_info({:conflict_check_complete, group_id, {:error, reason}}, state) do
    Logger.error("Schedule conflict check failed for group #{group_id}: #{inspect(reason)}")

    updated_state =
      state
      |> put_in([:conflict_check_status_by_group, group_id], :error)
      |> put_in([:conflict_check_error_by_group, group_id], inspect(reason))

    ScheduleChangePubSub.broadcast_conflict_check_updated(group_id)
    {:noreply, updated_state}
  end

  defp add_or_update_changed_course(group_id: group_id, change_attrs: change_attrs, state: state) do
    case ScheduleChangeDb.add_or_update_change(group_id, change_attrs) do
      {:ok, change} ->
        changes = Map.get(state.changes_by_group, group_id, [])
        updated_changes = upsert_change(changes, change)

        updated_state =
          state
          |> put_in([:changes_by_group, group_id], updated_changes)
          |> schedule_conflict_check(group_id: group_id)

        ScheduleChangePubSub.broadcast_change_updated(group_id, change)

        {:noreply, updated_state}

      {:error, reason} ->
        Logger.error("Failed to add/update schedule change: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp remove_existing_change_for_attrs(
         group_id: group_id,
         change_attrs: change_attrs,
         state: state
       ) do
    case find_change_by_group_crn(state: state, group_id: group_id, crn: change_attrs["crn"]) do
      nil ->
        {:noreply, state}

      %{"id" => change_id} ->
        case ScheduleChangeDb.remove_change(change_id) do
          :ok ->
            ScheduleChangePubSub.broadcast_change_removed(group_id, change_id)

            updated_changes =
              state.changes_by_group
              |> Map.get(group_id, [])
              |> Enum.reject(&(&1["id"] == change_id))

            updated_state =
              state
              |> put_in([:changes_by_group, group_id], updated_changes)
              |> schedule_conflict_check(group_id: group_id)

            {:noreply, updated_state}

          {:error, reason} ->
            Logger.error("Failed to remove reverted schedule change: #{inspect(reason)}")
            {:noreply, state}
        end
    end
  end

  defp load_groups do
    case ScheduleChangeDb.list_groups() do
      {:ok, groups} ->
        groups

      {:error, reason} ->
        Logger.error("Failed to load groups: #{inspect(reason)}")
        []
    end
  end

  defp load_changes_by_group(groups) do
    Enum.reduce(groups, %{}, fn group, acc ->
      group_id = group["id"]

      case ScheduleChangeDb.list_changes_for_group(group_id) do
        {:ok, changes} ->
          Map.put(acc, group_id, changes)

        {:error, reason} ->
          Logger.error("Failed to load changes for group #{group_id}: #{inspect(reason)}")
          acc
      end
    end)
  end

  defp initial_conflict_check_statuses(changes_by_group) do
    Map.new(changes_by_group, fn {group_id, changes} ->
      status = if changes == [], do: :not_checking, else: :checking
      {group_id, status}
    end)
  end

  defp upsert_change(changes, %{"id" => id} = change) do
    idx = Enum.find_index(changes, &(&1["id"] == id))

    if idx do
      List.replace_at(changes, idx, change)
    else
      [change | changes]
    end
  end

  defp find_change_group_id(state, change_id) do
    Enum.find_value(state.changes_by_group, fn {group_id, changes} ->
      if Enum.any?(changes, &(&1["id"] == change_id)), do: group_id
    end)
  end

  defp find_change_by_group_crn(state: state, group_id: group_id, crn: crn) do
    state.changes_by_group
    |> Map.get(group_id, [])
    |> Enum.find(&(&1["crn"] == crn))
  end

  defp groups_with_changes(state) do
    Enum.map(state.groups, fn group ->
      group_id = group["id"]

      group
      |> Map.put("changes", changes_with_conflicts(group_id: group_id, state: state))
      |> Map.put(
        "conflict_check_status",
        Map.get(state.conflict_check_status_by_group, group_id, :not_checking)
      )
      |> Map.put("conflict_check_error", Map.get(state.conflict_check_error_by_group, group_id))
    end)
  end

  defp changes_with_conflicts(group_id: group_id, state: state) do
    conflicts_by_change_id = Map.get(state.conflicts_by_change_id_by_group, group_id, %{})

    state.changes_by_group
    |> Map.get(group_id, [])
    |> Enum.map(fn change ->
      Map.put(change, "conflicts", Map.get(conflicts_by_change_id, change["id"], []))
    end)
  end

  defp conflicts_by_change_id_for_changes(changes) do
    changes
    |> Enum.group_by(& &1["term"])
    |> Enum.reduce_while({:ok, %{}}, fn {term_code, term_changes}, {:ok, acc} ->
      case owner_course_lists_for_term(term_code: term_code) do
        {:ok, owner_course_lists} ->
          result =
            ScheduleConflictDetector.detect_term_conflicts(
              owner_course_lists: owner_course_lists,
              active_changes: term_changes
            )

          {:cont, {:ok, Map.merge(acc, result.conflicts_by_change_id)}}

        {:error, reason} ->
          {:halt, {:error, {:owner_course_lists_failed, term_code, reason}}}
      end
    end)
  end

  defp schedule_conflict_check(state, group_id: group_id) do
    updated_state =
      state
      |> put_in([:conflict_check_status_by_group, group_id], :checking)
      |> update_in([:conflict_check_error_by_group], &Map.delete(&1, group_id))

    ScheduleChangePubSub.broadcast_conflict_check_updated(group_id)
    send(self(), {:start_conflict_check, group_id})
    updated_state
  end

  defp start_conflict_check_task(group_id: group_id, state: state) do
    changes = Map.get(state.changes_by_group, group_id, [])
    manager = self()

    Task.start(fn ->
      result =
        try do
          conflicts_by_change_id_for_changes(changes)
        rescue
          error -> {:error, {:exception, error, __STACKTRACE__}}
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      send(manager, {:conflict_check_complete, group_id, result})
    end)
  end

  defp owner_course_lists_for_term(term_code: term_code) do
    ScheduleOwnerDomainManager.get_term_owner_course_lists(term_code: term_code)
  catch
    :exit, reason -> {:error, reason}
  end

  defp change_returns_to_original(change_attrs: %{"operation" => "update"} = change_attrs) do
    with false <- change_attrs["course_name"] == "__DELETED__",
         term_code when is_binary(term_code) <- change_attrs["term"],
         crn when is_binary(crn) <- change_attrs["crn"],
         {:ok, owner_course_lists} <- owner_course_lists_for_term(term_code: term_code),
         %{} = original_course <-
           original_course(owner_course_lists: owner_course_lists, crn: crn) do
      original_meetings_match?(change_attrs: change_attrs, original_course: original_course) and
        original_professor_matches?(change_attrs: change_attrs, original_course: original_course)
    else
      {:error, reason} ->
        Logger.error(
          "Failed to load original course for reverted change detection: #{inspect(reason)}"
        )

        false

      _other ->
        false
    end
  end

  defp change_returns_to_original(change_attrs: _change_attrs), do: false

  defp original_course(owner_course_lists: owner_course_lists, crn: crn) do
    owner_course_lists
    |> Enum.flat_map(&courses_for_owner/1)
    |> Enum.find(&(&1["crn"] == crn))
  end

  defp courses_for_owner(%{courses: courses}) when is_list(courses), do: courses
  defp courses_for_owner(%{"courses" => courses}) when is_list(courses), do: courses
  defp courses_for_owner(_owner), do: []

  defp original_meetings_match?(change_attrs: change_attrs, original_course: original_course) do
    changed_meetings = change_attrs["meet_info"] || original_course["meet_info"] || []
    original_meetings = original_course["meet_info"] || []

    normalize_meetings(changed_meetings) == normalize_meetings(original_meetings)
  end

  defp normalize_meetings(meetings) do
    meetings
    |> Enum.map(fn meeting ->
      %{
        days: meeting |> Map.get("days", []) |> Enum.sort(),
        start_minutes: time_minutes(meeting["start_time"]),
        end_minutes: time_minutes(meeting["end_time"]),
        room: ScheduleUtils.room_name(meeting: meeting)
      }
    end)
    |> Enum.sort_by(&{&1.days, &1.start_minutes, &1.end_minutes, &1.room || ""})
  end

  defp original_professor_matches?(change_attrs: change_attrs, original_course: original_course) do
    changed_professor =
      changed_professor(change_attrs: change_attrs, original_course: original_course)

    changed_professor == first_professor(original_course)
  end

  defp changed_professor(
         change_attrs: %{"target_professor" => professor},
         original_course: _course
       )
       when is_binary(professor) and professor != "" do
    professor
  end

  defp changed_professor(change_attrs: _change_attrs, original_course: original_course) do
    first_professor(original_course)
  end

  defp first_professor(course) do
    course
    |> Map.get("instructors", [])
    |> List.wrap()
    |> Enum.find_value("", fn
      %{"name" => name} when is_binary(name) -> name
      _instructor -> nil
    end)
  end

  defp time_minutes(<<hour::binary-size(2), ":", minute::binary-size(2), _rest::binary>>) do
    with {hour, ""} <- Integer.parse(hour),
         {minute, ""} <- Integer.parse(minute) do
      hour * 60 + minute
    else
      _other -> nil
    end
  end

  defp time_minutes(_time), do: nil
end
