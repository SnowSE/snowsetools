defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusLive do
  use SimpleSyllabusReporterWeb, :live_view
  require Logger

  alias SimpleSyllabusReporterWeb.Syllabus.ReportHandlers
  alias SimpleSyllabusReporterWeb.Syllabus.SyllabusSearchResultsList
  alias SimpleSyllabusReporterWeb.Syllabus.SyllabusDetail
  alias SimpleSyllabusReporterWeb.Syllabus.SearchQuickNavigation
  alias SimpleSyllabusReporterWeb.Syllabus.SyllabusSearchForm
  alias SimpleSyllabusReporter.Syllabi.SyllabusDomainManager
  alias SimpleSyllabusReporter.Reports.ReportGenerationStatus
  alias SimpleSyllabusReporter.Reports.ReportGeneratorDomainManger

  on_mount {SimpleSyllabusReporterWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    if connected?(socket), do: ReportGenerationStatus.subscribe()

    socket =
      socket
      |> assign(:page_title, "Syllabus Search")
      |> assign(:query, "")
      |> assign(:selected, nil)
      |> assign(:loading_detail, false)
      |> assign(:detail_error, nil)
      |> assign(:search_error, nil)
      |> ReportHandlers.mount_assigns()

    {:ok, socket}
  end

  def handle_params(%{"q" => query} = params, _uri, socket) do
    code = params["code"]
    title = params["title"]
    term = params["term"] || ""
    prev_code = socket.assigns.selected && socket.assigns.selected["code"]
    code_changed? = code != prev_code

    socket = assign(socket, :query, query)

    socket =
      cond do
        code && code_changed? ->
          ReportGeneratorDomainManger.request_items_for_code(code, self())

          socket
          |> ReportHandlers.clear_detail()
          |> assign(:loading_detail, true)
          |> assign(:detail_error, nil)
          |> assign(:selected, %{
            "code" => code,
            "title" => (socket.assigns.selected || %{})["title"] || title || code,
            "term" => term
          })
          |> assign(:generating, MapSet.new())
          |> start_async(:fetch_detail, fn -> SyllabusDomainManager.get_detail(code) end)

        is_nil(code) && code_changed? ->
          ReportHandlers.clear_detail(socket)

        true ->
          socket
      end

    {:noreply, push_event(socket, "save_state", %{query: query})}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("restore_state", %{"query" => query}, socket)
      when is_binary(query) and byte_size(query) > 0 do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}
  end

  def handle_event("restore_state", _params, socket), do: {:noreply, socket}

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}
  end

  @detail_events ~w[
    select_element
    open_correction
    cancel_correction
    save_correction
    generate_report
    generate_missing_for_selected
  ]

  def handle_event(event, params, socket) when event in @detail_events do
    ReportHandlers.handle_event(event, params, socket)
  end

  def handle_async(:fetch_detail, {:ok, {:ok, doc}}, socket) do
    prev = socket.assigns.selected

    merged =
      Map.merge(doc, %{"code" => prev["code"], "title" => prev["title"], "term" => prev["term"]})

    {:noreply, socket |> assign(:loading_detail, false) |> assign(:selected, merged)}
  end

  def handle_async(:fetch_detail, {:ok, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:loading_detail, false) |> assign(:detail_error, reason)}
  end

  def handle_async(:fetch_detail, {:exit, reason}, socket) do
    {:noreply, socket |> assign(:loading_detail, false) |> assign(:detail_error, inspect(reason))}
  end

  def handle_info({:quick_nav, query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}
  end

  def handle_info({:report_counts_loaded, result}, socket) do
    Phoenix.LiveView.send_update(SyllabusSearchResultsList,
      id: "search-results",
      report_counts_loaded: result
    )

    {:noreply, socket}
  end

  def handle_info(%ReportGenerationStatus.PendingUpdate{pending: pending} = msg, socket) do
    Phoenix.LiveView.send_update(SyllabusSearchResultsList,
      id: "search-results",
      pending_update: pending
    )

    ReportHandlers.handle_info(msg, socket)
  end

  def handle_info(
        %ReportGenerationStatus.ItemResult{
          code: code,
          element_id: element_id,
          result: {:ok, item}
        } =
          msg,
        socket
      ) do
    old_status = get_in(socket.assigns.report_items, [element_id, "status"])
    new_status = item["status"]

    Phoenix.LiveView.send_update(SyllabusSearchResultsList,
      id: "search-results",
      report_counts_update: {code, old_status, new_status}
    )

    ReportHandlers.handle_info(msg, socket)
  end

  def handle_info(message, socket) do
    case ReportHandlers.handle_info(message, socket) do
      :unhandled ->
        Logger.warning(
          "SyllabusLive: completely unhandled handle_info message: #{inspect(message)}"
        )

        {:noreply, socket}

      result ->
        result
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div
        id="syllabus-page"
        phx-hook=".SyllabusState"
        class="flex flex-col h-full min-h-0 max-w-[2000px] mx-auto w-full p-4"
      >
        <.live_component
          module={SearchQuickNavigation}
          id="quick-navigation"
          current_user={@current_user}
          active_query={@query}
        />
        <SyllabusSearchForm.search_form
          query={@query}
          loading_search={false}
        />

        <%= if @search_error do %>
          <div
            id="search-error"
            class="mb-3 rounded-lg bg-red-900/40 border border-red-700 px-4 py-3 text-red-300 text-sm"
          >
            {@search_error}
          </div>
        <% end %>

        <div class="flex gap-6 min-h-0 flex-1 overflow-hidden">
          <.live_component
            module={SyllabusSearchResultsList}
            id="search-results"
            query={@query}
            selected={@selected}
            elements={@elements}
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
              correcting_element_id={@correcting_element_id}
            />
          <% else %>
            <SyllabusDetail.detail_panel_placeholder />
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
