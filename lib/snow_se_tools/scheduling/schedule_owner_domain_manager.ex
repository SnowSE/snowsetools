defmodule SnowSeTools.Scheduling.ScheduleOwnerDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.AcademicPrograms.{AcademicProgramPubSub, ProgramDb}
  alias SnowSeTools.Snow.SnowCourseCacheDb
  alias SnowSeTools.Snow.SnowCourseCachePubSub
  alias SnowSeTools.Scheduling.ScheduleOwnerMetadata
  alias SnowSeTools.Scheduling.ScheduleOwnerSchedule

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def request_terms(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_terms, pid})
  end

  def request_schedule_owners_metadata(pid: pid, term_code: term_code)
      when is_pid(pid) and is_binary(term_code) do
    GenServer.cast(__MODULE__, {:request_schedule_owners_metadata, pid, term_code})
  end

  def request_schedule_owner_detail(pid: pid, term_code: term_code, owner_key: owner_key)
      when is_pid(pid) and is_binary(term_code) and is_binary(owner_key) do
    # GenServer.cast(__MODULE__, {:request_schedule_owner_detail, pid, term_code, owner_key})
  end

  def init(:ok) do
    academic_programs = load_academic_programs()

    SnowCourseCachePubSub.subscribe()
    AcademicProgramPubSub.subscribe()

    {:ok,
     %{
       terms: load_terms(),
       schedule_owner_metadata_by_term: %{},
       schedules_by_owner_by_term: %{},
       academic_programs: academic_programs
     }}
  end

  def handle_cast({:request_terms, pid}, state) do
    send(pid, {:schedule_owner_terms, state.terms})
    {:noreply, state}
  end

  def handle_cast({:request_schedule_owners_metadata, pid, term_code}, state) do
    metadata_by_term = state.schedule_owner_metadata_by_term

    schedule_owners =
      case Map.has_key?(metadata_by_term, term_code) do
        true ->
          metadata_by_term[term_code]

        false ->
          build_schedule_owners_metadata_for_term(term_code, state)
      end

    send(pid, {:schedule_owners, %{term_code: term_code, schedule_owners: schedule_owners}})

    updated_metadata_by_term = Map.put(metadata_by_term, term_code, schedule_owners)

    {:noreply,
     state
     |> Map.put(
       :schedule_owner_metadata_by_term,
       updated_metadata_by_term
     )}
  end

  def handle_cast({:request_schedule_owner_detail, pid, term_code, owner_key}, state) do
    schedule_owners = state.schedule_owners_by_term[term_code] || []

    case Enum.find(schedule_owners, &(&1.owner_key == owner_key)) do
      nil ->
        send(
          pid,
          {:schedule_owner_detail, %{term_code: term_code, owner_key: owner_key, detail: nil}}
        )

      detail ->
        send(
          pid,
          {:schedule_owner_detail, %{term_code: term_code, owner_key: owner_key, detail: detail}}
        )
    end

    {:noreply, state}
  end

  # def handle_info({:academic_programs, {:program_created, _program}}, state) do
  #   state = update_academic_programs(state)
  #   rebuild_cached_terms_and_broadcast(state)
  # end

  # def handle_info({:academic_programs, {:program_updated, _program}}, state) do
  #   state = update_academic_programs(state)
  #   rebuild_cached_terms_and_broadcast(state)
  # end

  # def handle_info({:academic_programs, {:program_deleted, _program_id}}, state) do
  #   state = update_academic_programs(state)
  #   rebuild_cached_terms_and_broadcast(state)
  # end

  # def handle_info(
  #       {:snow_course_cache,
  #        {:course_cache_updated, %{term_code: term_code, term_name: term_name}}},
  #       state
  #     ) do
  #   state = upsert_term_summary(state, term_code: term_code, term_name: term_name)
  #   ScheduleOwnerPubSub.broadcast_terms_changed(state.terms)
  #   {:noreply, rebuild_cached_term_and_broadcast(state, term_code: term_code)}
  # end

  # def handle_info({:snow_course_cache, {:course_cache_deleted, term_code}}, state) do
  #   state =
  #     state
  #     |> delete_term_summary(term_code)
  #     |> update_in([Access.key(:schedule_owners_by_term)], &Map.delete(&1, term_code))

  #   ScheduleOwnerPubSub.broadcast_terms_changed(state.terms)
  #   ScheduleOwnerPubSub.broadcast_term_deleted(term_code)
  #   {:noreply, state}
  # end

  def handle_info(msg, state) do
    Logger.debug("ScheduleOwnerDomainManager ignored message=#{inspect(msg)}")
    {:noreply, state}
  end

  defp load_academic_programs do
    case ProgramDb.list_programs() do
      {:ok, programs} ->
        programs

      {:error, reason} ->
        Logger.error(
          "ScheduleOwnerDomainManager failed to load academic programs: #{inspect(reason)}"
        )

        []
    end
  end

  defp load_terms do
    case SnowCourseCacheDb.list_terms_with_courses() do
      {:error, reason} ->
        Logger.error("ScheduleOwnerDomainManager failed to load terms: #{inspect(reason)}")
        []

      terms ->
        terms
    end
  end

  defp build_schedule_owners_metadata_for_term(term_code, state) do
    courses =
      case SnowCourseCacheDb.list_course_data_for_term(term_code: term_code) do
        {:ok, courses} ->
          courses

        {:error, reason} ->
          Logger.error(
            "ScheduleOwnerDomainManager failed to load courses for term=#{term_code}: #{inspect(reason)}"
          )

          []
      end

    academic_program_metadata =
      Enum.flat_map(state.academic_programs, fn program ->
        (program["semesters"] || [])
        |> Enum.with_index()
        |> Enum.map(fn {semester, semester_index} ->
          %ScheduleOwnerMetadata{
            type: :academic_program_semester,
            name: "#{program["name"]} #{ScheduleOwnerSchedule.semester_label(semester_index)}",
            academic_program_id: program["id"],
            academic_program_semester: semester["id"],
            key: "academic_program_semester:#{program["id"]}:#{semester["id"]}"
          }
        end)
      end)

    professor_and_room_metadata =
      courses
      |> Enum.flat_map(fn course ->
        Enum.map(course["instructors"] || [], fn instructor ->
          %ScheduleOwnerMetadata{
            type: :professor,
            name: instructor["name"],
            key: "professor:#{instructor["name"]}",
            academic_program_id: nil,
            academic_program_semester: nil
          }
        end) ++
          Enum.map(course["meet_info"] || [], fn meeting ->
            %ScheduleOwnerMetadata{
              type: :room,
              name: meeting["__room_name"],
              key: "room:#{meeting["__room_name"]}",
              academic_program_id: nil,
              academic_program_semester: nil
            }
          end)
      end)
      |> Enum.uniq()

    professor_and_room_metadata ++ academic_program_metadata
  end
end
