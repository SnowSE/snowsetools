defmodule SimpleSyllabusReporter.Reports.ReportGenerator do
  use GenServer
  require Logger

  alias SimpleSyllabusReporter.AI.AsyncCompletions
  alias SimpleSyllabusReporter.Reports.GeneratedReport
  alias SimpleSyllabusReporter.Reports.GeneratedReportItem
  alias SimpleSyllabusReporter.Reports.ReportInstruction
  alias SimpleSyllabusReporter.Reports.ReportGenerationStatus
  alias SimpleSyllabusReporter.Reports.RequiredReportElementCoverageCache
  alias SimpleSyllabusReporter.SimpleSyllabusApi

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
    GenServer.start_link(__MODULE__, %{pending: MapSet.new(), report_ids: %{}}, name: __MODULE__)
  end

  @doc "PubSub topic for a given syllabus code."
  def report_topic(code), do: "syllabus_report:#{code}"

  @doc "PubSub topic for pending-state updates for a given syllabus code."
  def pending_topic(code), do: "report_generator:pending:#{code}"

  @doc """
  Enqueues async generation for the given syllabus + element. If the same
  (code, element_id) pair is already in-flight this is a no-op. The result
  is broadcast to `report_topic(code)` as:

      {:report_item_result, code, element_id, {:ok, item} | {:error, reason}}
  """
  def generate_async(syllabus_doc, required_element) do
    GenServer.cast(__MODULE__, {:generate, syllabus_doc, required_element})
  end

  @doc """
  Enqueues async regeneration for every syllabus that has an unmet or
  partially_met item for `required_element`, excluding `exclude_code`
  (which is expected to already be re-queued by the caller).
  """
  def generate_async_all_unmet(required_element, exclude_code) do
    GenServer.cast(__MODULE__, {:generate_all_unmet, required_element, exclude_code})
  end

  @doc """
  Enqueues async generation for every syllabus that has been reported on
  but has no report item for `required_element` in its latest report.
  """
  def generate_async_all_missing(required_element, all_codes) when is_list(all_codes) do
    GenServer.cast(__MODULE__, {:generate_all_missing, required_element, all_codes})
  end

  @doc """
  Requests an immediate broadcast of the current pending element_ids for each
  given code to `pending_topic(code)`. Call this after subscribing to ensure
  you receive the current state.
  """
  def request_pending(codes) when is_list(codes) do
    GenServer.cast(__MODULE__, {:request_pending, codes})
  end

  @impl true
  def init(state) do
    Phoenix.PubSub.subscribe(@pubsub, @ai_topic)
    send(self(), :recover_pending_reports)
    {:ok, state}
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
            prepare_and_send(server, syllabus_doc, element, code, report_id)
          end)

          {:noreply,
           add_pending(%{state | report_ids: new_report_ids}, code, element_id, report_id)}

        {:error, reason} ->
          Logger.error(
            "ReportGenerator could not resolve report code=#{code} reason=#{inspect(reason)}"
          )

          broadcast_result(code, element_id, {:error, reason})
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_cast({:generate_all_unmet, element, exclude_code}, state) do
    Task.start(fn ->
      case GeneratedReportItem.list_unmet_for_element(element["id"]) do
        {:ok, rows} ->
          rows
          |> Enum.reject(fn row -> row["code"] == exclude_code end)
          |> Enum.group_by(& &1["code"])
          |> Enum.each(fn {code, _} ->
            case SimpleSyllabusApi.get_syllabus_details(code) do
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
      case GeneratedReportItem.list_not_generated_for_element(element["id"], all_codes) do
        {:ok, codes} ->
          Enum.each(codes, fn code ->
            case SimpleSyllabusApi.get_syllabus_details(code) do
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
  def handle_cast({:request_pending, codes}, state) do
    Enum.each(codes, fn code -> broadcast_pending_update(code, state.pending) end)
    {:noreply, state}
  end

  @impl true
  def handle_info(:recover_pending_reports, state) do
    case GeneratedReport.list_pending_with_incomplete_elements() do
      {:ok, []} ->
        {:noreply, state}

      {:ok, rows} ->
        Logger.info("Recovering #{length(rows)} pending report element(s) after restart")

        rows
        |> Enum.group_by(& &1["code"])
        |> Enum.each(fn {code, elements} ->
          Task.start(fn ->
            case SimpleSyllabusApi.get_syllabus_details(code) do
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
      "ReportGenerator prepare failed element_id=#{element_id} reason=#{inspect(reason)}"
    )

    broadcast_result(code, element_id, {:error, reason})
    {:noreply, drop_pending(state, code, element_id)}
  end

  def handle_info({{code, element_id, report_id}, {:ok, ai_result}}, state) do
    result =
      case GeneratedReportItem.upsert(report_id, element_id, ai_result) do
        {:ok, item} = ok ->
          RequiredReportElementCoverageCache.notify_item_saved(element_id)
          ok

        {:error, reason} = err ->
          Logger.error(
            "ReportGenerator upsert failed element_id=#{element_id} reason=#{inspect(reason)}"
          )

          err
      end

    broadcast_result(code, element_id, result)
    {:noreply, drop_pending(state, code, element_id)}
  end

  def handle_info({{code, element_id, _report_id}, {:error, reason}}, state) do
    Logger.error("ReportGenerator AI failed element_id=#{element_id} reason=#{inspect(reason)}")

    broadcast_result(code, element_id, {:error, reason})
    {:noreply, drop_pending(state, code, element_id)}
  end

  defp broadcast_result(code, element_id, result) do
    ReportGenerationStatus.publish_item_result(code, element_id, result)
  end

  defp broadcast_pending_update(code, pending) do
    element_ids =
      pending
      |> Enum.filter(fn {c, _} -> c == code end)
      |> Enum.map(fn {_, id} -> id end)
      |> MapSet.new()

    ReportGenerationStatus.publish_pending_update(code, element_ids)
  end

  defp ensure_report_id(code, syllabus_doc, report_ids) do
    case Map.get(report_ids, code) do
      nil ->
        case GeneratedReport.get_or_create_for_syllabus(
               syllabus_doc["code"],
               syllabus_doc["title"] || syllabus_doc["code"],
               primary_instructor_name(syllabus_doc)
             ) do
          {:ok, report} -> {:ok, report["id"], Map.put(report_ids, code, report["id"])}
          {:error, _} = err -> err
        end

      report_id ->
        {:ok, report_id, report_ids}
    end
  end

  defp prepare_and_send(server, syllabus_doc, element, code, report_id) do
    element_id = element["id"]

    result =
      try do
        build_messages_for(syllabus_doc, element)
      rescue
        e -> {:error, {:exception, Exception.message(e)}}
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    case result do
      {:ok, messages} ->
        send(server, {:generation_prepared, code, element_id, report_id, messages})

      {:error, reason} ->
        send(server, {:generation_failed, code, element_id, reason})
    end
  end

  defp add_pending(state, code, element_id, report_id) do
    new_pending = MapSet.put(state.pending, {code, element_id})
    broadcast_pending_update(code, new_pending)
    %{state | pending: new_pending, report_ids: Map.put(state.report_ids, code, report_id)}
  end

  defp drop_pending(state, code, element_id) do
    new_pending = MapSet.delete(state.pending, {code, element_id})
    broadcast_pending_update(code, new_pending)

    new_report_ids =
      if Enum.any?(new_pending, fn {c, _} -> c == code end) do
        state.report_ids
      else
        Map.delete(state.report_ids, code)
      end

    %{state | pending: new_pending, report_ids: new_report_ids}
  end

  defp build_messages_for(syllabus_doc, required_element) do
    with {:ok, instructions} <- ReportInstruction.list_for_element(required_element["id"]) do
      syllabus_text = extract_syllabus_text(syllabus_doc)
      {:ok, build_messages(required_element, instructions, syllabus_text)}
    end
  end

  defp build_messages(element, instructions, syllabus_text) do
    instruction_block =
      case instructions do
        [] ->
          ""

        _ ->
          lines = Enum.map_join(instructions, "\n", fn i -> "- #{i["content"]}" end)

          """

          <mandatory_evaluation_rules>
          The following rules MUST be applied when evaluating this element. They take precedence over your general judgment. If any rule conflicts with a standard finding, follow the rule.
          When a rule includes an example referencing a specific course, that example illustrates the pattern — the rule applies equally to ALL courses, including the one you are evaluating now. Never treat a course-specific example as evidence that the rule is limited to that course.
          #{lines}
          </mandatory_evaluation_rules>
          """
      end

    system = """
    You are an academic compliance reviewer evaluating whether a college course syllabus satisfies a specific required element policy.
    #{instruction_block}
    Analyze the provided syllabus content carefully and respond with:
    - status: "met", "not_met", or "partially_met"
    - description: a clear and short explanation of your finding
    - evidence: a verbatim excerpt from the syllabus that supports your finding (empty string if none found)
    - additional_considerations: any caveats, edge-cases, or notes for the reviewer, shorter is better (empty string if none)
    """

    user = """
    <required_element>
    <name>#{element["name"]}</name>
    <description>#{element["description"]}</description>
    </required_element>

    <syllabus_content>
    #{syllabus_text}
    </syllabus_content>
    """

    [
      %{role: "system", content: String.trim(system)},
      %{role: "user", content: String.trim(user)}
    ]
  end

  defp extract_syllabus_text(doc) do
    (doc["components"] || [])
    |> Enum.sort_by(& &1["sort_order"])
    |> Enum.map_join("\n\n", fn component ->
      name = component["name"] || ""
      text = (component["html"] || "") |> HtmlSanitizeEx.strip_tags() |> String.trim()
      if name != "", do: "## #{name}\n#{text}", else: text
    end)
  end

  defp primary_instructor_name(doc) do
    name =
      (doc["editors"] || [])
      |> Enum.filter(fn editor ->
        "instructor" in (get_in(editor, ["role", "role_types"]) || [])
      end)
      |> Enum.flat_map(fn editor -> editor["accounts"] || [] end)
      |> Enum.map_join(", ", fn account -> account["email"] || "" end)

    if name == "", do: "Unknown", else: name
  end
end
