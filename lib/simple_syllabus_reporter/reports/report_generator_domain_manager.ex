defmodule SimpleSyllabusReporter.Reports.ReportGeneratorDomainManger do
  use GenServer
  require Logger

  alias SimpleSyllabusReporter.AI.AsyncCompletions
  alias SimpleSyllabusReporter.ConfigDB
  alias SimpleSyllabusReporter.Reports.GeneratedReportDB
  alias SimpleSyllabusReporter.Reports.GeneratedReportItemDB
  alias SimpleSyllabusReporter.Reports.ReportGenerationMessages
  alias SimpleSyllabusReporter.Reports.ReportGenerationStatus
  alias SimpleSyllabusReporter.Reports.RequiredElementDB
  alias SimpleSyllabusReporter.Reports.CoverageCacheUtils
  alias SimpleSyllabusReporter.Syllabi.SyllabusDomainManager

  @pubsub SimpleSyllabusReporter.PubSub
  @ai_topic "report_generator:ai"

  @ai_schema %{
    "type" => "object",
    "properties" => %{
      "status" => %{"type" => "string", "enum" => ["met", "not_met", "partially_met"]},
      "description" => %{"type" => "string"},
      "evidence" => %{"type" => "string"},
      "additional_considerations" => %{"type" => "string"}
    },
    "required" => ["status", "description", "evidence", "additional_considerations"],
    "additionalProperties" => false
  }

  def start_link(_opts) do
    GenServer.start_link(
      __MODULE__,
      %{
        pending: MapSet.new(),
        report_ids: %{},
        broadcast_timer: nil,
        counts: %{},
        syllabi_codes: []
      },
      name: __MODULE__
    )
  end

  def generate_async(syllabus_doc, required_element) do
    GenServer.cast(__MODULE__, {:generate, syllabus_doc, required_element})
  end

  # --- Coverage cache public API ---

  def element_coverage_topic(element_id), do: CoverageCacheUtils.element_topic(element_id)

  def subscribe_element_coverage(element_id) do
    Phoenix.PubSub.subscribe(@pubsub, element_coverage_topic(element_id))
  end

  def unsubscribe_element_coverage(element_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, element_coverage_topic(element_id))
  end

  def get_element_coverage(element_id) do
    GenServer.call(__MODULE__, {:get_coverage, element_id})
  end

  def get_syllabi_codes do
    GenServer.call(__MODULE__, :get_syllabi_codes)
  end

  def set_syllabi_codes(codes) when is_list(codes) do
    GenServer.cast(__MODULE__, {:set_syllabi_codes, codes})
  end

  def request_totals(pid) do
    GenServer.cast(__MODULE__, {:request_totals, pid})
  end

  def generate_async_all_unmet(required_element, exclude_code) do
    GenServer.cast(__MODULE__, {:generate_all_unmet, required_element, exclude_code})
  end

  def generate_async_all_missing(required_element, all_codes) when is_list(all_codes) do
    GenServer.cast(__MODULE__, {:generate_all_missing, required_element, all_codes})
  end

  def request_pending(codes) when is_list(codes) do
    GenServer.cast(__MODULE__, {:request_pending, codes})
  end

  def request_items_for_code(code, pid) do
    GenServer.cast(__MODULE__, {:request_items_for_code, code, pid})
  end

  def request_report_counts(codes, pid) when is_list(codes) do
    GenServer.cast(__MODULE__, {:request_report_counts, codes, pid})
  end

  def request_elements(pid) do
    GenServer.cast(__MODULE__, {:request_elements, pid})
  end

  def generate_missing_for_codes(codes, elements) when is_list(codes) do
    GenServer.cast(__MODULE__, {:generate_missing_for_codes, codes, elements})
  end

  def regenerate_non_met_for_code(code, elements) do
    GenServer.cast(__MODULE__, {:regenerate_non_met_for_code, code, elements})
  end

  @impl true
  def init(state) do
    Phoenix.PubSub.subscribe(@pubsub, @ai_topic)
    ConfigDB.subscribe()
    send(self(), :recover_pending_reports)
    send(self(), :hydrate_coverage)
    {:ok, state}
  end

  @impl true
  def handle_call({:get_coverage, element_id}, _from, state) do
    counts = Map.get(state.counts, element_id)
    {:reply, CoverageCacheUtils.with_not_generated(counts), state}
  end

  @impl true
  def handle_call(:get_syllabi_codes, _from, state) do
    {:reply, state.syllabi_codes, state}
  end

  @impl true
  def handle_cast({:set_syllabi_codes, codes}, state) do
    {:noreply, %{state | syllabi_codes: codes}}
  end

  @impl true
  def handle_cast({:request_totals, pid}, state) do
    Task.start(fn ->
      case GeneratedReportItemDB.totals_by_school() do
        {:ok, by_school} ->
          school_rows = Enum.map(by_school, &with_not_generated_for_school/1)
          grand_total = sum_school_totals(school_rows)
          send(pid, {:totals_loaded, %{"totals" => grand_total, "by_school" => school_rows}})

        {:error, reason} ->
          Logger.error(
            "ReportGeneratorDomainManger request_totals failed reason=#{inspect(reason)}"
          )
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:refresh_coverage, element_id}, state) do
    {:noreply, refresh_coverage(state, element_id)}
  end

  @impl true
  def handle_cast({:generate, syllabus_doc, element}, state) do
    code = syllabus_doc["code"]
    element_id = element["id"]
    key = {code, element_id}

    if MapSet.member?(state.pending, key) do
      {:noreply, state}
    else
      case ensure_report_id(code, syllabus_doc, state.report_ids) do
        {:ok, report_id, new_report_ids} ->
          server = self()

          Task.start(fn ->
            ReportGenerationMessages.prepare_and_send(server, syllabus_doc, element, code, report_id)
          end)

          {:noreply,
           add_pending(%{state | report_ids: new_report_ids}, code, element_id, report_id)}

        {:error, reason} ->
          Logger.error(
            "ReportGeneratorDomainManger could not resolve report code=#{code} reason=#{inspect(reason)}"
          )

          broadcast_result(code, element_id, {:error, reason})
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_cast({:generate_all_unmet, element, exclude_code}, state) do
    Task.start(fn ->
      case GeneratedReportItemDB.list_unmet_for_element(element["id"]) do
        {:ok, rows} ->
          rows
          |> Enum.reject(fn row -> row["code"] == exclude_code end)
          |> Enum.group_by(& &1["code"])
          |> Enum.each(fn {code, _} ->
            case SyllabusDomainManager.get_detail(code) do
              {:ok, syllabus_doc} ->
                generate_async(syllabus_doc, element)

              {:error, reason} ->
                Logger.error(
                  "generate_all_unmet: failed to fetch syllabus code=#{code} reason=#{inspect(reason)}"
                )
            end
          end)

        {:error, reason} ->
          Logger.error("generate_all_unmet: failed to list unmet items reason=#{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:generate_all_missing, element, all_codes}, state) do
    Task.start(fn ->
      case GeneratedReportItemDB.list_not_generated_for_element(element["id"], all_codes) do
        {:ok, codes} ->
          Enum.each(codes, fn code ->
            case SyllabusDomainManager.get_detail(code) do
              {:ok, syllabus_doc} ->
                generate_async(syllabus_doc, element)

              {:error, reason} ->
                Logger.error(
                  "generate_all_missing: failed to fetch syllabus code=#{code} reason=#{inspect(reason)}"
                )
            end
          end)

        {:error, reason} ->
          Logger.error("generate_all_missing: failed to list codes reason=#{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:request_pending, _codes}, state) do
    ReportGenerationStatus.publish_pending_update(state.pending)
    {:noreply, state}
  end

  def handle_cast({:request_items_for_code, code, pid}, state) do
    Task.start(fn -> send(pid, {:report_items_loaded, fetch_items_for_code(code)}) end)
    {:noreply, state}
  end

  def handle_cast({:request_report_counts, codes, pid}, state) do
    Task.start(fn ->
      send(pid, {:report_counts_loaded, GeneratedReportItemDB.item_counts_for_syllabi(codes)})
    end)

    {:noreply, state}
  end

  def handle_cast({:request_elements, pid}, state) do
    Task.start(fn -> send(pid, {:elements_loaded, RequiredElementDB.list_all()}) end)
    {:noreply, state}
  end

  def handle_cast({:generate_missing_for_codes, codes, elements}, state) do
    Task.start(fn ->
      Enum.each(codes, fn code ->
        with {:ok, full_doc} <- SyllabusDomainManager.get_detail(code),
             {:ok, items_map} <- fetch_items_for_code(code) do
          existing_ids = MapSet.new(Map.keys(items_map))
          missing = Enum.reject(elements, fn e -> MapSet.member?(existing_ids, e["id"]) end)
          Enum.each(missing, fn element -> generate_async(full_doc, element) end)
        else
          {:error, reason} ->
            Logger.error(
              "generate_missing_for_codes: failed for code=#{code} reason=#{inspect(reason)}"
            )
        end
      end)
    end)

    {:noreply, state}
  end

  def handle_cast({:regenerate_non_met_for_code, code, elements}, state) do
    Task.start(fn ->
      with {:ok, full_doc} <- SyllabusDomainManager.get_detail(code),
           {:ok, items_map} <- fetch_items_for_code(code) do
        non_met_ids =
          items_map
          |> Enum.filter(fn {_id, item} -> item["status"] in ["not_met", "partially_met"] end)
          |> MapSet.new(fn {id, _} -> id end)

        elements
        |> Enum.filter(fn e -> MapSet.member?(non_met_ids, e["id"]) end)
        |> Enum.each(fn element -> generate_async(full_doc, element) end)
      else
        {:error, reason} ->
          Logger.error(
            "regenerate_non_met_for_code: failed for code=#{code} reason=#{inspect(reason)}"
          )
      end
    end)

    {:noreply, state}
  end

  def handle_info(:flush_pending_broadcast, state) do
    ReportGenerationStatus.publish_pending_update(state.pending)
    {:noreply, %{state | broadcast_timer: nil}}
  end

  @impl true
  def handle_info({:term_changed, _term_id}, state) do
    send(self(), :hydrate_coverage)
    {:noreply, state}
  end

  @impl true
  def handle_info(:hydrate_coverage, state) do
    counts =
      case GeneratedReportItemDB.all_element_coverage_counts() do
        {:ok, rows} ->
          CoverageCacheUtils.hydrate_counts(rows)

        {:error, reason} ->
          Logger.error(
            "ReportGeneratorDomainManger coverage hydration failed: #{inspect(reason)}"
          )

          %{}
      end

    Enum.each(counts, fn {element_id, raw} ->
      CoverageCacheUtils.broadcast_element(
        element_id,
        CoverageCacheUtils.with_not_generated(raw)
      )
    end)

    {:noreply, %{state | counts: counts}}
  end

  @impl true
  def handle_info(:recover_pending_reports, state) do
    case GeneratedReportDB.list_pending_with_incomplete_elements() do
      {:ok, []} ->
        {:noreply, state}

      {:ok, rows} ->
        Logger.info("Recovering #{length(rows)} pending report element(s) after restart")

        rows
        |> Enum.group_by(& &1["code"])
        |> Enum.each(fn {code, elements} ->
          Task.start(fn ->
            case SyllabusDomainManager.get_detail(code) do
              {:ok, syllabus_doc} ->
                Enum.each(elements, fn row ->
                  element = %{
                    "id" => row["element_id"],
                    "name" => row["element_name"],
                    "description" => row["element_description"]
                  }

                  generate_async(syllabus_doc, element)
                end)

              {:error, reason} ->
                Logger.error(
                  "Recovery: failed to fetch syllabus code=#{code} reason=#{inspect(reason)}"
                )
            end
          end)
        end)

        {:noreply, state}

      {:error, reason} ->
        Logger.error("Failed to recover pending reports: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:generation_prepared, code, element_id, report_id, messages}, state) do
    AsyncCompletions.complete(@ai_topic, {code, element_id, report_id}, messages,
      schema: @ai_schema
    )

    {:noreply, state}
  end

  def handle_info({:generation_failed, code, element_id, reason}, state) do
    Logger.error(
      "ReportGeneratorDomainManger prepare failed element_id=#{element_id} reason=#{inspect(reason)}"
    )

    broadcast_result(code, element_id, {:error, reason})
    {:noreply, drop_pending(state, code, element_id)}
  end

  def handle_info({{code, element_id, report_id}, {:ok, ai_result}}, state) do
    {result, state} =
      case GeneratedReportItemDB.upsert(report_id, element_id, ai_result) do
        {:ok, _item} = ok ->
          {ok, refresh_coverage(state, element_id)}

        {:error, reason} = err ->
          Logger.error(
            "ReportGeneratorDomainManger upsert failed element_id=#{element_id} reason=#{inspect(reason)}"
          )

          {err, state}
      end

    broadcast_result(code, element_id, result)
    {:noreply, drop_pending(state, code, element_id)}
  end

  def handle_info({{code, element_id, _report_id}, {:error, reason}}, state) do
    Logger.error(
      "ReportGeneratorDomainManger AI failed element_id=#{element_id} reason=#{inspect(reason)}"
    )

    broadcast_result(code, element_id, {:error, reason})
    {:noreply, drop_pending(state, code, element_id)}
  end

  defp refresh_coverage(state, element_id) do
    case GeneratedReportItemDB.item_counts_for_element(element_id) do
      {:ok, raw} ->
        CoverageCacheUtils.broadcast_element(
          element_id,
          CoverageCacheUtils.with_not_generated(raw)
        )

        %{state | counts: Map.put(state.counts, element_id, raw)}

      {:error, reason} ->
        Logger.error(
          "ReportGeneratorDomainManger coverage refresh failed element_id=#{element_id} reason=#{inspect(reason)}"
        )

        state
    end
  end

  defp broadcast_result(code, element_id, result) do
    ReportGenerationStatus.publish_item_result(code, element_id, result)
  end

  defp schedule_pending_broadcast(%{broadcast_timer: nil} = state) do
    timer = Process.send_after(self(), :flush_pending_broadcast, 200)
    %{state | broadcast_timer: timer}
  end

  defp schedule_pending_broadcast(state), do: state

  defp fetch_items_for_code(code) do
    case GeneratedReportDB.get_latest_for_syllabus(code) do
      {:ok, report} -> GeneratedReportItemDB.list_for_report_as_map(report["id"])
      {:error, :not_found} -> {:ok, %{}}
      {:error, _} = err -> err
    end
  end

  defp ensure_report_id(code, syllabus_doc, report_ids) do
    case Map.get(report_ids, code) do
      nil ->
        case GeneratedReportDB.get_or_create_for_syllabus(
               syllabus_doc["code"],
               syllabus_doc["title"] || syllabus_doc["code"],
               ReportGenerationMessages.primary_instructor_name(syllabus_doc)
             ) do
          {:ok, report} -> {:ok, report["id"], Map.put(report_ids, code, report["id"])}
          {:error, _} = err -> err
        end

      report_id ->
        {:ok, report_id, report_ids}
    end
  end

  defp add_pending(state, code, element_id, report_id) do
    new_pending = MapSet.put(state.pending, {code, element_id})

    new_state = %{
      state
      | pending: new_pending,
        report_ids: Map.put(state.report_ids, code, report_id)
    }

    schedule_pending_broadcast(new_state)
  end

  defp drop_pending(state, code, element_id) do
    new_pending = MapSet.delete(state.pending, {code, element_id})

    new_report_ids =
      if Enum.any?(new_pending, fn {c, _} -> c == code end) do
        state.report_ids
      else
        Map.delete(state.report_ids, code)
      end

    new_state = %{state | pending: new_pending, report_ids: new_report_ids}
    schedule_pending_broadcast(new_state)
  end

  defp with_not_generated_for_school(row) do
    not_generated = max(0, row["total_syllabi"] - row["syllabi_with_reports"])
    Map.put(row, "not_generated", not_generated)
  end

  defp sum_school_totals(school_rows) do
    Enum.reduce(school_rows, %{"met" => 0, "not_met" => 0, "partially_met" => 0, "total_syllabi" => 0, "not_generated" => 0}, fn row, acc ->
      %{
        "met" => acc["met"] + row["met"],
        "not_met" => acc["not_met"] + row["not_met"],
        "partially_met" => acc["partially_met"] + row["partially_met"],
        "total_syllabi" => acc["total_syllabi"] + row["total_syllabi"],
        "not_generated" => acc["not_generated"] + row["not_generated"]
      }
    end)
  end
end
