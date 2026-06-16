defmodule SnowSeTools.Reports.ReportGenerationMessages do
  @moduledoc """
  Builds AI prompt messages for report generation and dispatches them
  to the GenServer via send/2. No GenServer state dependency.
  """

  alias SnowSeTools.Reports.ReportInstructionDB

  @doc """
  Runs in a Task. Builds messages for the given syllabus + element and
  sends either `{:generation_prepared, ...}` or `{:generation_failed, ...}`
  back to `server`.
  """
  def prepare_and_send(server, syllabus_doc, element, code, report_id) do
    element_id = element["id"]

    result =
      try do
        build_for(syllabus_doc, element)
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

  def primary_instructor_name(doc) do
    name =
      (doc["editors"] || [])
      |> Enum.filter(fn editor ->
        "instructor" in (get_in(editor, ["role", "role_types"]) || [])
      end)
      |> Enum.flat_map(fn editor -> editor["accounts"] || [] end)
      |> Enum.map_join(", ", fn account -> account["email"] || "" end)

    if name == "", do: "Unknown", else: name
  end

  defp build_for(syllabus_doc, required_element) do
    with {:ok, instructions} <- ReportInstructionDB.list_for_element(required_element["id"]) do
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
end
