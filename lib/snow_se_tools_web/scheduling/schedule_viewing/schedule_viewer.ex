defmodule SnowSeToolsWeb.Scheduling.ScheduleViewer do
  use SnowSeToolsWeb, :html

  alias Phoenix.LiveView
  alias SnowSeTools.Scheduling.{ScheduleOwnerDomainManager, ScheduleOwnerPubSub}
  alias SnowSeToolsWeb.Scheduling.WeekSchedule
  import SnowSeToolsWeb.Scheduling.ScheduleViewerTermAndSearch
  import SnowSeToolsWeb.Scheduling.ScheduleViewerScheduleOwnerList

  defstruct [
    :key,
    :terms,
    :selected_term_code,
    :schedule_owners,
    :visible_schedule_owners,
    :query,
    :selected_schedule_owner_keys,
    :selected_schedule_owners,
    :selected_count,
    :loading?
  ]

  def assign_component(socket, key, opts \\ []) do
    socket
    |> assign(key, socket.assigns[key] || initial_state(key: key, opts: opts))
    |> initial_setup()
  end

  defp initial_state(key: key, opts: opts) do
    opts = Map.new(opts)

    %__MODULE__{
      key: key,
      terms: Map.get(opts, :terms, []),
      selected_term_code: Map.get(opts, :selected_term_code),
      schedule_owners: Map.get(opts, :schedule_owners, []),
      visible_schedule_owners: Map.get(opts, :visible_schedule_owners, []),
      query: Map.get(opts, :query, ""),
      selected_schedule_owner_keys:
        Map.get(opts, :selected_schedule_owner_keys, empty_selected_keys()),
      selected_schedule_owners: Map.get(opts, :selected_schedule_owners, []),
      selected_count: Map.get(opts, :selected_count, 0),
      loading?: Map.get(opts, :loading?, true)
    }
  end

  def render(assigns) do
    ~H"""
    <div id="scheduling-page" class="mx-auto flex h-full min-h-0 w-full max-w-[2000px] gap-4 p-4">
      <aside class="flex w-80 shrink-0 flex-col gap-3 pr-2">
        <div class="flex items-center justify-between gap-2">
          <h1 class="text-sm font-semibold text-slate-100">Scheduling</h1>
          <button
            id="clear-selected-schedules"
            type="button"
            phx-click="schedule-viewer:clear_selected"
            disabled={@state.selected_count == 0}
            class={[
              "inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs transition",
              if(@state.selected_count == 0,
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
          schedule_owners={@state.visible_schedule_owners}
          selected_keys={@state.selected_schedule_owner_keys}
        />
      </aside>

      <main class="min-w-0 flex-1 overflow-y-auto">
        <div
          :if={@state.selected_schedule_owners == []}
          id="scheduling-empty-selection"
          class="flex h-full min-h-96 items-center justify-center rounded-xl border-2 border-dashed border-slate-800 text-sm text-slate-500"
        >
          Select a professor, room, or program semester schedule.
        </div>

        <div id="selected-schedules" class="grid grid-cols-1 gap-4 2xl:grid-cols-2">
          <%= for schedule_owner <- @state.selected_schedule_owners do %>
            <WeekSchedule.render schedule_owner={schedule_owner} />
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  defp initial_setup(socket) do
    socket
    |> maybe_attach_hooks()
    |> maybe_request_initial_data()
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

  defp maybe_request_initial_data(socket) do
    if LiveView.connected?(socket) and
         !Map.get(socket.private, :schedule_viewer_initial_data_requested?) do
      ScheduleOwnerPubSub.subscribe()
      ScheduleOwnerDomainManager.request_terms(pid: self())
      put_in(socket, [Access.key(:private), :schedule_viewer_initial_data_requested?], true)
    else
      socket
    end
  end

  def hooked_info({:schedule_owner_terms, terms}, socket) do
    state = state(socket)
    selected_term_code = state.selected_term_code || default_selected_term_code(terms)

    if is_binary(selected_term_code) do
      ScheduleOwnerDomainManager.request_schedule_owners(
        pid: self(),
        term_code: selected_term_code
      )
    end

    {:halt,
     update_state(socket, fn state ->
       %{state | terms: terms, selected_term_code: selected_term_code, loading?: true}
     end)}
  end

  def hooked_info(
        {:schedule_owners, %{term_code: term_code, schedule_owners: schedule_owners}},
        socket
      ) do
    {:halt,
     apply_term_schedule_owners(socket, term_code: term_code, schedule_owners: schedule_owners)}
  end

  def hooked_info({:schedule_owners, {:terms_changed, terms}}, socket) do
    {:halt,
     update_state(socket, fn state ->
       selected_term_code = keep_selected_term(state.selected_term_code, terms)

       if selected_term_code != state.selected_term_code and is_binary(selected_term_code) do
         ScheduleOwnerDomainManager.request_schedule_owners(
           pid: self(),
           term_code: selected_term_code
         )
       end

       state
       |> Map.merge(%{
         terms: terms,
         selected_term_code: selected_term_code,
         schedule_owners:
           if(selected_term_code == state.selected_term_code, do: state.schedule_owners, else: []),
         loading?:
           selected_term_code != state.selected_term_code and is_binary(selected_term_code)
       })
       |> recompute_view_state()
     end)}
  end

  def hooked_info(
        {:schedule_owners,
         {:term_schedule_owners_replaced,
          %{term_code: term_code, schedule_owners: schedule_owners}}},
        socket
      ) do
    {:halt,
     apply_term_schedule_owners(socket, term_code: term_code, schedule_owners: schedule_owners)}
  end

  def hooked_info({:schedule_owners, {:term_deleted, %{term_code: term_code}}}, socket) do
    {:halt, apply_term_deleted(socket, term_code: term_code)}
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  def hooked_event("schedule-viewer:set_term", %{"term_code" => term_code}, socket) do
    ScheduleOwnerDomainManager.request_schedule_owners(pid: self(), term_code: term_code)

    {:halt,
     update_state(socket, fn state ->
       state
       |> Map.merge(%{selected_term_code: term_code, schedule_owners: [], loading?: true})
       |> recompute_view_state()
     end)}
  end

  def hooked_event("schedule-viewer:search", %{"query" => query}, socket) do
    {:halt,
     update_state(socket, fn state ->
       recompute_view_state(%{state | query: query})
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

       recompute_view_state(%{state | selected_schedule_owner_keys: keys})
     end)}
  end

  def hooked_event("schedule-viewer:clear_selected", _params, socket) do
    {:halt,
     update_state(socket, fn state ->
       recompute_view_state(%{state | selected_schedule_owner_keys: clear_selected_keys(state)})
     end)}
  end

  def hooked_event("schedule-viewer:close_schedule", %{"key" => owner_key}, socket) do
    {:halt,
     update_state(socket, fn state ->
       keys = MapSet.delete(state.selected_schedule_owner_keys, owner_key)
       recompute_view_state(%{state | selected_schedule_owner_keys: keys})
     end)}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  defp apply_term_schedule_owners(socket, term_code: term_code, schedule_owners: schedule_owners) do
    update_state(socket, fn state ->
      if state.selected_term_code == term_code do
        state
        |> Map.merge(%{schedule_owners: schedule_owners, loading?: false})
        |> recompute_view_state()
      else
        state
      end
    end)
  end

  defp apply_term_deleted(socket, term_code: term_code) do
    update_state(socket, fn state ->
      terms = Enum.reject(state.terms, &(&1["term_code"] == term_code))

      if state.selected_term_code == term_code do
        selected_term_code = default_selected_term_code(terms)

        if is_binary(selected_term_code) do
          ScheduleOwnerDomainManager.request_schedule_owners(
            pid: self(),
            term_code: selected_term_code
          )
        end

        state
        |> Map.merge(%{
          terms: terms,
          selected_term_code: selected_term_code,
          schedule_owners: [],
          selected_schedule_owner_keys: clear_selected_keys(state),
          loading?: is_binary(selected_term_code)
        })
        |> recompute_view_state()
      else
        %{state | terms: terms}
      end
    end)
  end

  defp recompute_view_state(state) do
    visible_schedule_owners = filter_schedule_owners(state.schedule_owners, state.query)

    selected_schedule_owners =
      visible_schedule_owners
      |> Enum.filter(&MapSet.member?(state.selected_schedule_owner_keys, &1.key))

    %{
      state
      | visible_schedule_owners: visible_schedule_owners,
        selected_schedule_owners: selected_schedule_owners,
        selected_count: MapSet.size(state.selected_schedule_owner_keys)
    }
  end

  defp filter_schedule_owners(schedule_owners, query) do
    query_words =
      query
      |> normalize()
      |> String.split(~r/\s+/, trim: true)

    Enum.filter(schedule_owners, fn schedule_owner ->
      query_words == [] or query_matches_all?(schedule_owner.search_text, query_words)
    end)
  end

  defp query_matches_all?(search_text, query_words) do
    normalized = normalize(search_text)
    Enum.all?(query_words, &String.contains?(normalized, &1))
  end

  defp keep_selected_term(selected_term_code, terms) do
    term_codes = MapSet.new(terms, & &1["term_code"])

    if MapSet.member?(term_codes, selected_term_code) do
      selected_term_code
    else
      default_selected_term_code(terms)
    end
  end

  defp update_state(socket, update_fn) do
    key = viewer_key(socket)
    assign(socket, key, update_fn.(socket.assigns[key]))
  end

  defp state(socket), do: socket.assigns[viewer_key(socket)]
  defp viewer_key(_socket), do: :schedule_viewer

  defp default_selected_term_code([]), do: nil
  defp default_selected_term_code([term | _]), do: term["term_code"]

  defp empty_selected_keys, do: MapSet.new([])

  defp clear_selected_keys(state),
    do: MapSet.difference(state.selected_schedule_owner_keys, state.selected_schedule_owner_keys)

  defp normalize(value) when is_binary(value), do: value |> String.downcase() |> String.trim()
  defp normalize(_value), do: ""
end
