defmodule SimpleSyllabusReporterWeb.Syllabus.ReportHandlers do
  import Phoenix.LiveView
  import Phoenix.Component

  use SimpleSyllabusReporterWeb, :verified_routes

  alias SimpleSyllabusReporter.SimpleSyllabusApi
  alias SimpleSyllabusReporter.Reports.RequiredElement
  alias SimpleSyllabusReporter.Reports.GeneratedReport
  alias SimpleSyllabusReporter.Reports.GeneratedReportItem
  alias SimpleSyllabusReporter.Reports.ReportGenerator
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
    Enum.each(missing, fn element -> ReportGenerator.generate_async(selected, element) end)

    missing_ids = MapSet.new(missing, & &1["id"])

    {:noreply, assign(socket, :generating, MapSet.union(socket.assigns.generating, missing_ids))}
  end

  def handle_event("generate_report", %{"id" => element_id}, socket) do
    element = Enum.find(socket.assigns.elements, fn e -> e["id"] == element_id end)
    ReportGenerator.generate_async(socket.assigns.selected, element)

    {:noreply,
     socket
     |> assign(:generating, MapSet.put(socket.assigns.generating, element_id))
     |> assign(:generation_errors, Map.delete(socket.assigns.generation_errors, element_id))}
  end

  def handle_event("generate_all_missing", _params, socket) do
    elements = socket.assigns.elements
    syllabi_docs = socket.assigns.syllabi_docs
    report_counts = socket.assigns.report_counts
    total = socket.assigns.total_elements

    codes_with_missing =
      syllabi_docs
      |> Map.keys()
      |> Enum.filter(fn code ->
        counts = Map.get(report_counts, code, %{})

        total_run =
          Map.get(counts, "met", 0) + Map.get(counts, "not_met", 0) +
            Map.get(counts, "partially_met", 0)

        total_run < total
      end)

    for code <- codes_with_missing do
      Task.start(fn ->
        case SimpleSyllabusApi.get_syllabus_details(code) do
          {:ok, full_doc} ->
            existing_ids = existing_element_ids_for_code(code)
            missing = Enum.reject(elements, fn e -> MapSet.member?(existing_ids, e["id"]) end)

            Enum.each(missing, fn element -> ReportGenerator.generate_async(full_doc, element) end)

          {:error, _} ->
            :ok
        end
      end)
    end

    {:noreply, assign(socket, :generating_all, true)}
  end

  def handle_async(:fetch_elements, {:ok, {:ok, elements}}, socket) do
    {:noreply,
     socket
     |> assign(:elements, elements)
     |> assign(:total_elements, length(elements))
     |> assign(:loading_elements, false)}
  end

  def handle_async(:fetch_elements, _result, socket) do
    {:noreply, assign(socket, :loading_elements, false)}
  end

  def handle_async(:fetch_existing_items, {:ok, {:ok, items_map}}, socket) do
    {:noreply, assign(socket, :report_items, items_map)}
  end

  def handle_async(:fetch_existing_items, _result, socket) do
    {:noreply, socket}
  end

  def handle_info(
        %ReportGenerationStatus.PendingUpdate{code: code, element_ids: element_ids},
        socket
      ) do
    if Map.has_key?(socket.assigns.syllabi_docs, code) do
      generating_per_code = Map.put(socket.assigns.generating_per_code, code, element_ids)

      generating_all =
        Enum.any?(generating_per_code, fn {_, ids} -> not MapSet.equal?(ids, MapSet.new()) end)

      socket =
        if socket.assigns.selected && socket.assigns.selected["code"] == code do
          assign(socket, :generating, element_ids)
        else
          socket
        end

      {:noreply,
       socket
       |> assign(:generating_per_code, generating_per_code)
       |> assign(:generating_all, generating_all)
       |> SimpleSyllabusReporterWeb.Syllabus.SearchHandlers.reinsert_syllabus(
         socket.assigns.syllabi_docs,
         code
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        %ReportGenerationStatus.ItemResult{
          code: code,
          element_id: element_id,
          result: {:ok, item}
        },
        socket
      ) do
    status = item["status"]
    old_status = get_in(socket.assigns.report_items, [element_id, "status"])

    report_counts =
      Map.update(
        socket.assigns.report_counts,
        code,
        %{status => 1},
        fn counts ->
          counts
          |> then(fn c ->
            if old_status,
              do: Map.update(c, old_status, 0, &max(0, &1 - 1)),
              else: c
          end)
          |> Map.update(status, 1, &(&1 + 1))
        end
      )

    socket =
      if socket.assigns.selected && socket.assigns.selected["code"] == code do
        socket
        |> assign(:report_items, Map.put(socket.assigns.report_items, element_id, item))
        |> assign(:generating, MapSet.delete(socket.assigns.generating, element_id))
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:report_counts, report_counts)
     |> SimpleSyllabusReporterWeb.Syllabus.SearchHandlers.reinsert_syllabus(
       socket.assigns.syllabi_docs,
       code
     )}
  end

  def handle_info(%ReportGenerationStatus.ItemResult{result: {:error, _reason}}, socket) do
    {:noreply, socket}
  end

  defp existing_element_ids_for_code(code) do
    with {:ok, report} <- GeneratedReport.get_latest_for_syllabus(code),
         {:ok, items_map} <- GeneratedReportItem.list_for_report_as_map(report["id"]) do
      MapSet.new(Map.keys(items_map))
    else
      _ -> MapSet.new()
    end
  end

  def mount_assigns(socket) do
    socket
    |> assign(:elements, [])
    |> assign(:total_elements, 0)
    |> assign(:generating_per_code, %{})
    |> assign(:generating_all, false)
    |> assign(:selected_element_id, nil)
    |> assign(:report_items, %{})
    |> assign(:generating, MapSet.new())
    |> assign(:generation_errors, %{})
    |> assign(:correcting_element_id, nil)
    |> assign(:loading_elements, true)
    |> start_async(:fetch_elements, fn -> RequiredElement.list_all() end)
  end
end
