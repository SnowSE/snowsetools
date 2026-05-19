defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusLive do
  use SimpleSyllabusReporterWeb, :live_view

  alias SimpleSyllabusReporterWeb.Syllabus.SearchHandlers
  alias SimpleSyllabusReporterWeb.Syllabus.ReportHandlers
  alias SimpleSyllabusReporterWeb.Syllabus.SyllabusDetail
  alias SimpleSyllabusReporterWeb.Syllabus.SearchQuickNavigation
  alias SimpleSyllabusReporterWeb.Syllabus.SyllabusSearchForm
  alias SimpleSyllabusReporterWeb.Syllabus.SyllabusSearchResultsList

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
      |> assign(:report_counts, %{})
      |> assign(:departments, [])
      |> assign(:org_id, nil)
      |> ReportHandlers.mount_assigns()

    socket =
      if connected?(socket) do
        start_async(socket, :fetch_departments, fn ->
          SimpleSyllabusReporter.SimpleSyllabusApi.get_departments()
        end)
      else
        socket
      end

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    SearchHandlers.handle_params(params, socket)
  end

  @search_events ~w[
    restore_state
    quick_nav
    search
    select
    close_detail
  ]
  @report_events ~w[
    select_element
    open_correction
    cancel_correction
    save_correction
    generate_report
    generate_missing_for_selected
    generate_all_missing
    generate_missing_for_professor
    regenerate_non_met
  ]

  def handle_event(event, params, socket) when event in @search_events do
    SearchHandlers.handle_event(event, params, socket)
  end

  def handle_event(event, params, socket) when event in @report_events do
    ReportHandlers.handle_event(event, params, socket)
  end

  def handle_async(task, result, socket)
      when task in [:search, :fetch_detail, :fetch_report_counts, :fetch_departments] do
    SearchHandlers.handle_async(task, result, socket)
  end

  def handle_async(task, result, socket)
      when task in [:fetch_elements, :fetch_existing_items] do
    ReportHandlers.handle_async(task, result, socket)
  end

  def handle_info(message, socket) do
    ReportHandlers.handle_info(message, socket)
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
        <SearchQuickNavigation.quick_navigation
          departments={@departments}
          current_user={@current_user}
          active_query={@query}
        />
        <SyllabusSearchForm.search_form
          query={@query}
          loading_search={@loading_search}
          departments={@departments}
        />

        <%= if @search_error do %>
          <div
            id="search-error"
            class="mb-6 rounded-lg bg-red-900/40 border border-red-700 px-4 py-3 text-red-300 text-sm"
          >
            Error: {@search_error}
          </div>
        <% end %>

        <div class="flex gap-6 min-h-0 flex-1 overflow-hidden">
          <SyllabusSearchResultsList.results_list
            syllabi_docs={@syllabi_docs}
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
