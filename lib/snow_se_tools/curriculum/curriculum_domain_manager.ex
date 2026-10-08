defmodule SnowSeTools.Curriculum.CurriculumDomainManager do
  @moduledoc """
  The one writer for the curriculum map, and the conductor of review runs.

  Edits arrive as casts carrying the caller's pid; the caller gets
  `{:curriculum, {:action_result, {:ok, message} | {:error, reason}}}` back and
  every viewer gets `{:curriculum, :changed}` over PubSub.

  A review run walks the courses of one academic program:

    1. read each course's master syllabus from snow.edu and mirror its
       outcomes (a `:syllabi_only` run stops here);
    2. ask the model, one completion per course, which skills the course
       teaches, using the master syllabus, the faculty repository and the
       section syllabi as evidence;
    3. ask once more whether any of the proposed skills duplicate each other
       or the catalog.

  Steps 2 and 3 go through `AsyncCompletions`, which limits how many requests
  reach the model at once; their answers come back here as PubSub messages.
  """

  use GenServer
  require Logger

  alias SnowSeTools.AcademicPrograms.ProgramDb
  alias SnowSeTools.AI.AsyncCompletions

  alias SnowSeTools.Curriculum.{
    AbetDb,
    AbetMatrix,
    CourseCode,
    CurriculumData,
    CurriculumDb,
    CurriculumMap,
    CurriculumPubSub,
    FacultyMaterials,
    MasterSyllabus,
    OutcomeDb,
    SectionSyllabi,
    SkillDb,
    SkillReviewPrompt,
    SuggestionBuilder,
    SuggestionDb,
    SuggestionDecisions,
    XlsxReader
  }

  alias SnowSeTools.Data.DbHelpers

  @ai_topic "curriculum:ai"
  @faculty_budget 40_000
  @section_budget 12_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "The run in progress (with a human-readable phase), or the last one."
  def run_status, do: GenServer.call(__MODULE__, :run_status)

  @doc """
  Sends the caller `{:curriculum, {:loaded, %{data:, programs:, run_status:}}}`
  with the whole map, or `{:curriculum, {:load_failed, reason}}`.
  """
  def request_map(pid: pid) when is_pid(pid), do: GenServer.cast(__MODULE__, {:request_map, pid})

  @doc """
  Reads an uploaded ABET workbook and sends the caller
  `{:curriculum, {:abet_preview, preview}}`: its sheet names, the sheets that
  would be imported, and what importing them would bring in.
  """
  def preview_abet_matrix(pid: pid, xlsx: binary, file_name: file_name, sheets: sheets),
    do: GenServer.cast(__MODULE__, {:preview_abet, pid, binary, file_name, sheets})

  def start_run(pid: pid, program_id: program_id, kind: kind, started_by: started_by)
      when kind in [:full, :syllabi_only] do
    GenServer.cast(__MODULE__, {:start_run, pid, program_id, kind, started_by})
  end

  def create_skill(pid: pid, attrs: attrs),
    do: GenServer.cast(__MODULE__, {:create_skill, pid, attrs})

  def update_skill(pid: pid, id: id, attrs: attrs),
    do: GenServer.cast(__MODULE__, {:update_skill, pid, id, attrs})

  def delete_skill(pid: pid, id: id), do: GenServer.cast(__MODULE__, {:delete_skill, pid, id})

  def set_course_skill(pid: pid, link: link, updated_by: updated_by),
    do: GenServer.cast(__MODULE__, {:set_course_skill, pid, link, updated_by})

  def remove_course_skill(pid: pid, link: link),
    do: GenServer.cast(__MODULE__, {:remove_course_skill, pid, link})

  def accept_suggestions(pid: pid, ids: ids, decided_by: decided_by, levels: levels),
    do: GenServer.cast(__MODULE__, {:accept_suggestions, pid, ids, decided_by, levels})

  def reject_suggestions(pid: pid, ids: ids, decided_by: decided_by),
    do: GenServer.cast(__MODULE__, {:reject_suggestions, pid, ids, decided_by})

  def import_abet_matrix(
        pid: pid,
        xlsx: binary,
        file_name: file_name,
        sheets: sheets,
        imported_by: by
      ),
      do: GenServer.cast(__MODULE__, {:import_abet, pid, binary, file_name, sheets, by})

  @impl true
  def init(:ok) do
    with :ok <- CurriculumDb.bootstrap_tables(),
         :ok <- abandon_interrupted_run() do
      Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @ai_topic)
      {:ok, %{run: nil}}
    else
      {:error, reason} ->
        Logger.error("Curriculum bootstrap failed reason=#{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:run_status, _from, state) do
    {:reply, current_status(state), state}
  end

  @impl true
  def handle_cast({:start_run, pid, _program_id, _kind, _started_by}, %{run: run} = state)
      when run != nil do
    reply(pid, {:error, "A review is already running (#{run.phase})."})
    {:noreply, state}
  end

  def handle_cast({:start_run, pid, program_id, kind, started_by}, state) do
    case begin_run(program_id, kind, started_by) do
      {:ok, run} ->
        reply(pid, {:ok, "Started: reading #{length(run.courses)} master syllabi."})
        state = %{state | run: run}
        broadcast_status(state)
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Curriculum run could not start reason=#{inspect(reason)}")
        reply(pid, {:error, reason})
        {:noreply, state}
    end
  end

  def handle_cast({:request_map, pid}, state) do
    result =
      with {:ok, data} <- CurriculumData.load(),
           {:ok, programs} <- ProgramDb.list_programs() do
        {:loaded, %{data: data, programs: programs, run_status: current_status(state)}}
      else
        {:error, reason} ->
          Logger.error("Curriculum map could not be loaded reason=#{inspect(reason)}")
          {:load_failed, reason}
      end

    send(pid, {:curriculum, result})
    {:noreply, state}
  end

  def handle_cast({:preview_abet, pid, binary, file_name, sheets}, state) do
    preview =
      case XlsxReader.read(binary) do
        {:ok, workbook} ->
          slo_sheet = sheets[:slo_sheet] || AbetMatrix.default_slo_sheet(workbook)

          criteria_sheet =
            if Map.has_key?(sheets, :criteria_sheet),
              do: sheets.criteria_sheet,
              else: AbetMatrix.default_criteria_sheet(workbook)

          %{
            file_name: file_name,
            slo_sheets: AbetMatrix.slo_sheet_names(workbook),
            criteria_sheets: AbetMatrix.criteria_sheet_names(workbook),
            slo_sheet: slo_sheet,
            criteria_sheet: criteria_sheet || "",
            result: interpret_matrix(workbook, slo_sheet, criteria_sheet)
          }

        {:error, reason} ->
          Logger.warning("ABET workbook unreadable file=#{file_name} reason=#{reason}")
          %{file_name: file_name, error: reason}
      end

    send(pid, {:curriculum, {:abet_preview, preview}})
    {:noreply, state}
  end

  def handle_cast({:create_skill, pid, attrs}, state) do
    SkillDb.create_skill(
      name: attrs["name"],
      category: attrs["category"],
      description: attrs["description"]
    )
    |> respond(pid, "Skill added.")

    {:noreply, state}
  end

  def handle_cast({:update_skill, pid, id, attrs}, state) do
    result =
      DbHelpers.transaction(fn ->
        with {:ok, skill} <-
               SkillDb.update_skill(
                 id: id,
                 name: attrs["name"],
                 category: attrs["category"],
                 description: attrs["description"]
               ),
             :ok <-
               SkillDb.set_dependencies(skill_id: id, builds_on_ids: attrs["builds_on_ids"] || []) do
          {:ok, skill}
        end
      end)

    respond(result, pid, "Skill saved.")
    {:noreply, state}
  end

  def handle_cast({:delete_skill, pid, id}, state) do
    respond(SkillDb.delete_skill(id: id), pid, "Skill deleted.")
    {:noreply, state}
  end

  def handle_cast({:set_course_skill, pid, link, updated_by}, state) do
    SkillDb.set_course_skill(
      subject_code: link["subject_code"],
      course_number: link["course_number"],
      skill_id: link["skill_id"],
      level: link["level"],
      note: link["note"] || "",
      updated_by: updated_by
    )
    |> respond(pid, "Saved.")

    {:noreply, state}
  end

  def handle_cast({:remove_course_skill, pid, link}, state) do
    SkillDb.remove_course_skill(
      subject_code: link["subject_code"],
      course_number: link["course_number"],
      skill_id: link["skill_id"]
    )
    |> respond(pid, "Removed.")

    {:noreply, state}
  end

  def handle_cast({:accept_suggestions, pid, ids, decided_by, levels}, state) do
    decide_each(pid, ids, "accepted", fn suggestion ->
      SuggestionDecisions.accept(
        suggestion: suggestion,
        decided_by: decided_by,
        level: levels[suggestion["id"]]
      )
    end)

    {:noreply, state}
  end

  def handle_cast({:reject_suggestions, pid, ids, decided_by}, state) do
    decide_each(
      pid,
      ids,
      "rejected",
      &SuggestionDecisions.reject(suggestion: &1, decided_by: decided_by)
    )

    {:noreply, state}
  end

  def handle_cast({:import_abet, pid, binary, file_name, sheets, imported_by}, state) do
    result =
      with {:ok, workbook} <- XlsxReader.read(binary),
           {:ok, matrix} <-
             AbetMatrix.interpret(
               sheets: workbook,
               slo_sheet: sheets.slo_sheet,
               criteria_sheet: sheets.criteria_sheet
             ) do
        AbetDb.import_matrix(
          matrix: matrix,
          meta: %{
            file_name: file_name,
            slo_sheet: sheets.slo_sheet,
            criteria_sheet: sheets.criteria_sheet,
            imported_by: imported_by
          }
        )
      end

    case result do
      {:ok, counts} ->
        reply(
          pid,
          {:ok, "Imported #{counts.outcomes} ABET outcomes and #{counts.coverage} course marks."}
        )

        CurriculumPubSub.broadcast_changed()

      {:error, reason} ->
        Logger.error("ABET matrix import failed file=#{file_name} reason=#{inspect(reason)}")
        reply(pid, {:error, reason})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:syllabus_read, run_id, course, result}, %{run: %{id: run_id} = run} = state) do
    run =
      case result do
        {:ok, %{added: added, retired: retired}}
        when added + retired > 0 and run.syllabi_seen_before? ->
          add_note(
            run,
            "#{CourseCode.label(course)}: master syllabus outcomes changed (#{added} new, #{retired} removed)."
          )

        {:ok, _counts} ->
          run

        {:error, reason} ->
          add_note(
            run,
            "#{CourseCode.label(course)}: master syllabus not read — #{format_reason(reason)}"
          )
      end

    run = %{run | syllabi_read: run.syllabi_read + 1}
    run = %{run | phase: "Reading master syllabi (#{run.syllabi_read}/#{length(run.courses)})"}
    state = %{state | run: run}
    CurriculumPubSub.broadcast_changed()
    broadcast_status(state)
    {:noreply, state}
  end

  def handle_info({:syllabi_done, run_id}, %{run: %{id: run_id, kind: :syllabi_only}} = state) do
    {:noreply, finish_run(state, "completed")}
  end

  def handle_info({:syllabi_done, run_id}, %{run: %{id: run_id} = run} = state) do
    run = %{run | phase: "Gathering course materials"}
    manager = self()
    start_task(fn -> enqueue_course_reviews(manager, run) end)
    state = %{state | run: run}
    broadcast_status(state)
    {:noreply, state}
  end

  def handle_info({:reviews_enqueued, run_id, notes}, %{run: %{id: run_id} = run} = state) do
    run = Enum.reduce(notes, run, &add_note(&2, &1))
    run = %{run | phase: review_phase(run)}
    state = %{state | run: run}
    broadcast_status(state)
    {:noreply, state}
  end

  def handle_info({:reviews_failed, run_id, reason}, %{run: %{id: run_id} = run} = state) do
    state = %{
      state
      | run: add_note(run, "Course reviews could not start — #{format_reason(reason)}")
    }

    {:noreply, finish_run(state, "error", format_reason(reason))}
  end

  def handle_info(
        {{:course_review, run_id, subject, number}, result},
        %{run: %{id: run_id} = run} = state
      ) do
    course = %{"subject_code" => subject, "course_number" => number}

    run =
      case result do
        {:ok, answer} ->
          record_course_review(run, course, answer)

        {:error, reason} ->
          add_note(
            run,
            "#{CourseCode.label(course)}: AI review failed — #{format_reason(reason)}"
          )
      end

    run = %{run | reviews_done: run.reviews_done + 1}
    persist_progress(run)
    run = %{run | phase: review_phase(run)}
    state = %{state | run: run}
    CurriculumPubSub.broadcast_changed()

    if run.reviews_done >= length(run.courses) do
      {:noreply, start_merge_review(state)}
    else
      broadcast_status(state)
      {:noreply, state}
    end
  end

  def handle_info({{:merge_review, run_id}, result}, %{run: %{id: run_id} = run} = state) do
    run =
      case result do
        {:ok, answer} ->
          record_merge_review(run, answer)

        {:error, reason} ->
          add_note(run, "Duplicate-skill check failed — #{format_reason(reason)}")
      end

    CurriculumPubSub.broadcast_changed()
    {:noreply, finish_run(%{state | run: run}, "completed")}
  end

  def handle_info({{:course_review, _stale_run_id, _subject, _number}, _result}, state),
    do: {:noreply, state}

  def handle_info({{:merge_review, _stale_run_id}, _result}, state), do: {:noreply, state}
  def handle_info({:syllabus_read, _stale_run_id, _course, _result}, state), do: {:noreply, state}
  def handle_info({:syllabi_done, _stale_run_id}, state), do: {:noreply, state}
  def handle_info({:reviews_enqueued, _stale_run_id, _notes}, state), do: {:noreply, state}
  def handle_info({:reviews_failed, _stale_run_id, _reason}, state), do: {:noreply, state}

  def handle_info(message, state) do
    Logger.warning(
      "CurriculumDomainManager ignored an unhandled message #{inspect(message, limit: 5)}"
    )

    {:noreply, state}
  end

  defp begin_run(program_id, kind, started_by) do
    with {:ok, program} <- find_program(program_id),
         courses when courses != [] <- CurriculumMap.program_courses(program),
         {:ok, previous_syllabi} <- OutcomeDb.list_master_syllabi(),
         {:ok, row} <-
           SuggestionDb.create_run(
             program_id: program_id,
             started_by: started_by,
             total_courses: length(courses)
           ),
         :ok <- maybe_supersede(kind, row["id"]) do
      run = %{
        id: row["id"],
        kind: kind,
        program: program,
        started_by: started_by,
        started_at: row["started_at"],
        courses: courses,
        syllabi_seen_before?: previous_syllabi != [],
        syllabi_read: 0,
        reviews_done: 0,
        inserted: MapSet.new(),
        proposed: %{},
        notes: [],
        phase: "Reading master syllabi (0/#{length(courses)})"
      }

      manager = self()
      start_task(fn -> read_master_syllabi(manager, run) end)
      {:ok, run}
    else
      [] -> {:error, "That program has no courses yet."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp interpret_matrix(_workbook, nil, _criteria_sheet),
    do: {:error, "No sheet in this workbook has ABET student outcome rows."}

  defp interpret_matrix(workbook, slo_sheet, criteria_sheet) do
    AbetMatrix.interpret(
      sheets: workbook,
      slo_sheet: slo_sheet,
      criteria_sheet: blank_to_nil(criteria_sheet)
    )
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp maybe_supersede(:full, run_id), do: SuggestionDb.supersede_pending(except_run_id: run_id)
  defp maybe_supersede(:syllabi_only, _run_id), do: :ok

  defp find_program(program_id) do
    with {:ok, programs} <- ProgramDb.list_programs() do
      case Enum.find(programs, &(&1["id"] == program_id)) do
        nil -> {:error, "That academic program no longer exists."}
        program -> {:ok, program}
      end
    end
  end

  # Runs in a task: one snow.edu request at a time is plenty for ~35 courses
  # and keeps us polite to the college's web server.
  defp read_master_syllabi(manager, run) do
    Enum.each(run.courses, fn course ->
      subject = course["subject_code"]
      number = course["course_number"]

      result =
        case MasterSyllabus.fetch(subject_code: subject, course_number: number) do
          {:ok, syllabus} ->
            OutcomeDb.save_master_syllabus(
              subject_code: subject,
              course_number: number,
              syllabus: syllabus
            )

          {:error, reason} ->
            case OutcomeDb.record_fetch_error(
                   subject_code: subject,
                   course_number: number,
                   error: format_reason(reason)
                 ) do
              :ok -> {:error, reason}
              {:error, db_reason} -> {:error, db_reason}
            end
        end

      send(manager, {:syllabus_read, run.id, course, result})
    end)

    send(manager, {:syllabi_done, run.id})
  end

  # Runs in a task: gathering sources means GitHub and database reads per
  # course, and the prompts are queued as they are ready.
  defp enqueue_course_reviews(manager, run) do
    case CurriculumData.load() do
      {:ok, data} ->
        {tree, notes} = faculty_tree()

        program_courses =
          CurriculumMap.titled_courses(courses: run.courses, master_syllabi: data.master_syllabi)

        syllabi = Map.new(data.master_syllabi, &{CourseCode.key(&1), &1})

        outcomes =
          Enum.group_by(Enum.reject(data.outcomes, & &1["retired_at"]), &CourseCode.key/1)

        notes =
          Enum.reduce(program_courses, notes, fn course, notes ->
            {faculty_text, faculty_note} = faculty_text(tree, course)
            {section_text, section_note} = section_text(course)

            messages =
              SkillReviewPrompt.course_messages(%{
                course: course,
                program_courses: program_courses,
                skills: data.skills,
                links: data.links,
                master_syllabus: syllabi[CourseCode.key(course)],
                outcomes: Map.get(outcomes, CourseCode.key(course), []),
                faculty_text: faculty_text,
                section_text: section_text
              })

            AsyncCompletions.complete(
              @ai_topic,
              {:course_review, run.id, course["subject_code"], course["course_number"]},
              messages,
              schema: SkillReviewPrompt.course_schema(),
              user: run.started_by
            )

            notes ++ Enum.reject([faculty_note, section_note], &is_nil/1)
          end)

        send(manager, {:reviews_enqueued, run.id, notes})

      {:error, reason} ->
        send(manager, {:reviews_failed, run.id, reason})
    end
  end

  defp faculty_tree do
    case FacultyMaterials.fetch_tree() do
      {:ok, tree} ->
        {tree, []}

      {:error, :not_configured} ->
        {nil, ["Faculty repository skipped: CURRICULUM_GITHUB_TOKEN is not set."]}

      {:error, reason} ->
        {nil, ["Faculty repository could not be read — #{format_reason(reason)}"]}
    end
  end

  defp faculty_text(nil, _course), do: {"", nil}

  defp faculty_text(tree, course) do
    case FacultyMaterials.read_course(
           tree: tree,
           course_number: course["course_number"],
           budget: @faculty_budget
         ) do
      {:ok, %{text: ""}} -> {"", nil}
      {:ok, %{text: text}} -> {text, nil}
    end
  end

  defp section_text(course) do
    case SectionSyllabi.read_course(
           subject_code: course["subject_code"],
           course_number: course["course_number"],
           budget: @section_budget
         ) do
      {:ok, %{text: text}} ->
        {text, nil}

      {:error, reason} ->
        {"", "#{CourseCode.label(course)}: section syllabi not read — #{format_reason(reason)}"}
    end
  end

  defp record_course_review(run, course, answer) do
    case CurriculumData.review_state() do
      {:ok, review_state} ->
        suggestions =
          answer
          |> then(
            &SuggestionBuilder.from_course_review(answer: &1, course: course, state: review_state)
          )
          |> Enum.reject(&MapSet.member?(run.inserted, &1["fingerprint"]))

        Enum.reduce(suggestions, run, fn suggestion, run ->
          case SuggestionDb.insert_suggestion(run_id: run.id, suggestion: suggestion) do
            :ok ->
              %{
                run
                | inserted: MapSet.put(run.inserted, suggestion["fingerprint"]),
                  proposed: remember_proposed(run.proposed, suggestion)
              }

            {:error, reason} ->
              Logger.error("Curriculum suggestion not saved reason=#{inspect(reason)}")

              add_note(
                run,
                "#{CourseCode.label(course)}: a suggestion could not be saved — #{format_reason(reason)}"
              )
          end
        end)

      {:error, reason} ->
        add_note(
          run,
          "#{CourseCode.label(course)}: suggestions not saved — #{format_reason(reason)}"
        )
    end
  end

  defp remember_proposed(proposed, %{
         "kind" => "course_skill",
         "payload" => %{"skill_id" => nil} = payload
       }) do
    Map.put_new(proposed, SuggestionBuilder.key(payload["skill_name"]), %{
      "name" => payload["skill_name"],
      "description" => payload["description"]
    })
  end

  defp remember_proposed(proposed, _suggestion), do: proposed

  defp start_merge_review(%{run: run} = state) do
    with true <- map_size(run.proposed) > 0,
         {:ok, skills} <- SkillDb.list_skills() do
      AsyncCompletions.complete(
        @ai_topic,
        {:merge_review, run.id},
        SkillReviewPrompt.merge_messages(skills: skills, proposed: Map.values(run.proposed)),
        schema: SkillReviewPrompt.merge_schema(),
        user: run.started_by
      )

      state = %{state | run: %{run | phase: "Looking for duplicate skills"}}
      broadcast_status(state)
      state
    else
      false ->
        finish_run(state, "completed")

      {:error, reason} ->
        finish_run(
          %{
            state
            | run: add_note(run, "Duplicate-skill check skipped — #{format_reason(reason)}")
          },
          "completed"
        )
    end
  end

  defp record_merge_review(run, answer) do
    proposed_names = Enum.map(Map.values(run.proposed), & &1["name"])

    case CurriculumData.review_state() do
      {:ok, review_state} ->
        answer
        |> then(
          &SuggestionBuilder.from_merge_review(
            answer: &1,
            proposed_names: proposed_names,
            state: review_state
          )
        )
        |> Enum.reject(&MapSet.member?(run.inserted, &1["fingerprint"]))
        |> Enum.reduce(run, fn suggestion, run ->
          case SuggestionDb.insert_suggestion(run_id: run.id, suggestion: suggestion) do
            :ok ->
              %{run | inserted: MapSet.put(run.inserted, suggestion["fingerprint"])}

            {:error, reason} ->
              add_note(run, "A merge suggestion could not be saved — #{format_reason(reason)}")
          end
        end)

      {:error, reason} ->
        add_note(run, "Merge suggestions not saved — #{format_reason(reason)}")
    end
  end

  defp finish_run(%{run: run} = state, status, error \\ nil) do
    summary =
      if run.kind == :full,
        do: "Done: #{MapSet.size(run.inserted)} suggestions to review.",
        else: "Done: master syllabi re-read."

    case SuggestionDb.update_run(
           run_id: run.id,
           changes: %{
             status: status,
             error: error,
             notes: run.notes,
             finished_courses: if(run.kind == :full, do: run.reviews_done, else: run.syllabi_read)
           }
         ) do
      {:ok, _row} ->
        :ok

      {:error, reason} ->
        Logger.error("Curriculum run could not be closed reason=#{inspect(reason)}")
    end

    state = %{state | run: nil}
    CurriculumPubSub.broadcast_changed()
    CurriculumPubSub.broadcast_run(%{running?: false, phase: summary, run: last_run_row()})
    state
  end

  defp persist_progress(run) do
    case SuggestionDb.update_run(
           run_id: run.id,
           changes: %{finished_courses: run.reviews_done, notes: run.notes}
         ) do
      {:ok, _row} ->
        :ok

      {:error, reason} ->
        Logger.error("Curriculum run progress not saved reason=#{inspect(reason)}")
    end
  end

  defp abandon_interrupted_run do
    case SuggestionDb.latest_run() do
      {:ok, %{"status" => "running"} = run} ->
        case SuggestionDb.update_run(
               run_id: run["id"],
               changes: %{status: "error", error: "Interrupted by a restart."}
             ) do
          {:ok, _row} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:ok, _no_running_run} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp current_status(%{run: nil}), do: %{running?: false, phase: nil, run: last_run_row()}

  defp current_status(%{run: run}) do
    %{
      running?: true,
      phase: run.phase,
      run: %{
        "id" => run.id,
        "status" => "running",
        "started_by" => run.started_by,
        "started_at" => run.started_at,
        "notes" => run.notes,
        "program_name" => run.program["name"]
      }
    }
  end

  defp last_run_row do
    case SuggestionDb.latest_run() do
      {:ok, run} ->
        run

      {:error, reason} ->
        Logger.error("Curriculum last run not read reason=#{inspect(reason)}")
        nil
    end
  end

  defp broadcast_status(state), do: CurriculumPubSub.broadcast_run(current_status(state))

  defp review_phase(run),
    do: "Reviewing courses with AI (#{run.reviews_done}/#{length(run.courses)})"

  defp add_note(run, note), do: %{run | notes: run.notes ++ [note]}

  defp decide_each(pid, ids, verb, decide) do
    results =
      Enum.map(ids, fn id ->
        with {:ok, suggestion} <- SuggestionDb.get_suggestion(id) do
          decide.(suggestion)
        end
      end)

    failures = for {:error, reason} <- results, do: format_reason(reason)
    done = length(results) - length(failures)

    case failures do
      [] -> reply(pid, {:ok, "#{done} #{plural(done, "suggestion")} #{verb}."})
      [first | _] -> reply(pid, {:error, "#{done} #{verb}, #{length(failures)} not: #{first}"})
    end

    if done > 0, do: CurriculumPubSub.broadcast_changed()
  end

  defp respond(result, pid, message) do
    case result do
      {:ok, _value} ->
        reply(pid, {:ok, message})
        CurriculumPubSub.broadcast_changed()

      :ok ->
        reply(pid, {:ok, message})
        CurriculumPubSub.broadcast_changed()

      {:error, reason} ->
        Logger.error("Curriculum edit failed reason=#{inspect(reason)}")
        reply(pid, {:error, reason})
    end
  end

  defp reply(pid, result), do: send(pid, {:curriculum, {:action_result, result}})

  defp start_task(fun) do
    {:ok, _pid} = Task.Supervisor.start_child(SnowSeTools.TaskSupervisor, fun)
    :ok
  end

  defp plural(1, word), do: word
  defp plural(_count, word), do: word <> "s"

  def format_reason(reason) when is_binary(reason), do: reason
  def format_reason({:query_failed, message}), do: "database error: #{message}"
  def format_reason(:not_found), do: "not found"
  def format_reason(:not_unique), do: "that name is already taken"
  def format_reason(:queue_full), do: "the AI queue is full; try again later"

  def format_reason({status, message}) when is_integer(status),
    do: "AI service answered #{status}: #{inspect(message)}"

  def format_reason(reason), do: inspect(reason, limit: 5)
end
