defmodule SnowSeToolsWeb.Scheduling.SchedulingLive do
  use SnowSeToolsWeb, :live_view
  require Logger

  alias SnowSeTools.AcademicPrograms.{AcademicProgramPubSub, ProgramDomainManager}
  alias SnowSeTools.Snow.SnowCourseCacheDb
  alias SnowSeToolsWeb.Scheduling.AcademicProgramsComponent
  alias SnowSeToolsWeb.Scheduling.AcademicProgramStateUtils
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerData
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerList
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerSearch
  alias SnowSeToolsWeb.Scheduling.WeekSchedule

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      AcademicProgramPubSub.subscribe()
      ProgramDomainManager.request_programs(pid: self())
    end

    terms = list_terms()
    selected_term_code = default_selected_term_code(terms)
    courses = load_courses(selected_term_code)

    {:ok,
     socket
     |> assign(:page_title, "Scheduling")
     |> assign(:selected_term_code, selected_term_code)
     |> assign(:courses, courses)
     |> assign(:academic_programs, [])
     |> assign(:query, "")
     |> assign(:selected_schedule_owner_keys, [])
     |> assign(:mode, :viewer)
     |> assign(:modes, viewer: "Schedule Viewer", programs: "Academic Programs")}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :mode, mode_from_params(params))}
  end

  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    {:noreply, push_patch(socket, to: scheduling_path(mode: mode_atom))}
  end

  def handle_event("clear_selected", _params, socket) do
    send(self(), {:selection_updated, []})
    {:noreply, socket}
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

  def handle_info({:academic_programs, message}, socket) do
    AcademicProgramStateUtils.handle_message(message, socket)
  end

  def handle_info({:close_schedule, key}, socket) do
    updated = Enum.reject(socket.assigns.selected_schedule_owner_keys, &(&1 == key))
    {:noreply, assign(socket, :selected_schedule_owner_keys, updated)}
  end

  def render(assigns) do
    assigns =
      assigns
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
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="flex h-full min-h-0 flex-col">
        <div class="shrink-0 border-b border-slate-700/60">
          <div class="mx-auto flex w-full max-w-[2000px] items-center gap-1 px-4">
            <%= for {mode_key, label} <- @modes do %>
              <button
                id={"scheduling-tab-#{mode_key}"}
                type="button"
                phx-click="switch_mode"
                phx-value-mode={mode_key}
                class={[
                  "cursor-pointer border-b-2 px-4 py-2.5 text-sm font-medium transition-colors",
                  @mode == mode_key && "border-indigo-400 text-indigo-300",
                  @mode != mode_key &&
                    "border-transparent text-slate-400 hover:border-slate-500 hover:text-slate-200"
                ]}
              >
                {label}
              </button>
            <% end %>
          </div>
        </div>

        <div class="min-h-0 flex-1">
          <%= case @mode do %>
            <% :viewer -> %>
              <div id="scheduling-page" class="mx-auto flex h-full min-h-0 w-full max-w-[2000px] gap-4 p-4">
                <aside class="flex w-80 shrink-0 flex-col gap-3 pr-2">
                  <div class="flex items-center justify-between gap-2">
                    <h1 class="text-sm font-semibold text-slate-100">Scheduling</h1>
                    <button
                      id="clear-selected-schedules"
                      type="button"
                      phx-click="clear_selected"
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
                  />

                  <.live_component
                    module={ScheduleOwnerList}
                    id="schedule-owner-list"
                    courses={@courses}
                    academic_programs={@academic_programs}
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
                    Select a professor, room, or program semester schedule.
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
            <% :programs -> %>
              <.live_component
                module={AcademicProgramsComponent}
                id="academic-programs"
                programs={@academic_programs}
              />
          <% end %>
          </div>
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

  defp mode_from_params(%{"mode" => "programs"}), do: :programs
  defp mode_from_params(_params), do: :viewer

  defp scheduling_path(mode: mode_atom), do: "/scheduling?mode=#{mode_atom}"

end
