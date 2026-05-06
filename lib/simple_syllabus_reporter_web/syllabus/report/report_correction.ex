defmodule SimpleSyllabusReporterWeb.Syllabus.ReportCorrection do
  use SimpleSyllabusReporterWeb, :html

  import Phoenix.LiveView
  import Phoenix.Component

  alias SimpleSyllabusReporter.Reports.ReportGenerator
  alias SimpleSyllabusReporter.Reports.ReportInstruction

  attr :element_id, :string, required: true
  attr :finding, :string, required: true
  attr :evidence, :string, default: ""
  attr :considerations, :string, default: ""
  attr :status, :string, default: nil
  attr :syllabus, :map, default: nil
  attr :open, :boolean, default: false

  def correction_panel(assigns) do
    ~H"""
    <%= if @open do %>
      <form
        id={"correction-form-#{@element_id}"}
        phx-submit="save_correction"
        class="flex flex-col gap-2"
      >
        <input type="hidden" name="element_id" value={@element_id} />
        <input
          :if={syllabus_text(@syllabus) != ""}
          type="hidden"
          name="syllabus_content"
          value={syllabus_text(@syllabus)}
        />
        <p class="text-[10px] font-semibold uppercase tracking-wider text-slate-500">
          Describe what's incorrect
        </p>
        <textarea
          id={"correction-textarea-#{@element_id}"}
          name="content"
          rows="18"
          class="w-full bg-slate-950 text-slate-200 text-xs rounded-lg px-3 py-2.5 border border-slate-700 focus:outline-none focus:border-indigo-500 resize-none leading-relaxed font-mono"
        >{build_evaluation_text(@status, @finding, @evidence, @considerations)}</textarea>
        <div class="flex gap-2">
          <button
            id={"save-correction-btn-#{@element_id}"}
            type="submit"
            class="px-3 py-1.5 text-xs bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg transition-colors cursor-pointer"
          >
            Save correction
          </button>
          <button
            id={"cancel-correction-btn-#{@element_id}"}
            type="button"
            phx-click="cancel_correction"
            class="px-3 py-1.5 text-xs text-slate-400 hover:text-slate-200 transition-colors cursor-pointer"
          >
            Cancel
          </button>
        </div>
      </form>
    <% else %>
      <button
        id={"correct-btn-#{@element_id}"}
        type="button"
        phx-click="open_correction"
        phx-value-id={@element_id}
        class="inline-flex items-center gap-1 text-xs text-slate-600 hover:text-slate-400 transition-colors cursor-pointer"
      >
        <span class="hero-pencil-square size-3" /> Correct this report
      </button>
    <% end %>
    """
  end

  def handle_save_correction(
        %{"element_id" => element_id, "content" => content} = params,
        socket,
        syllabus
      ) do
    full_content =
      case Map.get(params, "syllabus_content", "") do
        "" ->
          content

        syllabus_text ->
          "<syllabus_content>\n#{syllabus_text}\n</syllabus_content>\n\n---\n\n<evaluation>\n#{content}\n</evaluation>"
      end

    case ReportInstruction.create(element_id, %{"content" => full_content}) do
      {:ok, _} ->
        element = Enum.find(socket.assigns.elements, fn e -> e["id"] == element_id end)
        ReportGenerator.generate_async(syllabus, element)

        {:noreply,
         socket
         |> assign(:correcting_element_id, nil)
         |> assign(:generating, MapSet.put(socket.assigns.generating, element_id))
         |> assign(:generation_errors, Map.delete(socket.assigns.generation_errors, element_id))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save correction: #{inspect(reason)}")}
    end
  end

  defp build_evaluation_text(status, finding, evidence, considerations) do
    status_label = status_text(status)
    finding_section = "Status: #{status_label}\nFinding: #{finding}"

    evidence_section =
      if evidence && evidence != "",
        do: "\n\nEvidence: #{evidence}",
        else: ""

    considerations_section =
      if considerations && considerations != "",
        do: "\n\nConsiderations: #{considerations}",
        else: ""

    finding_section <>
      evidence_section <>
      considerations_section
  end

  defp status_text("met"), do: "Met"
  defp status_text("not_met"), do: "Not Met"
  defp status_text("partially_met"), do: "Partially Met"
  defp status_text(_), do: "Unknown"

  defp syllabus_text(nil), do: ""

  defp syllabus_text(doc) do
    (doc["components"] || [])
    |> Enum.sort_by(& &1["sort_order"])
    |> Enum.map_join("\n\n", fn component ->
      name = component["name"] || ""
      text = (component["html"] || "") |> HtmlSanitizeEx.strip_tags() |> String.trim()
      if name != "", do: "## #{name}\n#{text}", else: text
    end)
  end
end
