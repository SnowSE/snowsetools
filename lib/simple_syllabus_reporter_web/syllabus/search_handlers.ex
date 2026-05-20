defmodule SimpleSyllabusReporterWeb.Syllabus.SearchHandlers do
  import Phoenix.LiveView
  import Phoenix.Component

  use SimpleSyllabusReporterWeb, :verified_routes

  alias SimpleSyllabusReporter.Syllabi.SyllabusManager
  alias SimpleSyllabusReporter.Reports.GeneratedReportDB
  alias SimpleSyllabusReporter.Reports.GeneratedReportItemDB
  alias SimpleSyllabusReporter.Reports.ReportGenerationStatus
  alias SimpleSyllabusReporter.Reports.RequiredReportElementCoverageCache

  def handle_params(%{"q" => query} = params, socket) when byte_size(query) > 0 do
    code = params["code"]
    title = params["title"]
    term = params["term"] || ""
    prev_query = socket.assigns.query
    prev_code = socket.assigns[:selected] && socket.assigns.selected["code"]

    query_changed? = query != prev_query
    code_changed? = code != prev_code

    socket =
      cond do
        not query_changed? ->
          socket

        email?(query) ->
          socket
          |> reset_for_search(query, nil)
          |> start_async(:search, fn -> SyllabusManager.search_by_email(query) end)

        socket.assigns.departments == [] ->
          socket
          |> reset_for_search(query, nil)
          |> assign(:search_pending?, true)

        dept = find_department(socket.assigns.departments, query) ->
          org_id = dept["entity_id"]

          socket
          |> reset_for_search(query, org_id)
          |> start_async(:search, fn -> SyllabusManager.search_by_org(org_id) end)

        true ->
          assign(socket,
            query: query,
            search_error: "Department not found",
            loading_search: false
          )
      end

    socket =
      cond do
        code && code_changed? ->
          socket
          |> clear_detail()
          |> assign(:loading_detail, true)
          |> assign(:detail_error, nil)
          |> assign(:selected, %{
            "code" => code,
            "title" => (socket.assigns.selected || %{})["title"] || title || code,
            "term" => term
          })
          |> assign(:generating, Map.get(socket.assigns.generating_per_code, code, MapSet.new()))
          |> start_async(:fetch_detail, fn -> SyllabusManager.get_detail(code) end)
          |> start_async(:fetch_existing_items, fn -> existing_items_for_code(code) end)

        is_nil(code) && code_changed? ->
          socket
          |> clear_detail()

        true ->
          socket
      end

    {:noreply, push_event(socket, "save_state", %{query: query})}
  end

  def handle_params(_params, socket) do
    {:noreply, socket}
  end

  def handle_event("restore_state", %{"query" => query}, socket)
      when is_binary(query) and byte_size(query) > 0 do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}
  end

  def handle_event("restore_state", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "quick_nav",
        %{"type" => "division", "name" => name},
        socket
      ) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{name}")}
  end

  def handle_event("quick_nav", %{"type" => "my_syllabi"}, socket) do
    email = socket.assigns.current_user.email
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{email}")}
  end

  def handle_event("search", %{"query" => query}, socket) do
    cond do
      email?(query) ->
        {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}

      find_department(socket.assigns.departments, query) ->
        {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}

      true ->
        {:noreply,
         assign(
           socket,
           :search_error,
           "Please select a department from the list or enter an email address"
         )}
    end
  end

  def handle_event("select", %{"code" => code, "title" => title, "term" => term}, socket) do
    query = socket.assigns.query

    {:noreply,
     push_patch(socket, to: ~p"/syllabi?q=#{query}&code=#{code}&title=#{title}&term=#{term}")}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{socket.assigns.query}")}
  end

  defp clear_detail(socket) do
    socket
    |> assign(:selected, nil)
    |> assign(:selected_element_id, nil)
    |> assign(:report_items, %{})
    |> assign(:generating, MapSet.new())
    |> assign(:generation_errors, %{})
  end

  defp reset_for_search(socket, query, org_id) do
    socket
    |> assign(:query, query)
    |> assign(:org_id, org_id)
    |> assign(:search_pending?, false)
    |> assign(:loading_search, true)
    |> assign(:search_error, nil)
    |> assign(:syllabi_empty?, true)
  end

  defp find_department(departments, name) do
    Enum.find(departments, &(String.downcase(&1["name"]) == String.downcase(name)))
  end

  defp email?(query), do: Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, query)

  def handle_async(:search, {:ok, {:ok, %{items: docs, cached_at: cached_at}}}, socket) do
    codes = Enum.map(docs, & &1["code"])

    if connected?(socket) do
      ReportGenerationStatus.request_pending(codes)
      RequiredReportElementCoverageCache.set_syllabi_codes(codes)
    end

    socket =
      socket
      |> assign(:loading_search, false)
      |> assign(:search_cached_at, cached_at)
      |> assign(:syllabi_empty?, docs == [])
      |> assign(:syllabi_docs, Map.new(docs, &{&1["code"], &1}))
      |> start_async(:fetch_report_counts, fn ->
        GeneratedReportItemDB.item_counts_for_syllabi(codes)
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
    {:noreply, assign(socket, :report_counts, counts)}
  end

  def handle_async(:fetch_report_counts, _result, socket) do
    {:noreply, socket}
  end

  def handle_async(:fetch_departments, {:ok, {:ok, departments}}, socket) do
    socket = assign(socket, :departments, departments)

    socket =
      if socket.assigns.search_pending? do
        query = socket.assigns.query

        case find_department(departments, query) do
          nil ->
            assign(socket,
              loading_search: false,
              search_error: "Department not found",
              search_pending?: false
            )

          dept ->
            org_id = dept["entity_id"]

            socket
            |> assign(:org_id, org_id)
            |> assign(:search_pending?, false)
            |> start_async(:search, fn -> SyllabusManager.search_by_org(org_id) end)
        end
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:fetch_departments, _result, socket) do
    {:noreply, socket}
  end

  defp existing_items_for_code(code) do
    case GeneratedReportDB.get_latest_for_syllabus(code) do
      {:ok, report} -> GeneratedReportItemDB.list_for_report_as_map(report["id"])
      {:error, :not_found} -> {:ok, %{}}
      {:error, _} = err -> err
    end
  end
end
