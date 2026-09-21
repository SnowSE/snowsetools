defmodule SnowSeToolsWeb.Scheduling.ScheduleTermConflicts do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView

  alias SnowSeTools.Scheduling.{
    AcknowledgedConflictDomainManager,
    ScheduleConflictDetector,
    ScheduleOwnerDomainManager
  }

  alias SnowSeToolsWeb.Scheduling.ScheduleConflictDetail

  defstruct [
    :selected_term_code,
    conflicts_by_owner_key: %{},
    loading?: false,
    error: nil,
    resolved_conflicts: [],
    conflict_count: 0,
    conflicted_course_crns: MapSet.new(),
    acknowledged: MapSet.new(),
    acknowledged_count: 0
  ]

  @type t :: %__MODULE__{
          selected_term_code: String.t() | nil,
          conflicts_by_owner_key: %{optional(String.t()) => [map()]},
          loading?: boolean(),
          error: String.t() | nil,
          resolved_conflicts: [map()],
          conflict_count: non_neg_integer(),
          conflicted_course_crns: MapSet.t(String.t()),
          acknowledged: MapSet.t(String.t()),
          acknowledged_count: non_neg_integer()
        }

  @key :schedule_term_conflicts_state

  def assign_component(socket) do
    initial_state = %__MODULE__{}

    socket =
      if Map.has_key?(socket.assigns, @key) do
        socket
      else
        assign(socket, @key, initial_state)
      end

    maybe_attach_hooks(socket)
  end

  def sync_selected_term(socket, term_code: term_code) when is_binary(term_code) do
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      socket
    else
      updated_state = %{
        state
        | selected_term_code: term_code,
          conflicts_by_owner_key: %{},
          loading?: false,
          error: nil,
          resolved_conflicts: [],
          conflict_count: 0,
          conflicted_course_crns: MapSet.new(),
          acknowledged: MapSet.new(),
          acknowledged_count: 0
      }

      socket
      |> assign(@key, updated_state)
      |> request_acknowledged(term_code: term_code)
      |> maybe_request_conflicts(term_code: term_code)
    end
  end

  def sync_selected_term(socket, term_code: nil), do: socket

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :schedule_term_conflicts_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook(
        "schedule-term-conflicts:info",
        :handle_info,
        &hooked_info/2
      )
      |> LiveView.attach_hook(
        "schedule-term-conflicts:event",
        :handle_event,
        &hooked_event/3
      )
      |> put_in([Access.key(:private), :schedule_term_conflicts_hooks_attached?], true)
    end
  end

  def hooked_info(
        {:term_baseline_conflicts_ready, %{term_code: term_code, result: result}},
        socket
      ) do
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      case result do
        {:ok, %{conflicts_by_owner_key: conflicts_by_owner_key}} ->
          {:halt,
           show_conflicts(socket, %{
             state
             | conflicts_by_owner_key: conflicts_by_owner_key,
               loading?: false,
               error: nil
           })}

        {:error, reason} ->
          Logger.error(
            "Term baseline conflicts failed term=#{term_code} reason=#{inspect(reason)}"
          )

          {:halt,
           assign(socket, @key, %{
             state
             | loading?: false,
               error: inspect(reason),
               resolved_conflicts: [],
               conflict_count: 0,
               conflicted_course_crns: MapSet.new()
           })}
      end
    else
      {:halt, socket}
    end
  end

  def hooked_info({:acknowledged_conflicts, {:listed, payload}}, socket) do
    %{term_code: term_code, fingerprints: fingerprints} = payload
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      {:halt, show_conflicts(socket, %{state | acknowledged: MapSet.new(fingerprints)})}
    else
      {:halt, socket}
    end
  end

  def hooked_info({:acknowledged_conflicts, {:acknowledged, payload}}, socket) do
    %{term_code: term_code, fingerprint: fingerprint} = payload
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      {:halt,
       show_conflicts(socket, %{
         state
         | acknowledged: MapSet.put(state.acknowledged, fingerprint)
       })}
    else
      {:halt, socket}
    end
  end

  def hooked_info({:acknowledged_conflicts, {:reset, %{term_code: term_code}}}, socket) do
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      {:halt, show_conflicts(socket, %{state | acknowledged: MapSet.new()})}
    else
      {:halt, socket}
    end
  end

  def hooked_info({:acknowledged_conflicts, {:error, reason}}, socket) do
    Logger.error("Acknowledged conflicts request failed: #{inspect(reason)}")

    {:halt,
     LiveView.put_flash(
       socket,
       :error,
       "Couldn't save which conflicts you've acknowledged. They are all still listed."
     )}
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  # -- Events ------------------------------------------------------------------

  def hooked_event(
        "schedule-term-conflicts:acknowledge",
        %{"fingerprint" => fingerprint},
        socket
      )
      when is_binary(fingerprint) do
    state = socket.assigns[@key]

    AcknowledgedConflictDomainManager.acknowledge(
      pid: self(),
      user: socket.assigns[:current_user],
      term_code: state.selected_term_code,
      fingerprint: fingerprint
    )

    {:halt, socket}
  end

  def hooked_event("schedule-term-conflicts:reset_acknowledged", _params, socket) do
    state = socket.assigns[@key]

    AcknowledgedConflictDomainManager.reset(
      pid: self(),
      user: socket.assigns[:current_user],
      term_code: state.selected_term_code
    )

    {:halt, socket}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def conflicted_course_crns(%__MODULE__{} = state), do: state.conflicted_course_crns

  # -- Trigger async conflict detection in a Task and send result back via message --

  defp maybe_request_conflicts(socket, term_code: term_code) do
    if LiveView.connected?(socket) do
      manager = self()

      Task.start(fn ->
        result =
          try do
            with {:ok, owner_course_lists} <-
                   ScheduleOwnerDomainManager.get_term_owner_course_lists(term_code: term_code),
                 true <- owner_course_lists != [] do
              conflicts =
                ScheduleConflictDetector.detect_term_conflicts(
                  owner_course_lists: owner_course_lists,
                  active_changes: []
                )

              {:ok, conflicts}
            else
              false -> {:ok, %{conflicts_by_owner_key: %{}}}
              other -> other
            end
          rescue
            e -> {:error, e}
          catch
            kind, reason -> {:error, {kind, reason}}
          end

        send(manager, {:term_baseline_conflicts_ready, %{term_code: term_code, result: result}})
      end)

      assign(socket, @key, %{socket.assigns[@key] | loading?: true})
    else
      socket
    end
  end

  # -- Resolve raw conflict data into display-ready structs using viewer state metadata --

  defp resolve_conflicts_from_viewer_state(conflicts_by_owner_key, socket) do
    owner_metadata = get_owner_metadata(socket)
    metadata_by_key = Enum.into(owner_metadata, %{}, &{&1.key, &1})

    conflicts_by_owner_key
    |> Enum.map(fn {owner_key, conflicts} ->
      metadata = Map.get(metadata_by_key, owner_key)
      name = Map.get(metadata, :name) || owner_key

      icon_name =
        case Map.get(metadata, :type) do
          :professor -> "hero-user"
          :room -> "hero-building-office-2"
          :academic_program_semester -> "hero-academic-cap"
          _other -> "hero-question-mark-circle"
        end

      %{
        owner_key: owner_key,
        owner_name: name,
        icon_name: icon_name,
        conflicts: conflicts
      }
    end)
    |> Enum.sort_by(& &1.owner_name)
  end

  defp get_owner_metadata(socket) do
    case socket.assigns[:schedule_viewer_state] do
      %{schedule_owners_metadata_by_term: by_term, selected_term_code: term_code} ->
        Map.get(by_term, term_code, [])

      _ ->
        []
    end
  end

  # The one place the panel decides what is on screen: everything detected,
  # minus what this person has already looked at. Conflict highlighting in the
  # week grid comes from the same list, so an acknowledged clash stops colouring
  # its courses too.
  defp show_conflicts(socket, %__MODULE__{} = state) do
    visible = reject_acknowledged(state.conflicts_by_owner_key, state.acknowledged)
    resolved = resolve_conflicts_from_viewer_state(visible, socket)

    assign(socket, @key, %{
      state
      | resolved_conflicts: resolved,
        conflict_count: count_conflicts(resolved),
        conflicted_course_crns: conflict_crns(visible),
        acknowledged_count: acknowledged_count(state)
    })
  end

  defp reject_acknowledged(conflicts_by_owner_key, acknowledged) do
    conflicts_by_owner_key
    |> Enum.map(fn {owner_key, conflicts} ->
      {owner_key, Enum.reject(conflicts, &acknowledged?(&1, acknowledged))}
    end)
    |> Enum.reject(fn {_owner_key, conflicts} -> conflicts == [] end)
    |> Map.new()
  end

  # How many of the conflicts this term actually has are being kept off the
  # list — not how many were ever acknowledged, so the count matches what
  # resetting would bring back.
  defp acknowledged_count(%__MODULE__{} = state) do
    state.conflicts_by_owner_key
    |> Map.values()
    |> List.flatten()
    |> Enum.filter(&acknowledged?(&1, state.acknowledged))
    |> Enum.map(&fingerprint/1)
    |> Enum.uniq()
    |> length()
  end

  defp acknowledged?(conflict, acknowledged),
    do: MapSet.member?(acknowledged, fingerprint(conflict))

  defp fingerprint(conflict),
    do: Map.get(conflict, :fingerprint, Map.get(conflict, "fingerprint"))

  defp request_acknowledged(socket, term_code: term_code) do
    if LiveView.connected?(socket) do
      AcknowledgedConflictDomainManager.list(
        pid: self(),
        user: socket.assigns[:current_user],
        term_code: term_code
      )
    end

    socket
  end

  defp count_conflicts(owners),
    do: Enum.reduce(owners, 0, &(&2 + length(&1.conflicts)))

  defp conflict_crns(conflicts_by_owner_key) do
    conflicts_by_owner_key
    |> Map.values()
    |> List.flatten()
    |> Enum.flat_map(&conflict_course_crns/1)
    |> MapSet.new()
  end

  defp conflict_course_crns(conflict) do
    Map.get(conflict, :course_crns, Map.get(conflict, "course_crns", []))
  end

  # -- Rendering --

  attr :state, __MODULE__, required: true

  def render(assigns) do
    ~H"""
    <div
      id="schedule-term-conflicts"
      class="flex-1 min-h-0  border-t border-slate-800/80 pt-3 flex flex-col"
    >
      <div class="flex items-center justify-between gap-2">
        <h3 class="font-semibold uppercase tracking-wider text-slate-400">
          Schedule Conflicts
        </h3>
        <.status_badge
          loading={@state.loading?}
          error={@state.error}
          conflict_count={@state.conflict_count}
        />
      </div>

      <.acknowledged_line :if={@state.acknowledged_count > 0} count={@state.acknowledged_count} />

      <.empty_or_error_state
        loading={@state.loading?}
        error={@state.error}
        resolved_conflicts={@state.resolved_conflicts}
        acknowledged_count={@state.acknowledged_count}
      />

      <%= unless Enum.empty?(@state.resolved_conflicts) do %>
        <div class="flex-1 flex flex-col gap-2 pr-1 overflow-auto">
          <.owner_conflict_card :for={owner <- @state.resolved_conflicts} owner={owner} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :loading, :boolean, required: true
  attr :error, :any, default: nil
  attr :conflict_count, :integer, required: true

  defp status_badge(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <%= if @loading do %>
        <div class="inline-flex items-center gap-1 text-[10px] font-medium text-indigo-300">
          <.icon name="hero-arrow-path" class="size-3 animate-spin" />
          <span>Checking</span>
        </div>
      <% end %>

      <%= if @error do %>
        <div class="inline-flex items-center gap-1 text-[10px] font-medium text-red-300">
          <.icon name="hero-exclamation-triangle" class="size-3" />
          <span>Failed</span>
        </div>
      <% end %>

      <%= if not @loading and is_nil(@error) do %>
        <span class="text-[10px] text-slate-500">
          {@conflict_count}
        </span>
      <% end %>
    </div>
    """
  end

  attr :count, :integer, required: true

  defp acknowledged_line(assigns) do
    ~H"""
    <div id="schedule-conflicts-acknowledged" class="mt-1 flex items-center gap-2 text-[10px]">
      <span class="text-slate-500">
        {@count} acknowledged
      </span>
      <button
        type="button"
        id="schedule-conflicts-reset-acknowledged"
        phx-click="schedule-term-conflicts:reset_acknowledged"
        class="cursor-pointer text-indigo-300 underline decoration-dotted underline-offset-2 transition-colors hover:text-indigo-200"
      >
        Reset acknowledged
      </button>
    </div>
    """
  end

  attr :loading, :boolean, required: true
  attr :error, :any, default: nil
  attr :resolved_conflicts, :list, default: []
  attr :acknowledged_count, :integer, default: 0

  defp empty_or_error_state(assigns) do
    ~H"""
    <%= cond do %>
      <% @loading and Enum.empty?(@resolved_conflicts) -> %>
        <div class="rounded-md border border-dashed border-slate-700/60 px-3 py-4 text-center text-xs text-slate-500">
          Checking for conflicts...
        </div>
      <% not @loading and Enum.empty?(@resolved_conflicts) and @acknowledged_count > 0 -> %>
        <div class="rounded-md border border-dashed border-slate-700/60 px-3 py-4 text-center text-xs text-slate-500">
          Nothing left to look at — every conflict in this term is acknowledged.
        </div>
      <% not @loading and Enum.empty?(@resolved_conflicts) -> %>
        <div class="rounded-md border border-dashed border-slate-700/60 px-3 py-4 text-center text-xs text-slate-500">
          No conflicts found.
        </div>
      <% @error -> %>
        <div class="rounded-md border border-dashed border-red-900/40 px-3 py-4 text-center text-xs text-red-400">
          Conflict detection failed: {@error}
        </div>
      <% true -> %>
        <div></div>
    <% end %>
    """
  end

  attr :owner, :map, required: true

  defp owner_conflict_card(assigns) do
    ~H"""
    <div
      id={owner_conflict_dom_id(@owner.owner_key)}
      data-owner-key={@owner.owner_key}
      class="rounded-lg border border-red-500/25 bg-red-950/15 p-2.5"
    >
      <div class="mb-1 flex items-center gap-1.5  text-red-200">
        <.icon name={@owner.icon_name} class="size-3.5 shrink-0 text-red-400" />
        <span class="truncate">{@owner.owner_name}</span>
        <span class="ml-auto rounded bg-red-900/60 px-1.5 py-0.5 text-red-200 text-sm">
          {length(@owner.conflicts)}
        </span>
      </div>

      <div class="space-y-1">
        <%= for conflict <- @owner.conflicts do %>
          <ScheduleConflictDetail.render
            conflict={conflict}
            acknowledge_event="schedule-term-conflicts:acknowledge"
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp owner_conflict_dom_id(owner_key) do
    "term-conflict-owner-#{:erlang.phash2(owner_key)}"
  end
end
