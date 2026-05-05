defmodule SimpleSyllabusReporter.Reports.ReportGenerator do
  use GenServer
  require Logger

  alias SimpleSyllabusReporter.AI.AsyncCompletions
  alias SimpleSyllabusReporter.Reports.GeneratedReport
  alias SimpleSyllabusReporter.Reports.GeneratedReportItem
  alias SimpleSyllabusReporter.Reports.ReportInstruction

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
    GenServer.start_link(__MODULE__, %{pending: MapSet.new()}, name: __MODULE__)
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
      server = self()

      Task.start(fn ->
        case prepare_generation(syllabus_doc, element) do
          {:ok, {report_id, messages}} ->
            send(server, {:generation_prepared, code, element_id, report_id, messages})

          {:error, reason} ->
            send(server, {:generation_failed, code, element_id, reason})
        end
      end)

      new_pending = MapSet.put(state.pending, key)
      broadcast_pending_update(code, new_pending)
      {:noreply, %{state | pending: new_pending}}
    end
  end

  @impl true
  def handle_cast({:request_pending, codes}, state) do
    Enum.each(codes, fn code -> broadcast_pending_update(code, state.pending) end)
    {:noreply, state}
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
    new_pending = MapSet.delete(state.pending, {code, element_id})
    broadcast_pending_update(code, new_pending)
    {:noreply, %{state | pending: new_pending}}
  end

  def handle_info({{code, element_id, report_id}, {:ok, ai_result}}, state) do
    result =
      case GeneratedReportItem.upsert(report_id, element_id, ai_result) do
        {:ok, _item} = ok ->
          ok

        {:error, reason} = err ->
          Logger.error(
            "ReportGenerator upsert failed element_id=#{element_id} reason=#{inspect(reason)}"
          )

          err
      end

    broadcast_result(code, element_id, result)
    new_pending = MapSet.delete(state.pending, {code, element_id})
    broadcast_pending_update(code, new_pending)
    {:noreply, %{state | pending: new_pending}}
  end

  def handle_info({{code, element_id, _report_id}, {:error, reason}}, state) do
    Logger.error("ReportGenerator AI failed element_id=#{element_id} reason=#{inspect(reason)}")

    broadcast_result(code, element_id, {:error, reason})
    new_pending = MapSet.delete(state.pending, {code, element_id})
    broadcast_pending_update(code, new_pending)
    {:noreply, %{state | pending: new_pending}}
  end

  defp broadcast_result(code, element_id, result) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      report_topic(code),
      {:report_item_result, code, element_id, result}
    )
  end

  defp broadcast_pending_update(code, pending) do
    element_ids =
      pending
      |> Enum.filter(fn {c, _} -> c == code end)
      |> Enum.map(fn {_, id} -> id end)
      |> MapSet.new()

    Phoenix.PubSub.broadcast(@pubsub, pending_topic(code), {:pending_update, code, element_ids})
  end

  defp prepare_generation(syllabus_doc, required_element) do
    with {:ok, instructions} <- ReportInstruction.list_for_element(required_element["id"]),
         {:ok, report} <-
           GeneratedReport.get_or_create_for_syllabus(
             syllabus_doc["code"],
             syllabus_doc["title"] || syllabus_doc["code"],
             primary_instructor_name(syllabus_doc)
           ) do
      syllabus_text = extract_syllabus_text(syllabus_doc)
      messages = build_messages(required_element, instructions, syllabus_text)
      {:ok, {report["id"], messages}}
    end
  end

  defp build_messages(element, instructions, syllabus_text) do
    system = """
    You are an academic compliance reviewer evaluating whether a college course syllabus satisfies a specific required element policy.
    Analyze the provided syllabus content carefully. Return a structured JSON response with:
    - status: "met", "not_met", or "partially_met"
    - description: a clear and short explanation of your finding
    - evidence: a verbatim excerpt from the syllabus that supports your finding (empty string if none found)
    - additional_considerations: any caveats, edge-cases, or notes for the reviewer, shorter is better (empty string if none)
    """

    instruction_block =
      case instructions do
        [] ->
          ""

        _ ->
          lines = Enum.map_join(instructions, "\n", fn i -> "- #{i["content"]}" end)
          "\n<evaluation_instructions>\n#{lines}\n</evaluation_instructions>"
      end

    user = """
    <required_element>
    <name>#{element["name"]}</name>
    <description>#{element["description"]}</description>#{instruction_block}
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
