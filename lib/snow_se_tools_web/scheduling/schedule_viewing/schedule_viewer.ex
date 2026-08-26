defmodule SnowSeToolsWeb.Scheduling.ScheduleViewer do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView

  alias SnowSeTools.Scheduling.{
    ScheduleOwnerDomainManager,
    ScheduleOwnerPubSub,
    ScheduleOwnerMetadata
  }

  alias SnowSeToolsWeb.Scheduling.{
    CourseListForTerm,
    ScheduleChangeGroups,
    ScheduleDetailsOrder,
    ScheduleTermConflicts
  }

  import SnowSeToolsWeb.Scheduling.ScheduleOwnerSearch

  defstruct [
    :terms,
    :selected_term_code,
    :schedule_owners_metadata_by_term,
    :query,
    :search_active,
    :highlighted_index
  ]

  @type t :: %__MODULE__{
          terms: [map()],
          selected_term_code: String.t() | nil,
          schedule_owners_metadata_by_term: %{optional(String.t()) => [ScheduleOwnerMetadata.t()]},
          query: String.t(),
          search_active: boolean(),
          highlighted_index: non_neg_integer()
        }
  @key :schedule_viewer_state

  def assign_component(socket) do
    socket
    |> assign(@key, %__MODULE__{
      terms: [],
      selected_term_code: nil,
      schedule_owners_metadata_by_term: %{},
      query: "",
      search_active: false,
      highlighted_index: 0
    })
    |> initial_setup()
  end

  attr :state, __MODULE__, required: true
  attr :schedule_details_order, :any, required: true
  attr :week_schedules, :list, default: []
  attr :week_schedule_edit_course_modal, :map, default: nil
  attr :schedule_change_groups_state, :any, required: true
  attr :schedule_term_conflicts_state, :any, required: true
  attr :academic_programs, :list, default: []
  attr :courses, :list, default: []

  def render(assigns) do
    ~H"""
    <div
      id="scheduling-page"
      class="mx-auto flex h-full min-h-0 w-full max-w-full gap-4 p-4"
    >
      <aside class="flex shrink-0 flex-col gap-3 pr-2 w-80 min-h-0">
        <.search
          state={@state}
          selected_schedule_order={ScheduleDetailsOrder.selected_owner_order(@schedule_details_order)}
        />
        <ScheduleChangeGroups.render
          state={@schedule_change_groups_state}
          courses={@courses}
          academic_programs={@academic_programs}
        />
        <ScheduleTermConflicts.render state={@schedule_term_conflicts_state} />
      </aside>

      <ScheduleDetailsOrder.render
        state={@schedule_details_order}
        week_schedules={@week_schedules}
        week_schedule_edit_course_modal={@week_schedule_edit_course_modal}
        active_change_group={ScheduleChangeGroups.active_change_group(@schedule_change_groups_state)}
        conflicted_course_crns={
          ScheduleTermConflicts.conflicted_course_crns(@schedule_term_conflicts_state)
        }
        active_conflicted_course_crns={
          ScheduleChangeGroups.active_conflicted_course_crns(@schedule_change_groups_state)
        }
        schedule_owners_metadata={selected_term_schedule_owners(@state)}
      />
    </div>
    """
  end

  def sync_selected_term(socket, term_code: term_code) when is_binary(term_code) do
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      socket
    else
      socket
      |> maybe_request_schedule_owners_metadata(term_code: term_code)
      |> assign(@key, %{
        state
        | selected_term_code: term_code
      })
    end
  end

  def sync_selected_term(socket, term_code: nil), do: socket

  def resolve_selected_term_code(terms: terms, selected_term_code: selected_term_code) do
    cond do
      is_binary(selected_term_code) and Enum.any?(terms, &(&1["term_code"] == selected_term_code)) ->
        selected_term_code

      terms == [] and is_binary(selected_term_code) ->
        selected_term_code

      true ->
        case terms do
          [first_term | _] -> first_term["term_code"]
          [] -> nil
        end
    end
  end

  defp selected_term_schedule_owners(%__MODULE__{} = state) do
    Map.get(state.schedule_owners_metadata_by_term, state.selected_term_code, [])
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
      resolve_selected_term_code(
        terms: terms,
        selected_term_code: socket.assigns[@key].selected_term_code
      )

    term_metadata_loaded =
      Map.has_key?(socket.assigns[@key].schedule_owners_metadata_by_term, selected_term_code)

    if is_binary(selected_term_code) and !term_metadata_loaded do
      ScheduleOwnerDomainManager.request_schedule_owners_metadata(
        pid: self(),
        term_code: selected_term_code
      )
    end

    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | terms: terms,
         selected_term_code: selected_term_code
     })
     |> CourseListForTerm.sync_selected_term(term_code: selected_term_code)
     |> ScheduleDetailsOrder.sync_selected_term(term_code: selected_term_code)
     |> ScheduleTermConflicts.sync_selected_term(term_code: selected_term_code)}
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
        {:schedule_owners,
         {:term_schedule_owners_replaced,
          %{term_code: term_code, schedule_owners: schedule_owners}}},
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
     })
     |> ScheduleDetailsOrder.sync_selected_term(
       term_code: socket.assigns[@key].selected_term_code
     )
     |> ScheduleTermConflicts.sync_selected_term(
       term_code: socket.assigns[@key].selected_term_code
     )}
  end

  def hooked_info(
        {:schedule_owners,
         {:schedule_owner_metadata_upserted,
          %{term_code: term_code, schedule_owner: schedule_owner}}},
        socket
      ) do
    {:halt,
     assign(socket, @key, %{
       socket.assigns[@key]
       | schedule_owners_metadata_by_term:
           Map.update(
             socket.assigns[@key].schedule_owners_metadata_by_term,
             term_code,
             [schedule_owner],
             fn schedule_owners ->
               schedule_owners
               |> Enum.reject(&(&1.key == schedule_owner.key))
               |> Kernel.++([schedule_owner])
             end
           )
     })}
  end

  def hooked_info(
        {:schedule_owners,
         {:schedule_owner_metadata_deleted, %{term_code: term_code, owner_key: owner_key}}},
        socket
      ) do
    {:halt,
     assign(socket, @key, %{
       socket.assigns[@key]
       | schedule_owners_metadata_by_term:
           Map.update(
             socket.assigns[@key].schedule_owners_metadata_by_term,
             term_code,
             [],
             &Enum.reject(&1, fn schedule_owner -> schedule_owner.key == owner_key end)
           )
     })}
  end

  def hooked_info(
        {:schedule_owners, {:terms_changed, terms}},
        socket
      ) do
    selected_term_code =
      resolve_selected_term_code(
        terms: terms,
        selected_term_code: socket.assigns[@key].selected_term_code
      )

    if is_binary(selected_term_code) and
         !Map.has_key?(socket.assigns[@key].schedule_owners_metadata_by_term, selected_term_code) do
      ScheduleOwnerDomainManager.request_schedule_owners_metadata(
        pid: self(),
        term_code: selected_term_code
      )
    end

    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | terms: terms,
         selected_term_code: selected_term_code
     })
     |> CourseListForTerm.sync_selected_term(term_code: selected_term_code)
     |> ScheduleDetailsOrder.sync_selected_term(term_code: selected_term_code)
     |> ScheduleTermConflicts.sync_selected_term(term_code: selected_term_code)}
  end

  def hooked_info({:schedule_owners, {:term_deleted, %{term_code: term_code}}}, socket) do
    terms = Enum.reject(socket.assigns[@key].terms, &(&1["term_code"] == term_code))

    selected_term_code =
      resolve_selected_term_code(
        terms: terms,
        selected_term_code:
          if(socket.assigns[@key].selected_term_code == term_code,
            do: nil,
            else: socket.assigns[@key].selected_term_code
          )
      )

    if is_binary(selected_term_code) and
         !Map.has_key?(socket.assigns[@key].schedule_owners_metadata_by_term, selected_term_code) do
      ScheduleOwnerDomainManager.request_schedule_owners_metadata(
        pid: self(),
        term_code: selected_term_code
      )
    end

    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | terms: terms,
         selected_term_code: selected_term_code,
         schedule_owners_metadata_by_term:
           Map.delete(socket.assigns[@key].schedule_owners_metadata_by_term, term_code)
     })
     |> CourseListForTerm.sync_selected_term(term_code: selected_term_code)
     |> ScheduleDetailsOrder.sync_selected_term(term_code: selected_term_code)
     |> ScheduleTermConflicts.sync_selected_term(term_code: selected_term_code)}
  end

  def hooked_info(
        {:schedule_owners, {:schedule_owner_detail_changed, _detail_changed}},
        socket
      ) do
    {:cont, socket}
  end

  def hooked_info(
        {:schedule_owners, unexpected_message},
        socket
      ) do
    Logger.warning("Received unexpected schedule_owners message: #{inspect(unexpected_message)}")
    {:cont, socket}
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  def hooked_event("schedule-viewer:set_term", %{"term_code" => term_code}, socket) do
    {:halt, LiveView.push_patch(socket, to: scheduling_path(term_code: term_code))}
  end

  def hooked_event("schedule-viewer:search", %{"query" => query}, socket) do
    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | query: query,
         search_active: true,
         highlighted_index: 0
     })}
  end

  def hooked_event("schedule-viewer:search_key", %{"key" => key}, socket) do
    state = socket.assigns[@key]
    matched = matched_owners(state)
    last_index = max(length(matched) - 1, 0)

    case key do
      "ArrowDown" ->
        {:halt,
         assign(socket, @key, %{
           state
           | search_active: true,
             highlighted_index: min(state.highlighted_index + 1, last_index)
         })}

      "ArrowUp" ->
        {:halt,
         assign(socket, @key, %{state | highlighted_index: max(state.highlighted_index - 1, 0)})}

      "Enter" ->
        socket =
          case Enum.at(matched, state.highlighted_index) do
            nil -> socket
            owner -> ScheduleDetailsOrder.toggle_owner(socket, key: owner.key)
          end

        {:halt,
         assign(socket, @key, %{
           socket.assigns[@key]
           | query: "",
             highlighted_index: 0
         })}

      "Escape" ->
        {:halt, assign(socket, @key, %{state | search_active: false})}

      _other ->
        {:halt, socket}
    end
  end

  def hooked_event("schedule-viewer:search_focused", _params, socket) do
    {:halt, assign(socket, @key, %{socket.assigns[@key] | search_active: true})}
  end

  def hooked_event("schedule-viewer:search_blurred", _params, socket) do
    {:halt, assign(socket, @key, %{socket.assigns[@key] | search_active: false})}
  end

  def hooked_event("schedule-owner-search:select", %{"key" => key}, socket) do
    {:halt, ScheduleDetailsOrder.toggle_owner(socket, key: key)}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  defp maybe_request_schedule_owners_metadata(socket, term_code: term_code) do
    if !Map.has_key?(socket.assigns[@key].schedule_owners_metadata_by_term, term_code) do
      ScheduleOwnerDomainManager.request_schedule_owners_metadata(
        pid: self(),
        term_code: term_code
      )
    end

    socket
  end

  defp scheduling_path(term_code: term_code), do: "/scheduling?mode=viewer&term=#{term_code}"
end
