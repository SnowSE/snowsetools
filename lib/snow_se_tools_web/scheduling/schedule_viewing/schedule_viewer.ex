defmodule SnowSeToolsWeb.Scheduling.ScheduleViewer do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView

  alias SnowSeTools.Scheduling.{
    ScheduleOwnerDomainManager,
    ScheduleOwnerPubSub,
    ScheduleOwnerMetadata
  }

  alias SnowSeToolsWeb.Scheduling.{ScheduleChangeGroups, ScheduleDetailsOrder}
  import SnowSeToolsWeb.Scheduling.ScheduleViewerTermAndSearch
  import SnowSeToolsWeb.Scheduling.ScheduleViewerScheduleOwnerList

  defstruct [
    :terms,
    :selected_term_code,
    :schedule_owners_metadata_by_term,
    :query
  ]

  @type t :: %__MODULE__{
          terms: [map()],
          selected_term_code: String.t() | nil,
          schedule_owners_metadata_by_term: %{optional(String.t()) => [ScheduleOwnerMetadata.t()]},
          query: String.t()
        }
  @key :schedule_viewer_state

  def assign_component(socket) do
    socket
    |> assign(@key, %__MODULE__{
      terms: [],
      selected_term_code: nil,
      schedule_owners_metadata_by_term: %{},
      query: ""
    })
    |> initial_setup()
  end

  def render(assigns) do
    ~H"""
    <div id="scheduling-page" class="mx-auto flex h-full min-h-0 w-full max-w-[2000px] gap-4 p-4">
      <aside class="flex shrink-0 flex-col gap-3 pr-2 w-30 sm:w-80">
        <.term_and_search state={@state} />
        <ScheduleChangeGroups.render state={@schedule_change_groups_state} />
        <.schedule_owner_list
          state={@state}
          selected_schedule_order={@schedule_details_order.selected_schedule_order}
        />
      </aside>

      <ScheduleDetailsOrder.render
        state={@schedule_details_order}
        week_schedules={@week_schedules}
        active_change_group={ScheduleChangeGroups.active_change_group(@schedule_change_groups_state)}
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
     |> ScheduleDetailsOrder.sync_selected_term(term_code: selected_term_code)}
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
     |> ScheduleDetailsOrder.sync_selected_term(term_code: selected_term_code)}
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
     |> ScheduleDetailsOrder.sync_selected_term(term_code: selected_term_code)}
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
    {:halt, socket}
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
       | query: query
     })}
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
