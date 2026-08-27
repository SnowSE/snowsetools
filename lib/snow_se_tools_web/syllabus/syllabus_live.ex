defmodule SnowSeToolsWeb.Syllabus.SyllabusLive do
  use SnowSeToolsWeb, :live_view
  require Logger
  alias SnowSeTools.Reports.ReportGeneratorDomainManger
  alias SnowSeTools.Reports.ReportGenerationStatus
  alias SnowSeTools.Syllabi.SyllabusDomainManager
  alias SnowSeTools.Syllabi.AvailableTermsDb

  on_mount {SnowSeToolsWeb.UserAuth, {:ensure_access, :syllabi}}

  def mount(_params, session, socket) do
    socket =
      if connected?(socket) do
        ReportGenerationStatus.subscribe()
        term_id = default_term_id(list_available_terms())
        ReportGeneratorDomainManger.request_totals(self(), term_id: term_id)
        start_async(socket, :fetch_departments, fn -> SyllabusDomainManager.get_departments() end)
      else
        socket
      end

    socket =
      socket
      |> assign(:page_title, "Syllabus Search")
      |> assign(:session_id, session["current_user_id"])
      |> assign(:mode, :search)
      |> assign(:search_live_pid, nil)
      |> assign(:search_params, %{})
      |> assign(:totals, nil)
      |> assign(:by_school, [])
      |> assign(:departments, %{})
      |> assign(:available_terms, list_available_terms())
      |> assign(:selected_term_id, default_term_id(list_available_terms()))
      |> assign(:modes,
        search: "Search Syllabi",
        school_overviews: "School Overviews",
        required_elements: "Required Elements",
        ai_history: "AI History",
        settings: "Settings"
      )

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    query = params["q"] || ""
    mode = mode_from_params(params)

    if search_live = socket.assigns.search_live_pid do
      send(search_live, {:navigate_params, params})
    end

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:mode, mode)
     |> assign(:search_params, params)}
  end

  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)

    {:noreply,
     push_patch(socket, to: syllabus_path(params: socket.assigns.search_params, mode: mode_atom))}
  end

  def handle_info({:search_navigate, query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}
  end

  def handle_info({:totals_loaded, %{"totals" => totals, "by_school" => by_school}}, socket) do
    {:noreply,
     socket
     |> assign(:totals, totals)
     |> assign(:by_school, by_school)}
  end

  def handle_info(%ReportGenerationStatus.PendingUpdate{}, socket) do
    {:noreply, socket}
  end

  def handle_info(%ReportGenerationStatus.ItemResult{}, socket) do
    ReportGeneratorDomainManger.request_totals(self(), term_id: socket.assigns.selected_term_id)
    {:noreply, socket}
  end

  def handle_info({:school_overview_term_changed, term_id}, socket) do
    selected_term_id = normalize_term_id(term_id)
    ReportGeneratorDomainManger.request_totals(self(), term_id: selected_term_id)

    {:noreply, assign(socket, :selected_term_id, selected_term_id)}
  end

  def handle_info({:syllabus_search_live_ready, pid}, socket) when is_pid(pid) do
    send(pid, {:navigate_params, socket.assigns.search_params})
    {:noreply, assign(socket, :search_live_pid, pid)}
  end

  def handle_async(:fetch_departments, {:ok, {:ok, departments}}, socket) do
    dept_map = Map.new(departments, fn d -> {d["entity_id"], d["name"]} end)
    {:noreply, assign(socket, :departments, dept_map)}
  end

  def handle_async(:fetch_departments, result, socket) do
    Logger.warning("SyllabusLive failed to load departments: #{inspect(result)}")
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="flex flex-col h-full min-h-0">
        <div class="border-b border-slate-700/60 shrink-0">
          <div class="max-w-[2000px] mx-auto w-full flex items-center gap-1 px-4">
            <%= for {mode_key, label} <- @modes do %>
              <button
                id={"tab-#{mode_key}"}
                type="button"
                phx-click="switch_mode"
                phx-value-mode={mode_key}
                class={[
                  "px-4 py-2.5 text-sm font-medium border-b-2 transition-colors cursor-pointer",
                  @mode == mode_key &&
                    "text-indigo-300 border-indigo-400",
                  @mode != mode_key &&
                    "text-slate-400 border-transparent hover:text-slate-200 hover:border-slate-500"
                ]}
              >
                {label}
              </button>
            <% end %>
          </div>
        </div>

        <div class="flex-1 min-h-0">
          <%= case @mode do %>
            <% :search -> %>
              {live_render(@socket, SnowSeToolsWeb.Syllabus.SyllabusSearchLive,
                id: "syllabus-search",
                session: %{
                  "current_user_id" => @session_id,
                  "parent_pid" => self() |> :erlang.pid_to_list() |> to_string()
                }
              )}
            <% :school_overviews -> %>
              <.live_component
                module={SnowSeToolsWeb.Syllabus.SchoolOverviewsComponent}
                id="school-overviews"
                totals={@totals}
                by_school={@by_school}
                departments={@departments}
                available_terms={@available_terms}
                selected_term_id={@selected_term_id}
              />
            <% :required_elements -> %>
              {live_render(@socket, SnowSeToolsWeb.Reports.RequiredElementsLive,
                id: "required-elements",
                session: %{"current_user_id" => @session_id}
              )}
            <% :ai_history -> %>
              {live_render(@socket, SnowSeToolsWeb.AI.CompletionsHistoryLive,
                id: "ai-history",
                session: %{"current_user_id" => @session_id}
              )}
            <% :settings -> %>
              {live_render(@socket, SnowSeToolsWeb.Config.SimpleSyllabusConfig,
                id: "settings",
                session: %{"current_user_id" => @session_id}
              )}
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp list_available_terms do
    case AvailableTermsDb.list_active_terms() do
      {:ok, terms} ->
        terms

      {:error, reason} ->
        Logger.error("SyllabusLive: failed to load available terms: #{inspect(reason)}")
        []
    end
  end

  defp normalize_term_id(term_id) when is_binary(term_id) and byte_size(term_id) == 0, do: nil
  defp normalize_term_id(term_id) when is_binary(term_id), do: term_id
  defp normalize_term_id(_term_id), do: nil

  @doc false
  def mode_from_params(%{"mode" => "search"}), do: :search
  def mode_from_params(%{"mode" => "school_overviews"}), do: :school_overviews
  def mode_from_params(%{"mode" => "required_elements"}), do: :required_elements
  def mode_from_params(%{"mode" => "ai_history"}), do: :ai_history
  def mode_from_params(%{"mode" => "settings"}), do: :settings
  def mode_from_params(_params), do: :search

  @doc false
  def syllabus_path(params: params, mode: mode_atom) do
    params
    |> Map.new()
    |> Map.put("mode", Atom.to_string(mode_atom))
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> URI.encode_query()
    |> then(&"/syllabi?#{&1}")
  end

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
end
