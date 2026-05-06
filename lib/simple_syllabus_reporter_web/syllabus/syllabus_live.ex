defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusLive do
  use SimpleSyllabusReporterWeb, :live_view

  alias SimpleSyllabusReporter.SimpleSyllabusApi
  alias SimpleSyllabusReporter.Reports.RequiredElement
  alias SimpleSyllabusReporter.Reports.GeneratedReport
  alias SimpleSyllabusReporter.Reports.GeneratedReportItem
  alias SimpleSyllabusReporter.Reports.ReportGenerator
  alias SimpleSyllabusReporter.Reports.ReportGenerationStatus
  alias SimpleSyllabusReporterWeb.Syllabus.SyllabusDetail
  alias SimpleSyllabusReporterWeb.Syllabus.SyllabusResultsList

  on_mount {SimpleSyllabusReporterWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Syllabus Search")
      |> assign(:query, "")
      |> assign(:loading_search, false)
      |> assign(:loading_detail, false)
      |> assign(:search_error, nil)
      |> assign(:detail_error, nil)
      |> assign(:selected, nil)
      |> stream_configure(:syllabi, dom_id: fn item -> item["code"] end)
      |> stream(:syllabi, [])
      |> assign(:syllabi_empty?, true)
      |> assign(:syllabi_docs, %{})
      |> assign(:elements, [])
      |> assign(:total_elements, 0)
      |> assign(:report_counts, %{})
      |> assign(:generating_per_code, %{})
      |> assign(:generating_all, false)
      |> assign(:selected_element_id, nil)
      |> assign(:report_items, %{})
      |> assign(:generating, MapSet.new())
      |> assign(:generation_errors, %{})
      |> assign(:loading_elements, true)
      |> start_async(:fetch_elements, fn -> RequiredElement.list_all() end)

    {:ok, socket}
  end

  def handle_params(%{"q" => query} = params, _uri, socket) when byte_size(query) > 0 do
    code = params["code"]
    title = params["title"]
    term = params["term"] || ""
    prev_query = socket.assigns.query
    prev_code = socket.assigns[:selected] && socket.assigns.selected["code"]

    query_changed? = query != prev_query
    code_changed? = code != prev_code

    socket =
      if query_changed? do
        socket
        |> assign(:query, query)
        |> assign(:loading_search, true)
        |> assign(:search_error, nil)
        |> stream(:syllabi, [], reset: true)
        |> assign(:syllabi_empty?, true)
        |> start_async(:search, fn -> SimpleSyllabusApi.search_syllabi(query) end)
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
          |> assign(:generating, MapSet.new())
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
     push_event(socket, "save_state", %{query: query, code: code, title: title, term: term})}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("restore_state", %{"query" => query} = params, socket)
      when is_binary(query) and byte_size(query) > 0 do
    to =
      case params do
        %{"code" => code, "title" => title, "term" => term} when is_binary(code) ->
          ~p"/syllabi?q=#{query}&code=#{code}&title=#{title}&term=#{term}"

        _ ->
          ~p"/syllabi?q=#{query}"
      end

    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("restore_state", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}
  end

  def handle_event("select", %{"code" => code, "title" => title, "term" => term}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/syllabi?q=#{socket.assigns.query}&code=#{code}&title=#{title}&term=#{term}"
     )}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{socket.assigns.query}")}
  end

  def handle_event("select_element", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_element_id, id)}
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
    socket =
      socket
      |> assign(:loading_search, false)
      |> assign(:search_error, reason)

    {:noreply, socket}
  end

  def handle_async(:search, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:loading_search, false)
      |> assign(:search_error, inspect(reason))

    {:noreply, socket}
  end

  def handle_async(:fetch_detail, {:ok, {:ok, doc}}, socket) do
    prev = socket.assigns.selected

    merged =
      Map.merge(doc, %{
        "code" => prev["code"],
        "title" => prev["title"],
        "term" => prev["term"]
      })

    socket =
      socket
      |> assign(:loading_detail, false)
      |> assign(:selected, merged)

    {:noreply, socket}
  end

  def handle_async(:fetch_detail, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:loading_detail, false)
      |> assign(:detail_error, reason)

    {:noreply, socket}
  end

  def handle_async(:fetch_detail, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:loading_detail, false)
      |> assign(:detail_error, inspect(reason))

    {:noreply, socket}
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
       |> reinsert_syllabus(socket.assigns.syllabi_docs, code)}
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

    report_counts =
      Map.update(
        socket.assigns.report_counts,
        code,
        %{status => 1},
        fn counts -> Map.update(counts, status, 1, &(&1 + 1)) end
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
     |> reinsert_syllabus(socket.assigns.syllabi_docs, code)}
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

  defp reinsert_syllabus(socket, _docs_by_code, nil), do: socket

  defp reinsert_syllabus(socket, docs_by_code, code) do
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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div
        id="syllabus-page"
        phx-hook=".SyllabusState"
        class="flex flex-col h-full min-h-0 max-w-5xl mx-auto w-full p-4"
      >
        <form id="syllabus-search-form" phx-submit="search" class="flex gap-3 pb-3">
          <input
            id="search-query-input"
            type="text"
            name="query"
            value={@query}
            placeholder="instructor name, coure code, instructor email, department"
            class="flex-1 bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition"
            autofocus
          />
          <button
            type="submit"
            id="search-submit-btn"
            disabled={@loading_search}
            class="px-5 py-2.5 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-medium rounded-lg transition-colors"
          >
            <%= if @loading_search do %>
              Searching…
            <% else %>
              Search
            <% end %>
          </button>
        </form>

        <%= if @search_error do %>
          <div
            id="search-error"
            class="mb-6 rounded-lg bg-red-900/40 border border-red-700 px-4 py-3 text-red-300 text-sm"
          >
            Error: {@search_error}
          </div>
        <% end %>

        <div class="flex gap-6 min-h-0 flex-1 overflow-hidden">
          <SyllabusResultsList.results_list
            syllabi={@streams.syllabi}
            syllabi_empty?={@syllabi_empty?}
            query={@query}
            loading_search={@loading_search}
            selected={@selected}
            total_elements={@total_elements}
            syllabi_count={map_size(@syllabi_docs)}
            report_counts={@report_counts}
            generating_per_code={@generating_per_code}
            generating_all={@generating_all}
          />

          <%= if @selected do %>
            <SyllabusDetail.detail_panel
              selected={@selected}
              loading_detail={@loading_detail}
              detail_error={@detail_error}
              elements={@elements}
              loading_elements={@loading_elements}
              selected_element_id={@selected_element_id}
              report_items={@report_items}
              generating={@generating}
              generation_errors={@generation_errors}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SyllabusState">
      export default {
        mounted() {
          const url = new URL(window.location.href);
          if (!url.searchParams.has("q")) {
            try {
              const stored = localStorage.getItem("syllabi_state");
              if (stored) {
                const state = JSON.parse(stored);
                if (state && state.query) {
                  this.pushEvent("restore_state", state);
                }
              }
            } catch (e) {
              console.error("SyllabusState: failed to read localStorage", e);
            }
          }

          this.handleEvent("save_state", (data) => {
            try {
              localStorage.setItem("syllabi_state", JSON.stringify(data));
            } catch (e) {
              console.error("SyllabusState: failed to write localStorage", e);
            }
          });
        }
      }
    </script>
    """
  end
end
