defmodule SimpleSyllabusReporterWeb.Syllabus.ReportHandlers do
  require Logger
  import Phoenix.Component

  use SimpleSyllabusReporterWeb, :verified_routes

  alias SimpleSyllabusReporter.Reports.ReportGeneratorDomainManger
  alias SimpleSyllabusReporter.Reports.ReportGenerationStatus
  alias SimpleSyllabusReporterWeb.Syllabus.ReportCorrection

  def handle_event("select_element", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_element_id, id)}
  end

  def handle_event("open_correction", %{"id" => element_id}, socket) do
    {:noreply, assign(socket, :correcting_element_id, element_id)}
  end

  def handle_event("cancel_correction", _params, socket) do
    {:noreply, assign(socket, :correcting_element_id, nil)}
  end

  def handle_event("save_correction", params, socket) do
    ReportCorrection.handle_save_correction(params, socket, socket.assigns.selected)
  end

  def handle_event("generate_missing_for_selected", _params, socket) do
    selected = socket.assigns.selected
    elements = socket.assigns.elements
    report_items = socket.assigns.report_items

    missing = Enum.reject(elements, fn e -> Map.has_key?(report_items, e["id"]) end)

    Enum.each(missing, fn element ->
      ReportGeneratorDomainManger.generate_async(selected, element)
    end)

    missing_ids = MapSet.new(missing, & &1["id"])

    {:noreply, assign(socket, :generating, MapSet.union(socket.assigns.generating, missing_ids))}
  end

  def handle_event("generate_report", %{"id" => element_id}, socket) do
    element = Enum.find(socket.assigns.elements, fn e -> e["id"] == element_id end)
    ReportGeneratorDomainManger.generate_async(socket.assigns.selected, element)

    {:noreply,
     socket
     |> assign(:generating, MapSet.put(socket.assigns.generating, element_id))
     |> assign(:generation_errors, Map.delete(socket.assigns.generation_errors, element_id))}
  end

  def handle_info({:elements_loaded, {:ok, elements}}, socket) do
    # Auto-select first element if none selected
    selected_element_id =
      if is_nil(socket.assigns.selected_element_id) && elements != [] do
        List.first(elements)["id"]
      else
        socket.assigns.selected_element_id
      end

    {:noreply,
     socket
     |> assign(:elements, elements)
     |> assign(:loading_elements, false)
     |> assign(:selected_element_id, selected_element_id)}
  end

  def handle_info({:elements_loaded, _error}, socket) do
    {:noreply, assign(socket, :loading_elements, false)}
  end

  def handle_info({:report_items_loaded, {:ok, items_map}}, socket) do
    {:noreply, assign(socket, :report_items, items_map)}
  end

  def handle_info({:report_items_loaded, _error}, socket) do
    {:noreply, socket}
  end

  # Only manages the element-level generating state for the detail panel.
  # generating_per_code/generating_all are owned by SyllabusSearchResultsList.
  def handle_info(%ReportGenerationStatus.PendingUpdate{pending: pending}, socket) do
    socket =
      if socket.assigns.selected do
        code = socket.assigns.selected["code"]

        generating =
          pending
          |> Enum.filter(fn {c, _} -> c == code end)
          |> Enum.map(fn {_, el_id} -> el_id end)
          |> MapSet.new()

        assign(socket, :generating, generating)
      else
        socket
      end

    {:noreply, socket}
  end

  # Only manages detail panel state. report_counts are owned by SyllabusSearchResultsList.
  def handle_info(
        %ReportGenerationStatus.ItemResult{
          code: code,
          element_id: element_id,
          result: {:ok, item}
        },
        socket
      ) do
    socket =
      if socket.assigns.selected && socket.assigns.selected["code"] == code do
        socket
        |> assign(:report_items, Map.put(socket.assigns.report_items, element_id, item))
        |> assign(:generating, MapSet.delete(socket.assigns.generating, element_id))
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(%ReportGenerationStatus.ItemResult{result: {:error, _reason}}, socket) do
    {:noreply, socket}
  end

  def handle_info(message, _socket) do
    Logger.warning("ReportHandlers: unhandled handle_info message: #{inspect(message)}")
    :unhandled
  end

  def clear_detail(socket) do
    socket
    |> assign(:selected, nil)
    |> assign(:selected_element_id, nil)
    |> assign(:report_items, %{})
    |> assign(:generating, MapSet.new())
    |> assign(:generation_errors, %{})
  end

  def mount_assigns(socket) do
    ReportGeneratorDomainManger.request_elements(self())

    socket
    |> assign(:elements, [])
    |> assign(:loading_detail, false)
    |> assign(:detail_error, nil)
    |> assign(:selected_element_id, nil)
    |> assign(:report_items, %{})
    |> assign(:generating, MapSet.new())
    |> assign(:generation_errors, %{})
    |> assign(:correcting_element_id, nil)
    |> assign(:loading_elements, true)
  end
end
