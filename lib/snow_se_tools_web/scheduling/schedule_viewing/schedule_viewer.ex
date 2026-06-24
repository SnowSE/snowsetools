defmodule SnowSeToolsWeb.Scheduling.ScheduleViewer do
  use SnowSeToolsWeb, :html

  alias Phoenix.LiveView

  alias SnowSeTools.Scheduling.{
    ScheduleOwnerDomainManager,
    ScheduleOwnerPubSub,
    ScheduleOwnerMetadata,
    ScheduleOwnerSchedule
  }

  alias SnowSeToolsWeb.Scheduling.WeekSchedule
  import SnowSeToolsWeb.Scheduling.ScheduleViewerTermAndSearch
  import SnowSeToolsWeb.Scheduling.ScheduleViewerScheduleOwnerList

  defstruct [
    :terms,
    :selected_term_code,
    :schedule_owners_metadata_by_term,
    :query,
    :selected_schedule_keys
  ]

  @type t :: %__MODULE__{
          terms: [map()],
          selected_term_code: String.t() | nil,
          schedule_owners_metadata_by_term: %{optional(String.t()) => [ScheduleOwnerMetadata.t()]},
          query: String.t(),
          selected_schedule_keys: MapSet.t(ScheduleOwnerMetadata.t())
        }
  @key :schedule_viewer_state

  def assign_component(socket) do
    socket
    |> assign(@key, %__MODULE__{
      terms: [],
      selected_term_code: nil,
      schedule_owners_metadata_by_term: %{},
      selected_schedule_keys: MapSet.new(),
      query: ""
    })
    |> initial_setup()
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
            disabled={MapSet.size(@state.selected_schedule_keys) == 0}
            class={[
              "inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs transition",
              if(MapSet.size(@state.selected_schedule_keys) == 0,
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
          state={@state}
          selected_schedule_keys={@state.selected_schedule_keys}
        />
      </aside>

      <main class="min-w-0 flex-1 overflow-y-auto">
        <div
          :if={MapSet.size(@state.selected_schedule_keys) == 0}
          id="scheduling-empty-selection"
          class="flex h-full min-h-96 items-center justify-center rounded-xl border-2 border-dashed border-slate-800 text-sm text-slate-500"
        >
          Select a professor, room, or program semester schedule.
        </div>

        <div id="selected-schedules" class="grid grid-cols-1 gap-4 2xl:grid-cols-2">
          <%= for owner_key <- MapSet.to_list(@state.selected_schedule_keys) do %>
            <div>{owner_key} selected</div>
            <%!-- <WeekSchedule.render owner_key={owner_key} schedule_owners_details={@state.schedule_owner_week_details[owner_key]} /> --%>
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
    selected_term_code =
      case {socket.assigns[@key].selected_term_code, terms} do
        {nil, [first_term | _]} -> first_term["term_code"]
        {selected, _} -> selected
        _ -> nil
      end

    term_metadata_loaded =
      Map.has_key?(socket.assigns[@key].schedule_owners_metadata_by_term, selected_term_code)

    if !term_metadata_loaded do
      ScheduleOwnerDomainManager.request_schedule_owners_metadata(
        pid: self(),
        term_code: selected_term_code
      )
    end

    {:halt,
     assign(socket, @key, %{
       socket.assigns[@key]
       | terms: terms,
         selected_term_code: selected_term_code
     })}
  end

  def hooked_info(
        {:schedule_owners, %{term_code: term_code, schedule_owners: schedule_owners}},
        socket
      ) do
    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | schedule_owners_metadata_by_term:
           Map.put(
             socket.assigns[@key].schedule_owners_metadata_by_term,
             term_code,
             schedule_owners
           )
     })}
  end

  def hooked_info(
        {:schedule_owners, unexpected_message},
        socket
      ) do
    Logger.warn("Received unexpected schedule_owners message: #{inspect(unexpected_message)}")
    {:halt, socket}
  end

  # def hooked_info(
  #       {:schedule_owners,
  #        {:term_schedule_owners_replaced,
  #         %{term_code: term_code, schedule_owners: [%ScheduleOwner{} | _] = schedule_owners}}},
  #       socket
  #     ) do
  #   state = state(socket)

  #   if state.selected_term_code == term_code do
  #     Enum.each(state.selected_schedule_keys, fn owner_key ->
  #       ScheduleOwnerDomainManager.request_schedule_owner_detail(
  #         pid: self(),
  #         term_code: term_code,
  #         owner_key: owner_key
  #       )
  #     end)
  #   end

  #   {:halt,
  #    apply_term_schedule_owners(socket, term_code: term_code, schedule_owners: schedule_owners)}
  # end

  # def hooked_info(
  #       {:schedule_owners,
  #        {:term_schedule_owners_replaced, %{term_code: term_code, schedule_owners: []}}},
  #       socket
  #     ) do
  #   {:halt, apply_term_schedule_owners(socket, term_code: term_code, schedule_owners: [])}
  # end

  # def hooked_info({:schedule_owners, {:term_deleted, %{term_code: term_code}}}, socket) do
  #   {:halt, apply_term_deleted(socket, term_code: term_code)}
  # end

  def hooked_info(_message, socket), do: {:cont, socket}

  def hooked_event("schedule-viewer:set_term", %{"term_code" => term_code}, socket) do
    has_owners_for_term =
      Map.has_key?(socket.assigns[@key].schedule_owners_metadata_by_term, term_code)

    if !has_owners_for_term do
      ScheduleOwnerDomainManager.request_schedule_owners_metadata(
        pid: self(),
        term_code: term_code
      )
    end

    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | selected_term_code: term_code
     })}
  end

  def hooked_event("schedule-viewer:search", %{"query" => query}, socket) do
    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | query: query
     })}
  end

  def hooked_event("schedule-viewer:toggle", %{"key" => key}, socket) do
    selected_owners =
      if MapSet.member?(socket.assigns[@key].selected_schedule_keys, key) do
        MapSet.delete(socket.assigns[@key].selected_schedule_keys, key)
      else
        MapSet.put(socket.assigns[@key].selected_schedule_keys, key)
      end

    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | selected_schedule_keys: selected_owners
     })}
  end

  def hooked_event("schedule-viewer:clear_selected", _params, socket) do
    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | selected_schedule_keys: MapSet.new()
     })}
  end

  def hooked_event("schedule-viewer:close_schedule", %{"key" => key}, socket) do
    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | selected_schedule_keys: MapSet.delete(socket.assigns[@key].selected_schedule_keys, key)
     })}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}
end
