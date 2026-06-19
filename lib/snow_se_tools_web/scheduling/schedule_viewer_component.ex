defmodule SnowSeToolsWeb.Scheduling.ScheduleViewerComponent do
  use SnowSeToolsWeb, :live_component
  require Logger

  alias SnowSeTools.Snow.SnowCourseCacheDb
  alias SnowSeToolsWeb.Scheduling.AcademicProgramStateUtils
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerData
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerList
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerSearch
  alias SnowSeToolsWeb.Scheduling.WeekSchedule

  def mount(socket) do
    terms = list_terms()
    selected_term_code = default_selected_term_code(terms)
    courses = load_courses(selected_term_code)

    {:ok,
     socket
     |> assign(:terms, terms)
     |> assign(:selected_term_code, selected_term_code)
     |> assign(:courses, courses)
     |> assign(:academic_programs, [])
     |> assign(:query, "")
     |> assign(:selected_schedule_owner_keys, [])}
  end

  def update(assigns, socket) do
    academic_programs = assigns[:academic_programs] || socket.assigns.academic_programs

    selected_schedule_owner_keys =
      if assigns[:academic_programs] != nil do
        AcademicProgramStateUtils.filter_selected_keys(
          socket.assigns.selected_schedule_owner_keys,
          socket.assigns.courses,
          socket.assigns.query,
          academic_programs
        )
      else
        socket.assigns.selected_schedule_owner_keys
      end

    {:ok,
     socket
     |> assign(:academic_programs, academic_programs)
     |> assign(:selected_schedule_owner_keys, selected_schedule_owner_keys)}
  end

  def handle_event("clear_selected", _params, socket) do
    {:noreply, assign(socket, :selected_schedule_owner_keys, [])}
  end

  def handle_info(%{event: "search_updated", payload: %{term_code: term_code, query: query}}, socket) do
    courses = load_courses(term_code)

    {:noreply,
     socket
     |> assign(:selected_term_code, term_code)
     |> assign(:courses, courses)
     |> assign(:query, query)}
  end

  def handle_info(%{event: "selection_updated", payload: %{keys: keys}}, socket) do
    {:noreply, assign(socket, :selected_schedule_owner_keys, keys)}
  end

  def handle_info(%{event: "close_schedule", payload: %{key: key}}, socket) do
    updated = Enum.reject(socket.assigns.selected_schedule_owner_keys, &(&1 == key))
    {:noreply, assign(socket, :selected_schedule_owner_keys, updated)}
  end

  def render(assigns) do
    on_search_updated = fn term_code, query ->
      send(self(), %{event: "search_updated", payload: %{term_code: term_code, query: query}})
    end

    on_selection_updated = fn keys ->
      send(self(), %{event: "selection_updated", payload: %{keys: keys}})
    end

    on_close_schedule = fn key ->
      send(self(), %{event: "close_schedule", payload: %{key: key}})
    end

    assigns =
      assigns
      |> assign(:on_search_updated, on_search_updated)
      |> assign(:on_selection_updated, on_selection_updated)
      |> assign(:on_close_schedule, on_close_schedule)
      |> assign(
        :selected_schedule_owners,
        ScheduleOwnerData.selected_schedule_owners(
          courses: assigns.courses,
          selected_schedule_owner_keys: assigns.selected_schedule_owner_keys,
          academic_programs: assigns.academic_programs
        )
      )
      |> assign(:selected_count, length(assigns.selected_schedule_owner_keys))

    ~H"""
    <div
      id="scheduling-page"
      class="mx-auto flex h-full min-h-0 w-full max-w-[2000px] gap-4 p-4"
    >
      <aside class="flex w-80 shrink-0 flex-col gap-3 pr-2">
        <div class="flex items-center justify-between gap-2">
          <h1 class="text-sm font-semibold text-slate-100">Scheduling</h1>
          <button
            id="clear-selected-schedules"
            type="button"
            phx-click="clear_selected"
            phx-target={@myself}
            disabled={@selected_count == 0}
            class={[
              "inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs transition",
              if(@selected_count == 0,
                do: "invisible cursor-not-allowed",
                else: "bg-red-950/50 text-red-300 hover:bg-red-900/70 hover:text-red-100"
              )
            ]}
          >
            <.icon name="hero-x-mark" class="size-3" /> Clear Selection
          </button>
        </div>

        <.live_component
          module={ScheduleOwnerSearch}
          id="schedule-owner-search"
          selected_term_code={@selected_term_code}
          query={@query}
          on_search_updated={@on_search_updated}
        />

        <.live_component
          module={ScheduleOwnerList}
          id="schedule-owner-list"
          courses={@courses}
          academic_programs={@academic_programs}
          query={@query}
          selected_schedule_owner_keys={@selected_schedule_owner_keys}
          on_selection_updated={@on_selection_updated}
        />
      </aside>

      <main class="min-w-0 flex-1 overflow-y-auto">
        <div
          :if={@selected_schedule_owners == []}
          id="scheduling-empty-selection"
          class="flex h-full min-h-96 items-center justify-center rounded-xl border-2 border-dashed border-slate-800 text-sm text-slate-500"
        >
          Select a professor, room, or program semester schedule.
        </div>

        <div id="selected-schedules" class="grid grid-cols-1 gap-4 2xl:grid-cols-2">
          <%= for schedule_owner <- @selected_schedule_owners do %>
            <.live_component
              module={WeekSchedule}
              id={"schedule-#{schedule_owner.dom_id}"}
              schedule_owner={schedule_owner}
              on_close_schedule={@on_close_schedule}
            />
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  defp list_terms do
    case SnowCourseCacheDb.list_terms_with_courses() do
      {:error, reason} ->
        Logger.error("ScheduleViewerComponent: failed to list terms: #{inspect(reason)}")
        []

      terms ->
        terms
    end
  end

  defp default_selected_term_code([]), do: nil
  defp default_selected_term_code([term | _]), do: term["term_code"]

  defp load_courses(nil), do: []

  defp load_courses(term_code) do
    case SnowCourseCacheDb.list_course_data_for_term(term_code: term_code) do
      {:ok, courses} ->
        courses

      {:error, reason} ->
        Logger.error(
          "ScheduleViewerComponent: failed to load courses for term=#{term_code}: #{inspect(reason)}"
        )

        []
    end
  end
end
