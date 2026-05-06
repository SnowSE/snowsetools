defmodule SimpleSyllabusReporterWeb.Syllabus.SearchHandlers do
  import Phoenix.LiveView
  import Phoenix.Component

  use SimpleSyllabusReporterWeb, :verified_routes

  alias SimpleSyllabusReporter.SimpleSyllabusApi
  alias SimpleSyllabusReporter.Reports.GeneratedReport
  alias SimpleSyllabusReporter.Reports.GeneratedReportItem
  alias SimpleSyllabusReporter.Reports.ReportGenerationStatus

  def handle_params(%{"q" => query} = params, socket) when byte_size(query) > 0 do
    org_id = params["org_id"]
    code = params["code"]
    title = params["title"]
    term = params["term"] || ""
    prev_query = socket.assigns.query
    prev_code = socket.assigns[:selected] && socket.assigns.selected["code"]

    query_changed? = query != prev_query
    code_changed? = code != prev_code

    socket =
      if query_changed? and is_binary(org_id) do
        socket
        |> assign(:query, query)
        |> assign(:org_id, org_id)
        |> assign(:loading_search, true)
        |> assign(:search_error, nil)
        |> stream(:syllabi, [], reset: true)
        |> assign(:syllabi_empty?, true)
        |> start_async(:search, fn -> SimpleSyllabusApi.search_syllabi(org_id) end)
      else
        socket
      end

    socket =
      cond do
        code && code_changed? ->
          docs_by_code = socket.assigns.syllabi_docs

          socket
          |> reinsert_syllabus(docs_by_code, prev_code)
          |> reinsert_syllabus(docs_by_code, code)
          |> assign(:loading_detail, true)
          |> assign(:detail_error, nil)
          |> assign(:selected, %{
            "code" => code,
            "title" => (socket.assigns.selected || %{})["title"] || title || code,
            "term" => term
          })
          |> assign(:selected_element_id, nil)
          |> assign(:report_items, %{})
          |> assign(:generating, Map.get(socket.assigns.generating_per_code, code, MapSet.new()))
          |> assign(:generation_errors, %{})
          |> start_async(:fetch_detail, fn -> SimpleSyllabusApi.get_syllabus_details(code) end)
          |> start_async(:fetch_existing_items, fn -> existing_items_for_code(code) end)

        is_nil(code) && code_changed? ->
          socket
          |> reinsert_syllabus(socket.assigns.syllabi_docs, prev_code)
          |> assign(:selected, nil)
          |> assign(:selected_element_id, nil)
          |> assign(:report_items, %{})
          |> assign(:generating, MapSet.new())
          |> assign(:generation_errors, %{})

        true ->
          socket
      end

    {:noreply,
     push_event(socket, "save_state", %{
       query: query,
       org_id: org_id,
       code: code,
       title: title,
       term: term
     })}
  end

  def handle_params(_params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "restore_state",
        %{"query" => query, "org_id" => org_id} = params,
        socket
      )
      when is_binary(query) and byte_size(query) > 0 do
    to =
      case params do
        %{"code" => code, "title" => title, "term" => term} when is_binary(code) ->
          ~p"/syllabi?q=#{query}&org_id=#{org_id}&code=#{code}&title=#{title}&term=#{term}"

        _ ->
          ~p"/syllabi?q=#{query}&org_id=#{org_id}"
      end

    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("restore_state", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    case find_department(socket.assigns.departments, query) do
      %{"entity_id" => org_id} ->
        {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}&org_id=#{org_id}")}

      nil ->
        {:noreply, assign(socket, :search_error, "Please select a department from the list")}
    end
  end

  def handle_event("select", %{"code" => code, "title" => title, "term" => term}, socket) do
    params = %{
      "q" => socket.assigns.query,
      "org_id" => socket.assigns.org_id,
      "code" => code,
      "title" => title,
      "term" => term
    }

    {:noreply, push_patch(socket, to: ~p"/syllabi?#{params}")}
  end

  def handle_event("close_detail", _params, socket) do
    params = %{"q" => socket.assigns.query, "org_id" => socket.assigns.org_id}
    {:noreply, push_patch(socket, to: ~p"/syllabi?#{params}")}
  end

  defp find_department(departments, name) do
    Enum.find(departments, &(String.downcase(&1["name"]) == String.downcase(name)))
  end

  def handle_async(:search, {:ok, {:ok, %{items: docs}}}, socket) do
    codes = Enum.map(docs, & &1["code"])

    if connected?(socket) do
      Enum.each(codes, fn code -> ReportGenerationStatus.subscribe(code) end)
      ReportGenerationStatus.request_pending(codes)
    end

    socket =
      socket
      |> assign(:loading_search, false)
      |> assign(:syllabi_empty?, docs == [])
      |> assign(:syllabi_docs, Map.new(docs, &{&1["code"], &1}))
      |> stream(:syllabi, docs, reset: true)
      |> start_async(:fetch_report_counts, fn ->
        GeneratedReportItem.item_counts_for_syllabi(codes)
      end)

    {:noreply, socket}
  end

  def handle_async(:search, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:loading_search, false)
     |> assign(:search_error, reason)}
  end

  def handle_async(:search, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading_search, false)
     |> assign(:search_error, inspect(reason))}
  end

  def handle_async(:fetch_detail, {:ok, {:ok, doc}}, socket) do
    prev = socket.assigns.selected

    merged =
      Map.merge(doc, %{
        "code" => prev["code"],
        "title" => prev["title"],
        "term" => prev["term"]
      })

    {:noreply,
     socket
     |> assign(:loading_detail, false)
     |> assign(:selected, merged)}
  end

  def handle_async(:fetch_detail, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:loading_detail, false)
     |> assign(:detail_error, reason)}
  end

  def handle_async(:fetch_detail, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading_detail, false)
     |> assign(:detail_error, inspect(reason))}
  end

  def handle_async(:fetch_report_counts, {:ok, {:ok, counts}}, socket) do
    socket =
      socket.assigns.syllabi_docs
      |> Map.values()
      |> Enum.reduce(assign(socket, :report_counts, counts), fn doc, acc ->
        stream_insert(acc, :syllabi, doc)
      end)

    {:noreply, socket}
  end

  def handle_async(:fetch_report_counts, _result, socket) do
    {:noreply, socket}
  end

  def handle_async(:fetch_departments, {:ok, {:ok, departments}}, socket) do
    {:noreply, assign(socket, :departments, departments)}
  end

  def handle_async(:fetch_departments, _result, socket) do
    {:noreply, socket}
  end

  def reinsert_syllabus(socket, _docs_by_code, nil), do: socket

  def reinsert_syllabus(socket, docs_by_code, code) do
    case Map.get(docs_by_code, code) do
      nil -> socket
      doc -> stream_insert(socket, :syllabi, doc)
    end
  end

  defp existing_items_for_code(code) do
    case GeneratedReport.get_latest_for_syllabus(code) do
      {:ok, report} -> GeneratedReportItem.list_for_report_as_map(report["id"])
      {:error, :not_found} -> {:ok, %{}}
      {:error, _} = err -> err
    end
  end
end
