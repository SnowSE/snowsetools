defmodule SnowSeToolsWeb.Syllabus.SyllabusSearchLive do
  use SnowSeToolsWeb, :live_view
  require Logger

  alias SnowSeToolsWeb.Syllabus.ReportHandlers
  alias SnowSeToolsWeb.Syllabus.SyllabusSearchResultsList
  alias SnowSeToolsWeb.Syllabus.SyllabusDetail
  alias SnowSeToolsWeb.Syllabus.SearchQuickNavigation
  alias SnowSeToolsWeb.Syllabus.SyllabusSearchForm
  alias SnowSeTools.Syllabi.SyllabusDomainManager
  alias SnowSeTools.Syllabi.AvailableTermsDb
  alias SnowSeTools.Reports.ReportGenerationStatus
  alias SnowSeTools.Reports.ReportGeneratorDomainManger

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, session, socket) do
    parent_pid =
      if pid_str = session["parent_pid"] do
        pid_str |> String.to_charlist() |> :erlang.list_to_pid()
      end

    if connected?(socket) do
      ReportGenerationStatus.subscribe()

      if parent_pid do
        send(parent_pid, {:syllabus_search_live_ready, self()})
      end
    end

    available_terms = list_available_terms()

    socket =
      socket
      |> assign(:page_title, "Syllabus Search")
      |> assign(:query, "")
      |> assign(:available_terms, available_terms)
      |> assign(:selected_term_id, default_term_id(available_terms))
      |> assign(
        :selected_term_name,
        find_term_name(available_terms, default_term_id(available_terms))
      )
      |> assign(:selected, nil)
      |> assign(:loading_detail, false)
      |> assign(:detail_error, nil)
      |> assign(:search_error, nil)
      |> assign(:parent_pid, parent_pid)
      |> ReportHandlers.mount_assigns()

    {:ok, socket}
  end

  def handle_event("restore_state", %{"query" => query} = params, socket)
      when is_binary(query) and byte_size(query) > 0 do
    socket = maybe_restore_term(params, socket)

    if pid = socket.assigns.parent_pid do
      send(pid, {:search_navigate, query})
    end

    {:noreply, socket}
  end

  def handle_event("restore_state", _params, socket), do: {:noreply, socket}

  def handle_event("search", %{"query" => query}, socket) do
    if pid = socket.assigns.parent_pid do
      send(pid, {:search_navigate, query})
    end

    {:noreply, socket}
  end

  def handle_event("set_search_term", %{"term_id" => term_id}, socket) do
    selected_term_id = normalize_term_id(term_id)

    socket =
      socket
      |> assign(:selected_term_id, selected_term_id)
      |> assign(
        :selected_term_name,
        find_term_name(socket.assigns.available_terms, selected_term_id)
      )
      |> ReportHandlers.clear_detail()

    {:noreply, push_event(socket, "save_state", state_payload(socket))}
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

  def handle_info({:navigate_params, params}, socket) do
    query = params["q"] || ""
    code = params["code"]
    title = params["title"]
    term = params["term"] || ""
    prev_code = socket.assigns.selected && socket.assigns.selected["code"]
    code_changed? = code != prev_code

    socket = assign(socket, :query, query)

    socket =
      cond do
        code && code_changed? && snow_course_params?(params) ->
          socket
          |> ReportHandlers.clear_detail()
          |> assign(:loading_detail, false)
          |> assign(:detail_error, nil)
          |> assign(:selected, snow_course_selection(params))

        code && code_changed? ->
          term_id = socket.assigns.selected_term_id
          ReportGeneratorDomainManger.request_items_for_code(code, self(), term_id: term_id)

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
          |> start_async(:fetch_detail, fn ->
            SyllabusDomainManager.get_detail(code, term_id: term_id)
          end)

        is_nil(code) && code_changed? ->
          ReportHandlers.clear_detail(socket)

        true ->
          socket
      end

    {:noreply, push_event(socket, "save_state", state_payload(socket))}
  end

  def handle_info({:quick_nav, query}, socket) do
    if pid = socket.assigns.parent_pid do
      send(pid, {:search_navigate, query})
    end

    {:noreply, socket}
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
          "SyllabusSearchLive: completely unhandled handle_info message: #{inspect(message)}"
        )

        {:noreply, socket}

      result ->
        result
    end
  end

  def render(assigns) do
    ~H"""
    <div
      id="syllabus-search-panel"
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
        available_terms={@available_terms}
        selected_term_id={@selected_term_id}
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
          selected_term_id={@selected_term_id}
          selected_term_name={@selected_term_name}
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

  defp list_available_terms do
    case AvailableTermsDb.list_active_terms() do
      {:ok, terms} ->
        terms

      {:error, reason} ->
        Logger.error("SyllabusSearchLive: failed to load available terms: #{inspect(reason)}")
        []
    end
  end

  defp normalize_term_id(term_id) when is_binary(term_id) and byte_size(term_id) == 0, do: nil
  defp normalize_term_id(term_id) when is_binary(term_id), do: term_id
  defp normalize_term_id(_term_id), do: nil

  defp default_term_id([]), do: nil

  defp default_term_id(terms) do
    now = Date.utc_today()

    {term_id, _name} =
      Enum.min_by(terms, fn {_id, name} ->
        {year, season} = parse_season_year(name)
        target_month = season_month(season)
        target = Date.new!(year, target_month, 15)
        abs(Date.diff(target, now))
      end)

    term_id
  end

  defp parse_season_year(name) do
    today = Date.utc_today()

    case String.split(name, " ", parts: 2) do
      [season, year_str] ->
        with {year, _} <- Integer.parse(year_str) do
          {year, String.downcase(season)}
        else
          _ -> {today.year, :unknown}
        end

      _ ->
        {today.year, :unknown}
    end
  end

  defp season_month("fall"), do: 9
  defp season_month("spring"), do: 3
  defp season_month("summer"), do: 6
  defp season_month(_), do: 1

  defp find_term_name(terms, term_id) do
    Enum.find_value(terms, term_id, fn {id, name} ->
      if id == term_id, do: name
    end)
  end

  defp maybe_restore_term(%{"term_id" => term_id}, socket) do
    selected_term_id = normalize_term_id(term_id)

    socket
    |> assign(:selected_term_id, selected_term_id)
    |> assign(
      :selected_term_name,
      find_term_name(socket.assigns.available_terms, selected_term_id)
    )
  end

  defp maybe_restore_term(_params, socket), do: socket

  defp state_payload(socket) do
    %{query: socket.assigns.query, term_id: socket.assigns.selected_term_id}
  end

  defp snow_course_params?(%{"source" => "snow_courses"}), do: true
  defp snow_course_params?(_params), do: false

  defp snow_course_selection(params) do
    %{
      "code" => params["code"],
      "title" => params["title"] || params["code"],
      "term" => params["term"] || "",
      "term_name" => params["term"] || "",
      "source" => "snow_courses",
      "syllabus_status" => "unpublished",
      "snow_course" => %{
        "term_code" => params["term_code"] || "",
        "crn" => params["crn"] || "",
        "subject_code" => params["subject_code"] || "",
        "course_number" => params["course_number"] || "",
        "section_number" => params["section_number"] || "",
        "course_name" => params["course_name"] || "",
        "primary_instructor_name" => params["primary_instructor_name"] || ""
      }
    }
  end
end
