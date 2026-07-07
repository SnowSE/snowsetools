defmodule SnowSeToolsWeb.Scheduling.ScheduleTermConflicts do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView

  alias SnowSeTools.Scheduling.{
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
    conflict_count: 0
  ]

  @type t :: %__MODULE__{
          selected_term_code: String.t() | nil,
          conflicts_by_owner_key: %{optional(String.t()) => [map()]},
          loading?: boolean(),
          error: String.t() | nil,
          resolved_conflicts: [map()],
          conflict_count: non_neg_integer()
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
          conflict_count: 0
      }

      socket
      |> assign(@key, updated_state)
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
          resolved_conflicts =
            resolve_conflicts_from_viewer_state(
              conflicts_by_owner_key,
              socket
            )

          {:halt,
           assign(socket, @key, %{
             state
             | conflicts_by_owner_key: conflicts_by_owner_key,
               loading?: false,
               error: nil,
               resolved_conflicts: resolved_conflicts,
               conflict_count: count_conflicts(resolved_conflicts)
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
               conflict_count: 0
           })}
      end
    else
      {:halt, socket}
    end
  end

  def hooked_info(_message, socket), do: {:cont, socket}

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

  defp count_conflicts(owners),
    do: Enum.reduce(owners, 0, &(&2 + length(&1.conflicts)))

  # -- Rendering --

  attr :state, __MODULE__, required: true

  def render(assigns) do
    ~H"""
    <div id="schedule-term-conflicts" class="min-h-0 border-t border-slate-800/80 pt-3">
      <div class="mb-2 flex items-center justify-between gap-2">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400">
          Schedule Conflicts
        </h3>
        <.status_badge
          loading={@state.loading?}
          error={@state.error}
          conflict_count={@state.conflict_count}
        />
      </div>

      <.empty_or_error_state
        loading={@state.loading?}
        error={@state.error}
        resolved_conflicts={@state.resolved_conflicts}
      />

      <%= unless Enum.empty?(@state.resolved_conflicts) do %>
        <div class="flex min-h-0 flex-col gap-2 overflow-y-auto pr-1">
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

  attr :loading, :boolean, required: true
  attr :error, :any, default: nil
  attr :resolved_conflicts, :list, default: []

  defp empty_or_error_state(assigns) do
    ~H"""
    <%= cond do %>
      <% @loading and Enum.empty?(@resolved_conflicts) -> %>
        <div class="rounded-md border border-dashed border-slate-700/60 px-3 py-4 text-center text-xs text-slate-500">
          Checking for conflicts...
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
        nil
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
      <div class="mb-1 flex items-center gap-1.5 text-[11px] font-medium text-red-200">
        <.icon name={@owner.icon_name} class="size-3.5 shrink-0 text-red-400" />
        <span class="truncate">{@owner.owner_name}</span>
        <span class="ml-auto rounded bg-red-900/60 px-1.5 py-0.5 text-[10px] font-medium text-red-200">
          {length(@owner.conflicts)}
        </span>
      </div>

      <div class="space-y-1">
        <%= for conflict <- @owner.conflicts do %>
          <ScheduleConflictDetail.render conflict={conflict} />
        <% end %>
      </div>
    </div>
    """
  end

  defp owner_conflict_dom_id(owner_key) do
    "term-conflict-owner-#{:erlang.phash2(owner_key)}"
  end
end
