defmodule SnowSeTools.Scheduling.ScheduleOwnerDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.AcademicPrograms.{AcademicProgramPubSub, ProgramDb}
  alias SnowSeTools.Snow.SnowCourseCacheDb
  alias SnowSeTools.Snow.SnowCourseCachePubSub
  alias SnowSeTools.Scheduling.ScheduleOwnerMetadata
  alias SnowSeTools.Scheduling.ScheduleOwnerPubSub
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
    GenServer.cast(__MODULE__, {:request_schedule_owner_detail, pid, term_code, owner_key})
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
    {schedules_by_owner, state} =
      case Map.fetch(state.schedules_by_owner_by_term, term_code) do
        {:ok, schedules_by_owner} ->
          {schedules_by_owner, state}

        :error ->
          schedules_by_owner =
            case SnowCourseCacheDb.list_course_data_for_term(term_code: term_code) do
              {:ok, courses} ->
                courses
                |> ScheduleOwnerSchedule.build_entries(state.academic_programs)
                |> Map.new(&{&1.owner_key, &1})

              {:error, reason} ->
                Logger.error(
                  "ScheduleOwnerDomainManager failed to load schedule details for term=#{term_code}: #{inspect(reason)}"
                )

                %{}
            end

          {schedules_by_owner,
           Map.put(
             state,
             :schedules_by_owner_by_term,
             Map.put(state.schedules_by_owner_by_term, term_code, schedules_by_owner)
           )}
      end

    case Map.get(schedules_by_owner, owner_key) do
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

  def handle_info({:academic_programs, {:program_created, program}}, state) do
    state = Map.put(state, :academic_programs, upsert_program(state.academic_programs, program))

    state =
      Enum.reduce(cached_term_codes(state), state, fn term_code, acc ->
        metadata_for_program = program_metadata(program: program)

        Enum.each(metadata_for_program, fn metadata ->
          ScheduleOwnerPubSub.broadcast_schedule_owner_metadata_upserted(term_code, metadata)
        end)

        update_in(
          acc,
          [Access.key(:schedule_owner_metadata_by_term), Access.key(term_code, [])],
          fn existing ->
            existing
            |> Enum.reject(&(&1.academic_program_id == program["id"]))
            |> Kernel.++(metadata_for_program)
            |> Enum.uniq_by(& &1.key)
          end
        )
        |> then(fn updated_acc ->
          if Map.has_key?(updated_acc.schedules_by_owner_by_term, term_code) do
            program_schedules = program_schedules(term_code: term_code, program: program)

            Enum.each(program_schedules, fn schedule ->
              ScheduleOwnerPubSub.broadcast_schedule_owner_detail_changed(
                term_code,
                schedule.owner_key,
                schedule
              )
            end)

            update_in(
              updated_acc,
              [Access.key(:schedules_by_owner_by_term), Access.key(term_code, %{})],
              fn schedules_by_owner ->
                Enum.reduce(program_schedules, schedules_by_owner, fn schedule, owner_acc ->
                  Map.put(owner_acc, schedule.owner_key, schedule)
                end)
              end
            )
          else
            updated_acc
          end
        end)
      end)

    {:noreply, state}
  end

  def handle_info({:academic_programs, {:program_updated, program}}, state) do
    previous_program = Enum.find(state.academic_programs, &(&1["id"] == program["id"]))
    state = Map.put(state, :academic_programs, upsert_program(state.academic_programs, program))

    state =
      Enum.reduce(cached_term_codes(state), state, fn term_code, acc ->
        previous_owner_keys =
          (previous_program || program)
          |> Map.get("semesters", [])
          |> Enum.map(
            &program_semester_owner_key(program_id: program["id"], semester_id: &1["id"])
          )

        metadata_for_program = program_metadata(program: program)

        new_owner_keys = MapSet.new(metadata_for_program, & &1.key)

        previous_owner_keys
        |> Enum.reject(&MapSet.member?(new_owner_keys, &1))
        |> Enum.each(fn owner_key ->
          ScheduleOwnerPubSub.broadcast_schedule_owner_metadata_deleted(term_code, owner_key)
          ScheduleOwnerPubSub.broadcast_schedule_owner_detail_changed(term_code, owner_key, nil)
        end)

        Enum.each(metadata_for_program, fn metadata ->
          ScheduleOwnerPubSub.broadcast_schedule_owner_metadata_upserted(term_code, metadata)
        end)

        acc
        |> update_in(
          [Access.key(:schedule_owner_metadata_by_term), Access.key(term_code, [])],
          fn existing ->
            existing
            |> Enum.reject(&(&1.academic_program_id == program["id"]))
            |> Kernel.++(metadata_for_program)
            |> Enum.uniq_by(& &1.key)
          end
        )
        |> update_in(
          [Access.key(:schedules_by_owner_by_term), Access.key(term_code, %{})],
          fn schedules_by_owner ->
            previous_owner_keys
            |> Enum.reduce(schedules_by_owner, &Map.delete(&2, &1))
          end
        )
        |> then(fn updated_acc ->
          if Map.has_key?(updated_acc.schedules_by_owner_by_term, term_code) do
            program_schedules = program_schedules(term_code: term_code, program: program)

            Enum.each(program_schedules, fn schedule ->
              ScheduleOwnerPubSub.broadcast_schedule_owner_detail_changed(
                term_code,
                schedule.owner_key,
                schedule
              )
            end)

            update_in(
              updated_acc,
              [Access.key(:schedules_by_owner_by_term), Access.key(term_code, %{})],
              fn schedules_by_owner ->
                Enum.reduce(program_schedules, schedules_by_owner, fn schedule, owner_acc ->
                  Map.put(owner_acc, schedule.owner_key, schedule)
                end)
              end
            )
          else
            updated_acc
          end
        end)
      end)

    {:noreply, state}
  end

  def handle_info({:academic_programs, {:program_deleted, program_id}}, state) do
    academic_programs = Enum.reject(state.academic_programs, &(&1["id"] == program_id))
    state = Map.put(state, :academic_programs, academic_programs)

    state =
      Enum.reduce(cached_term_codes(state), state, fn term_code, acc ->
        metadata_owner_keys =
          acc.schedule_owner_metadata_by_term
          |> Map.get(term_code, [])
          |> Enum.filter(&(&1.academic_program_id == program_id))
          |> Enum.map(& &1.key)

        schedule_owner_keys =
          acc.schedules_by_owner_by_term
          |> Map.get(term_code, %{})
          |> Enum.filter(fn {_owner_key, schedule} ->
            schedule.type == :academic_program_semester and
              String.starts_with?(schedule.owner_key, "academic_program_semester:#{program_id}:")
          end)
          |> Enum.map(fn {owner_key, _schedule} -> owner_key end)

        owner_keys = Enum.uniq(metadata_owner_keys ++ schedule_owner_keys)

        Enum.each(owner_keys, fn owner_key ->
          ScheduleOwnerPubSub.broadcast_schedule_owner_metadata_deleted(term_code, owner_key)
          ScheduleOwnerPubSub.broadcast_schedule_owner_detail_changed(term_code, owner_key, nil)
        end)

        acc
        |> update_in(
          [Access.key(:schedule_owner_metadata_by_term), Access.key(term_code, [])],
          &Enum.reject(&1, fn metadata -> metadata.academic_program_id == program_id end)
        )
        |> update_in(
          [Access.key(:schedules_by_owner_by_term), Access.key(term_code, %{})],
          fn schedules_by_owner ->
            Enum.reduce(owner_keys, schedules_by_owner, &Map.delete(&2, &1))
          end
        )
      end)

    {:noreply, state}
  end

  def handle_info(
        {:snow_course_cache,
         {:course_cache_updated, %{term_code: term_code, term_name: term_name}}},
        state
      ) do
    term_exists? = Enum.any?(state.terms, &(&1["term_code"] == term_code))

    terms =
      if term_exists? do
        Enum.map(state.terms, fn term ->
          if term["term_code"] == term_code do
            Map.put(term, "term_name", term_name)
          else
            term
          end
        end)
      else
        [
          %{
            "term_code" => term_code,
            "term_name" => term_name,
            "cached_at" => "",
            "course_count" => 0,
            "roster_count" => 0
          }
          | state.terms
        ]
        |> Enum.sort_by(& &1["term_code"], :desc)
      end

    state = Map.put(state, :terms, terms)
    ScheduleOwnerPubSub.broadcast_terms_changed(state.terms)

    state =
      if Map.has_key?(state.schedule_owner_metadata_by_term, term_code) do
        schedule_owners = build_schedule_owners_metadata_for_term(term_code, state)

        ScheduleOwnerPubSub.broadcast_term_schedule_owners_replaced(term_code, schedule_owners)

        Map.put(
          state,
          :schedule_owner_metadata_by_term,
          Map.put(state.schedule_owner_metadata_by_term, term_code, schedule_owners)
        )
      else
        state
      end

    state =
      if Map.has_key?(state.schedules_by_owner_by_term, term_code) do
        previous_owner_keys =
          state.schedules_by_owner_by_term
          |> Map.get(term_code, %{})
          |> Map.keys()
          |> MapSet.new()

        schedules_by_owner =
          case SnowCourseCacheDb.list_course_data_for_term(term_code: term_code) do
            {:ok, courses} ->
              courses
              |> ScheduleOwnerSchedule.build_entries(state.academic_programs)
              |> Map.new(&{&1.owner_key, &1})

            {:error, reason} ->
              Logger.error(
                "ScheduleOwnerDomainManager failed to refresh schedule details for term=#{term_code}: #{inspect(reason)}"
              )

              %{}
          end

        current_owner_keys =
          schedules_by_owner
          |> Map.keys()
          |> MapSet.new()

        previous_owner_keys
        |> MapSet.difference(current_owner_keys)
        |> Enum.each(fn owner_key ->
          ScheduleOwnerPubSub.broadcast_schedule_owner_detail_changed(term_code, owner_key, nil)
        end)

        Enum.each(schedules_by_owner, fn {owner_key, detail} ->
          ScheduleOwnerPubSub.broadcast_schedule_owner_detail_changed(
            term_code,
            owner_key,
            detail
          )
        end)

        Map.put(
          state,
          :schedules_by_owner_by_term,
          Map.put(state.schedules_by_owner_by_term, term_code, schedules_by_owner)
        )
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:snow_course_cache, {:course_cache_deleted, term_code}}, state) do
    state =
      state
      |> Map.put(:terms, Enum.reject(state.terms, &(&1["term_code"] == term_code)))
      |> update_in([Access.key(:schedule_owner_metadata_by_term)], &Map.delete(&1, term_code))
      |> update_in([Access.key(:schedules_by_owner_by_term)], &Map.delete(&1, term_code))

    ScheduleOwnerPubSub.broadcast_terms_changed(state.terms)
    ScheduleOwnerPubSub.broadcast_term_deleted(term_code)
    {:noreply, state}
  end

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

  defp upsert_program(programs, program) do
    [program | Enum.reject(programs, &(&1["id"] == program["id"]))]
    |> Enum.sort_by(&String.downcase(&1["name"] || ""))
  end

  defp cached_term_codes(state) do
    state.schedule_owner_metadata_by_term
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Map.keys(state.schedules_by_owner_by_term)))
  end

  defp program_metadata(program: program) do
    program
    |> Map.get("semesters", [])
    |> Enum.with_index()
    |> Enum.map(fn {semester, semester_index} ->
      %ScheduleOwnerMetadata{
        type: :academic_program_semester,
        name: "#{program["name"]} #{ScheduleOwnerSchedule.semester_label(semester_index)}",
        academic_program_id: program["id"],
        academic_program_semester: semester["id"],
        key: program_semester_owner_key(program_id: program["id"], semester_id: semester["id"])
      }
    end)
  end

  defp program_schedules(term_code: term_code, program: program) do
    case SnowCourseCacheDb.list_course_data_for_term(term_code: term_code) do
      {:ok, courses} ->
        program
        |> Map.get("semesters", [])
        |> Enum.with_index()
        |> Enum.map(fn {semester, semester_index} ->
          ScheduleOwnerSchedule.new_academic_program_semester(
            program,
            semester,
            semester_index,
            courses
          )
        end)

      {:error, reason} ->
        Logger.error(
          "ScheduleOwnerDomainManager failed to load courses for program schedule update term=#{term_code} program=#{program["id"]}: #{inspect(reason)}"
        )

        []
    end
  end

  defp program_semester_owner_key(program_id: program_id, semester_id: semester_id) do
    "academic_program_semester:#{program_id}:#{semester_id}"
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
            key:
              program_semester_owner_key(program_id: program["id"], semester_id: semester["id"])
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
          Enum.flat_map(course["meet_info"] || [], fn meeting ->
            room_name = ScheduleOwnerSchedule.room_name(meeting: meeting)

            if is_nil(room_name) do
              []
            else
              [
                %ScheduleOwnerMetadata{
                  type: :room,
                  name: room_name,
                  key: "room:#{room_name}",
                  academic_program_id: nil,
                  academic_program_semester: nil
                }
              ]
            end
          end)
      end)
      |> Enum.uniq()

    professor_and_room_metadata ++ academic_program_metadata
  end
end
