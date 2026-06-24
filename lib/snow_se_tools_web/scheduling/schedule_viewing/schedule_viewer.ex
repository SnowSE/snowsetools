defmodule SnowSeToolsWeb.Scheduling.ScheduleViewer do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Snow.SnowCourseCacheDb
  alias SnowSeToolsWeb.Scheduling.AcademicProgramStateUtils
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerData
  alias SnowSeToolsWeb.Scheduling.WeekSchedule

  defstruct [
    :key,
    :terms,
    :selected_term_code,
    :courses,
    :query,
    :academic_programs,
    :selected_schedule_owner_keys
  ]

  def assign_component(socket, key, opts \\ []) do
    boot_state = Map.merge(bootstrap_state(), Map.new(opts))

    socket
    |> assign(
      key,
      socket.assigns[key] ||
        %__MODULE__{
          key: key,
          terms: boot_state.terms,
          selected_term_code: boot_state.selected_term_code,
          courses: boot_state.courses,
          query: "",
          academic_programs: Map.get(boot_state, :academic_programs, []),
          selected_schedule_owner_keys: MapSet.new()
        }
    )
    |> maybe_attach_hooks()
  end

  def bootstrap_state do
    terms = list_terms()
    selected_term_code = default_selected_term_code(terms)

    %{
      terms: terms,
      selected_term_code: selected_term_code,
      courses: load_courses(selected_term_code)
    }
  end

  def apply_academic_programs(socket, academic_programs) do
    key = viewer_key(socket)
    state = socket.assigns[key]

    selected_schedule_owner_keys =
      AcademicProgramStateUtils.filter_selected_keys(
        state.selected_schedule_owner_keys,
        state.courses,
        state.query,
        academic_programs
      )

    assign(socket, key, %{
      state
      | academic_programs: academic_programs,
        selected_schedule_owner_keys: selected_schedule_owner_keys
    })
  end

  def render(assigns) do
    schedule_owners =
      ScheduleOwnerData.build_schedule_owners(
        courses: assigns.state.courses,
        query: assigns.state.query,
        academic_programs: assigns.state.academic_programs
      )

    selected_schedule_owners =
      ScheduleOwnerData.lookup_selected(
        schedule_owners,
        assigns.state.selected_schedule_owner_keys,
        assigns.state.academic_programs
      )

    selected_count = MapSet.size(assigns.state.selected_schedule_owner_keys)

    assigns =
      assigns
      |> assign(:schedule_owners, schedule_owners)
      |> assign(:selected_schedule_owners, selected_schedule_owners)
      |> assign(:selected_count, selected_count)

    ~H"""
    <div id="scheduling-page" class="mx-auto flex h-full min-h-0 w-full max-w-[2000px] gap-4 p-4">
      <aside class="flex w-80 shrink-0 flex-col gap-3 pr-2">
        <div class="flex items-center justify-between gap-2">
          <h1 class="text-sm font-semibold text-slate-100">Scheduling</h1>
          <button
            id="clear-selected-schedules"
            type="button"
            phx-click="schedule-viewer:clear_selected"
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

        <.term_and_search state={@state} />
        <.schedule_owner_list
          schedule_owners={@schedule_owners}
          selected_keys={@state.selected_schedule_owner_keys}
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
            <WeekSchedule.render schedule_owner={schedule_owner} />
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :schedule_viewer_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("schedule-viewer:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("schedule-viewer:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :schedule_viewer_hooks_attached?], true)
    end
  end

  def hooked_info({:academic_programs, {:loaded, _} = message}, socket) do
    {:noreply, updated_socket} = AcademicProgramStateUtils.handle_message(message, socket)

    case message do
      {:loaded, {:ok, programs}} ->
        {:halt, apply_academic_programs(updated_socket, programs)}

      {:loaded, {:error, _reason}} ->
        {:halt, updated_socket}
    end
  end

  def hooked_info({:academic_programs, {kind, _} = message}, socket)
      when kind in [:program_created, :program_updated, :program_deleted] do
    {:noreply, updated_socket} = AcademicProgramStateUtils.handle_message(message, socket)

    {:halt,
     apply_academic_programs(
       updated_socket,
       Map.get(updated_socket.assigns, :academic_programs, [])
     )}
  end

  def hooked_info({:academic_programs, {:action_result, _result}}, socket), do: {:cont, socket}

  def hooked_info(_message, socket), do: {:cont, socket}

  def hooked_event("schedule-viewer:set_term", %{"term_code" => term_code}, socket) do
    {:halt,
     update_state(socket, fn state ->
       courses = load_courses(term_code)
       %{state | selected_term_code: term_code, courses: courses}
     end)}
  end

  def hooked_event("schedule-viewer:search", %{"query" => query}, socket) do
    {:halt,
     update_state(socket, fn state ->
       %{state | query: query}
     end)}
  end

  def hooked_event("schedule-viewer:toggle", %{"key" => owner_key}, socket) do
    {:halt,
     update_state(socket, fn state ->
       keys = state.selected_schedule_owner_keys

       keys =
         if MapSet.member?(keys, owner_key),
           do: MapSet.delete(keys, owner_key),
           else: MapSet.put(keys, owner_key)

       %{state | selected_schedule_owner_keys: keys}
     end)}
  end

  def hooked_event("schedule-viewer:clear_selected", _params, socket) do
    {:halt,
     update_state(socket, fn state ->
       %{state | selected_schedule_owner_keys: MapSet.new()}
     end)}
  end

  def hooked_event("schedule-viewer:close_schedule", %{"key" => owner_key}, socket) do
    {:halt,
     update_state(socket, fn state ->
       %{
         state
         | selected_schedule_owner_keys:
             MapSet.delete(state.selected_schedule_owner_keys, owner_key)
       }
     end)}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  ## Private helpers

  defp update_state(socket, update_fn) do
    key = viewer_key(socket)
    assign(socket, key, update_fn.(socket.assigns[key]))
  end

  defp viewer_key(_socket), do: :schedule_viewer

  defp load_courses(nil), do: []

  defp load_courses(term_code) do
    case SnowCourseCacheDb.list_course_data_for_term(term_code: term_code) do
      {:ok, courses} ->
        courses

      {:error, reason} ->
        Logger.error(
          "ScheduleViewer: failed to load courses for term=#{term_code}: #{inspect(reason)}"
        )

        []
    end
  end

  defp list_terms do
    case SnowCourseCacheDb.list_terms_with_courses() do
      {:error, reason} ->
        Logger.error("ScheduleViewer: failed to list terms: #{inspect(reason)}")
        []

      terms ->
        terms
    end
  end

  defp default_selected_term_code([]), do: nil
  defp default_selected_term_code([term | _]), do: term["term_code"]

  ## Child function components

  defp term_and_search(assigns) do
    ~H"""
    <div class="flex shrink-0 flex-col gap-3">
      <.form
        for={to_form(%{})}
        id="scheduling-term-form"
        phx-change="schedule-viewer:set_term"
      >
        <select
          id="scheduling-term-select"
          name="term_code"
          class="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
        >
          <%= for term <- @state.terms do %>
            <option
              value={term["term_code"]}
              selected={term["term_code"] == @state.selected_term_code}
            >
              {term["term_name"]}
            </option>
          <% end %>
        </select>
      </.form>

      <.form
        for={to_form(%{})}
        id="scheduling-search-form"
        phx-change="schedule-viewer:search"
      >
        <div class="relative">
          <.icon
            name="hero-magnifying-glass"
            class="pointer-events-none absolute left-3 top-2.5 size-4 text-slate-500"
          />
          <input
            id="scheduling-search-input"
            type="search"
            name="query"
            value={@state.query}
            autocomplete="off"
            placeholder="Search professor, room, or program semester"
            class="w-full rounded-lg border border-slate-700 bg-slate-900 py-2 pl-9 pr-3 text-sm text-slate-100 placeholder:text-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500/30"
          />
        </div>
      </.form>
    </div>
    """
  end

  defp schedule_owner_list(assigns) do
    ~H"""
    <div id="schedule-owner-list" class="min-h-0 flex-1 space-y-2 overflow-y-auto pe-2">
      <.empty_state :if={@schedule_owners == []} />

      <%= for schedule_owner <- @schedule_owners do %>
        <.schedule_owner_button
          schedule_owner={schedule_owner}
          is_selected={MapSet.member?(@selected_keys, schedule_owner.key)}
        />
      <% end %>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div id="schedule-owner-empty" class="px-2 py-8 text-center text-sm text-slate-500">
      No matching schedules.
    </div>
    """
  end

  defp schedule_owner_button(assigns) do
    ~H"""
    <button
      id={"schedule-owner-#{@schedule_owner.dom_id}"}
      type="button"
      phx-click="schedule-viewer:toggle"
      phx-value-key={@schedule_owner.key}
      class={[
        "flex w-full items-center justify-between gap-3 rounded-lg border px-3 py-2 text-left transition",
        if(@is_selected,
          do: "border-indigo-500/50 bg-indigo-950/50 text-indigo-100",
          else:
            "border-slate-800 bg-slate-900/50 text-slate-200 hover:border-slate-700 hover:bg-slate-800/70"
        )
      ]}
    >
      <span class="min-w-0">
        <span class="block truncate text-sm font-medium">{@schedule_owner.name}</span>
        <span class="block text-xs text-slate-500">{@schedule_owner.type_label}</span>
        <span
          :if={Map.get(@schedule_owner, :type) == :academic_program_semester}
          class="mt-1 block text-xs text-slate-600"
        >
          {Map.get(@schedule_owner, :requirement_count, 0)} requirements
        </span>
      </span>
      <span class="shrink-0 text-xs text-slate-400">{@schedule_owner.credit_count} cr.</span>
    </button>
    """
  end
end
