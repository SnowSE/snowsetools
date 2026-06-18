defmodule SnowSeToolsWeb.Scheduling.SchedulingLive do
  use SnowSeToolsWeb, :live_view
  require Logger

  alias SnowSeTools.Snow.SnowCourseCacheDb
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerData
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerList
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerSearch
  alias SnowSeToolsWeb.Scheduling.WeekSchedule

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    terms = list_terms()
    selected_term_code = default_selected_term_code(terms)
    courses = load_courses(selected_term_code)

    {:ok,
     socket
     |> assign(:page_title, "Scheduling")
     |> assign(:selected_term_code, selected_term_code)
     |> assign(:courses, courses)
     |> assign(:query, "")
     |> assign(:selected_schedule_owner_keys, [])}
  end

  def handle_info({:search_updated, %{term_code: term_code, query: query}}, socket) do
    courses = load_courses(term_code)

    {:noreply,
     socket
     |> assign(:selected_term_code, term_code)
     |> assign(:courses, courses)
     |> assign(:query, query)}
  end

  def handle_info({:selection_updated, selected_schedule_owner_keys}, socket) do
    {:noreply, assign(socket, :selected_schedule_owner_keys, selected_schedule_owner_keys)}
  end

  def handle_info({:close_schedule, key}, socket) do
    updated = Enum.reject(socket.assigns.selected_schedule_owner_keys, &(&1 == key))
    {:noreply, assign(socket, :selected_schedule_owner_keys, updated)}
  end

  def handle_event("clear_selected", _params, socket) do
    send(self(), {:selection_updated, []})
    {:noreply, socket}
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(
        :selected_schedule_owners,
        ScheduleOwnerData.selected_schedule_owners(
          assigns.courses,
          assigns.selected_schedule_owner_keys
        )
      )
      |> assign(:selected_count, length(assigns.selected_schedule_owner_keys))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div id="scheduling-page" class="mx-auto flex h-full min-h-0 w-full max-w-[2000px] gap-4 p-4">
        <aside class="flex w-80 shrink-0 flex-col gap-3  pr-2">
          <div class="flex items-center justify-between gap-2">
            <h1 class="text-sm font-semibold text-slate-100">Scheduling</h1>
            <button
              id="clear-selected-schedules"
              type="button"
              phx-click="clear_selected"
              disabled={@selected_count == 0}
              class={[
                "inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs transition  ",
                if(@selected_count == 0,
                  do: "cursor-not-allowed invisible",
                  else: "text-red-300 bg-red-950/50 hover:bg-red-900/70 hover:text-red-100"
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
          />

          <.live_component
            module={ScheduleOwnerList}
            id="schedule-owner-list"
            courses={@courses}
            query={@query}
            selected_schedule_owner_keys={@selected_schedule_owner_keys}
          />
        </aside>

        <main class="min-w-0 flex-1 overflow-y-auto">
          <div
            :if={@selected_schedule_owners == []}
            id="scheduling-empty-selection"
            class="flex h-full min-h-96 items-center justify-center rounded-xl border-2 border-dashed border-slate-800 text-sm text-slate-500"
          >
            Select a professor or room schedule.
          </div>

          <div id="selected-schedules" class="grid grid-cols-1 gap-4 2xl:grid-cols-2">
            <%= for schedule_owner <- @selected_schedule_owners do %>
              <.live_component
                module={WeekSchedule}
                id={"schedule-#{schedule_owner.dom_id}"}
                schedule_owner={schedule_owner}
              />
            <% end %>
          </div>
        </main>
      </div>
    </Layouts.app>
    """
  end

  defp list_terms do
    case SnowCourseCacheDb.list_terms_with_courses() do
      {:error, _reason} -> []
      terms -> terms
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
          "Scheduling: failed to load courses for term=#{term_code}: #{inspect(reason)}"
        )

        []
    end
  end
end
