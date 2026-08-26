defmodule SnowSeToolsWeb.Scheduling.ScheduleDetailsOrder do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeToolsWeb.Scheduling.OverlayGroup
  alias SnowSeToolsWeb.Scheduling.ScheduleOrder
  alias SnowSeToolsWeb.Scheduling.ScheduleOverlays
  alias SnowSeToolsWeb.Scheduling.WeekSchedule

  defstruct [
    :selected_schedule_order,
    :overlays,
    :open_overlay_menu_key
  ]

  @key :schedule_details_order

  def assign_component(socket) do
    socket
    |> assign(@key, %__MODULE__{
      selected_schedule_order: ScheduleOrder.new(),
      overlays: ScheduleOverlays.new(),
      open_overlay_menu_key: nil
    })
    |> maybe_attach_hooks()
  end

  # -- Public API used by the search, change groups and conflicts panels --

  @doc "Every selected owner key, whether shown solo or inside an overlay group."
  def selected_owner_order(%__MODULE__{} = state) do
    ScheduleOrder.new(keys: all_owner_keys(state))
  end

  def selected_owner?(%__MODULE__{} = state, key: key) when is_binary(key) do
    ScheduleOrder.member?(order: state.selected_schedule_order, key: key) or
      ScheduleOverlays.owner_group(overlays: state.overlays, owner_key: key) != nil
  end

  @doc "Selects the owner if it isn't already on screen (solo or in a group)."
  def ensure_owner_selected(socket, key: key) when is_binary(key) do
    selected_term_code = socket.assigns.schedule_viewer_state.selected_term_code

    if is_binary(selected_term_code) and !selected_owner?(socket.assigns[@key], key: key) do
      socket
      |> WeekSchedule.assign_owner(owner_key: key, selected_term_code: selected_term_code)
      |> assign(@key, %{
        socket.assigns[@key]
        | selected_schedule_order:
            ScheduleOrder.put(order: socket.assigns[@key].selected_schedule_order, key: key)
      })
    else
      socket
    end
  end

  @doc "Selects the owner, or deselects it if already on screen (solo or in a group)."
  def toggle_owner(socket, key: key) when is_binary(key) do
    if selected_owner?(socket.assigns[@key], key: key) do
      remove_owner(socket, key: key)
    else
      ensure_owner_selected(socket, key: key)
    end
  end

  attr :state, __MODULE__, required: true
  attr :week_schedules, :map, required: true
  attr :week_schedule_edit_course_modal, :map, default: nil
  attr :active_change_group, :map, default: nil
  attr :conflicted_course_crns, :any, default: MapSet.new()
  attr :active_conflicted_course_crns, :any, default: MapSet.new()
  attr :schedule_owners_metadata, :list, default: []

  def render(assigns) do
    ~H"""
    <section class="min-w-0 flex-1 overflow-y-auto">
      <div
        :if={ScheduleOrder.size(@state.selected_schedule_order) > 0}
        class="flex items-center justify-end"
      >
        <button
          id="clear-selected-schedules"
          type="button"
          phx-click="schedule-details-order:clear_selected"
          class={[
            "inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs transition",
            "bg-red-950/50 text-red-300 hover:bg-red-900/70 hover:text-red-100"
          ]}
        >
          <.icon name="hero-x-mark" class="size-3" /> Clear Selection
        </button>
      </div>

      <div
        :if={ScheduleOrder.size(@state.selected_schedule_order) == 0}
        id="scheduling-empty-selection"
        class="flex h-full min-h-96 items-center justify-center rounded-xl border-2 border-dashed border-slate-800 text-sm text-slate-500"
      >
        Select a professor, room, or program semester schedule.
      </div>

      <div
        id="selected-schedules"
        phx-hook=".ScheduleDetailsOrder"
        class="flex flex-wrap justify-center"
      >
        <%= for {key, position} <- Enum.with_index(ScheduleOrder.to_list(@state.selected_schedule_order)) do %>
          <%= cond do %>
            <% ScheduleOverlays.group_key?(key) -> %>
              <OverlayGroup.render
                group_key={key}
                member_keys={ScheduleOverlays.members(overlays: @state.overlays, group_key: key)}
                week_schedules={@week_schedules}
                position={position}
                total_count={ScheduleOrder.size(@state.selected_schedule_order)}
                active_change_group={@active_change_group}
                conflicted_course_crns={@conflicted_course_crns}
                active_conflicted_course_crns={@active_conflicted_course_crns}
                overlay_targets={overlay_targets(@state, @week_schedules, key)}
                overlay_menu_open?={@state.open_overlay_menu_key == key}
              />
            <% week_schedule = @week_schedules[key] -> %>
              <WeekSchedule.render
                state={week_schedule}
                position={position}
                total_count={ScheduleOrder.size(@state.selected_schedule_order)}
                active_change_group={@active_change_group}
                conflicted_course_crns={@conflicted_course_crns}
                active_conflicted_course_crns={@active_conflicted_course_crns}
                schedule_owners_metadata={@schedule_owners_metadata}
                edit_course_modal={@week_schedule_edit_course_modal}
                overlay_targets={overlay_targets(@state, @week_schedules, key)}
                overlay_menu_open?={@state.open_overlay_menu_key == key}
              />
            <% true -> %>
              <div
                id={"selected-schedule-placeholder-#{key}"}
                class="w-[700px] rounded-lg border border-dashed border-slate-800/80 bg-slate-950/35 p-3 text-sm text-slate-500"
              >
                Loading schedule...
              </div>
          <% end %>
        <% end %>
      </div>
    </section>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ScheduleDetailsOrder">
      export default {
        mounted() {
          this.draggedKey = null;
          this.draggedCard = null;
          this.dropTargetCard = null;
          this.dropSpacer = null;

          this.onDragStart = (event) => {
            const card = event.target.closest("[data-schedule-card]");
            if (!card || !this.el.contains(card)) {
              return;
            }

            this.draggedKey = card.dataset.scheduleKey;
            this.draggedCard = card;
            card.classList.add("opacity-60");

            if (event.dataTransfer) {
              event.dataTransfer.effectAllowed = "move";
              event.dataTransfer.setData("text/plain", this.draggedKey);
            }
          };

          this.onDragOver = (event) => {
            if (!this.draggedKey) {
              return;
            }

            event.preventDefault();
            if (event.dataTransfer) {
              event.dataTransfer.dropEffect = "move";
            }

            const card = event.target.closest("[data-schedule-card]");
            if (
              card &&
              card.hasAttribute("data-drop-spacer") &&
              this.dropTargetCard
            ) {
              return;
            }

            if (!card || !this.el.contains(card) || card.dataset.scheduleKey === this.draggedKey) {
              this.setDropTarget(null);
              return;
            }

            this.setDropTarget(card);
          };

          this.onDrop = (event) => {
            if (!this.draggedKey) {
              return;
            }

            event.preventDefault();
            const card = event.target.closest("[data-schedule-card]");
            const targetKey =
              card && this.el.contains(card)
                ? card.hasAttribute("data-drop-spacer")
                  ? this.dropTargetCard && this.dropTargetCard.dataset.scheduleKey
                  : card.dataset.scheduleKey
                : null;

            this.pushEvent("schedule-details-order:reorder_schedule", {
              dragged_key: this.draggedKey,
              target_key: targetKey,
            });

            this.clearDraggingState();
          };

          this.onDragEnd = () => {
            this.clearDraggingState();
          };

          this.onKeyDown = (event) => {
            const card = event.target.closest("[data-schedule-card]");
            if (
              !card ||
              !this.el.contains(card) ||
              card.hasAttribute("data-drop-spacer") ||
              !event.altKey
            ) {
              return;
            }

            if (event.key !== "ArrowUp" && event.key !== "ArrowDown") {
              return;
            }

            event.preventDefault();
            this.pushEvent("schedule-details-order:move_schedule", {
              key: card.dataset.scheduleKey,
              direction: event.key === "ArrowUp" ? "up" : "down",
            });
          };

          this.el.addEventListener("dragstart", this.onDragStart);
          this.el.addEventListener("dragover", this.onDragOver);
          this.el.addEventListener("drop", this.onDrop);
          this.el.addEventListener("dragend", this.onDragEnd);
          this.el.addEventListener("keydown", this.onKeyDown);
        },

        destroyed() {
          this.el.removeEventListener("dragstart", this.onDragStart);
          this.el.removeEventListener("dragover", this.onDragOver);
          this.el.removeEventListener("drop", this.onDrop);
          this.el.removeEventListener("dragend", this.onDragEnd);
          this.el.removeEventListener("keydown", this.onKeyDown);
        },

        setDropTarget(card) {
          if (this.dropTargetCard === card) {
            return;
          }

          const beforeRects = this.captureCardRects();

          this.removeDropSpacer();

          if (this.dropTargetCard) {
            this.dropTargetCard.removeAttribute("data-drop-target");
          }

          this.dropTargetCard = card;

          if (!card) {
            this.animateReflow(beforeRects);
            return;
          }

          card.setAttribute("data-drop-target", "true");

          this.insertDropSpacer(card);
          this.animateReflow(beforeRects);
        },

        clearDraggingState() {
          if (this.draggedCard) {
            this.draggedCard.classList.remove("opacity-60");
          }

          this.setDropTarget(null);

          this.draggedKey = null;
          this.draggedCard = null;
        },

        captureCardRects() {
          const rects = new Map();

          this.getDroppableCards().forEach((card) => {
            rects.set(card.dataset.scheduleKey, card.getBoundingClientRect());
          });

          return rects;
        },

        getDroppableCards() {
          return Array.from(this.el.querySelectorAll("[data-schedule-card]")).filter((card) => {
            return (
              card.dataset.scheduleKey !== this.draggedKey &&
              !card.hasAttribute("data-drop-spacer")
            );
          });
        },

        insertDropSpacer(card) {
          const spacer = document.createElement("div");
          const rect = card.getBoundingClientRect();

          spacer.setAttribute("data-schedule-card", "true");
          spacer.setAttribute("data-drop-spacer", "true");
          spacer.className =
            "w-[700px] rounded-lg border border-dashed border-indigo-400/35 bg-indigo-950/20 shadow-sm shadow-indigo-950/10 transition-[height,opacity,transform] duration-200 ease-out";
          spacer.style.height = `${Math.max(rect.height, 160)}px`;

          card.before(spacer);
          this.dropSpacer = spacer;
        },

        removeDropSpacer() {
          if (!this.dropSpacer) {
            return;
          }

          this.dropSpacer.remove();
          this.dropSpacer = null;
        },

        animateReflow(beforeRects) {
          requestAnimationFrame(() => {
            this.getDroppableCards().forEach((card) => {
              const beforeRect = beforeRects.get(card.dataset.scheduleKey);
              if (!beforeRect) {
                return;
              }

              const afterRect = card.getBoundingClientRect();
              const deltaX = beforeRect.left - afterRect.left;
              const deltaY = beforeRect.top - afterRect.top;

              if (deltaX === 0 && deltaY === 0) {
                return;
              }

              card.style.transition = "transform 0ms";
              card.style.transform = `translate(${deltaX}px, ${deltaY}px)`;
              card.style.willChange = "transform";
              card.getBoundingClientRect();
              card.style.transition = "transform 220ms cubic-bezier(0.2, 0, 0, 1)";
              card.style.transform = "translate(0px, 0px)";

              window.setTimeout(() => {
                card.style.transition = "";
                card.style.transform = "";
                card.style.willChange = "";
              }, 220);
            });
          });
        },

      }
    </script>
    """
  end

  def sync_selected_term(socket, term_code: term_code) when is_binary(term_code) do
    state = socket.assigns[@key]

    socket
    |> refresh_selected_week_schedules(owner_keys: all_owner_keys(state), term_code: term_code)
    |> assign(@key, state)
  end

  def sync_selected_term(socket, term_code: nil) do
    socket
    |> WeekSchedule.clear_owners()
    |> assign(@key, reset_selection(socket.assigns[@key]))
  end

  def hooked_info(
        {:schedule_owners,
         {:term_schedule_owners_replaced,
          %{term_code: term_code, schedule_owners: schedule_owners}}},
        socket
      ) do
    selected_term_code = socket.assigns.schedule_viewer_state.selected_term_code

    if selected_term_code == term_code do
      state = socket.assigns[@key]
      replacement_keys = MapSet.new(schedule_owners, & &1.key)

      removed_keys =
        state
        |> all_owner_keys()
        |> Enum.reject(&MapSet.member?(replacement_keys, &1))

      socket =
        Enum.reduce(removed_keys, socket, fn owner_key, acc ->
          WeekSchedule.remove_owner(acc, owner_key: owner_key)
        end)

      overlays =
        ScheduleOverlays.retain_owner_keys(overlays: state.overlays, keys: replacement_keys)

      retained_order_keys =
        MapSet.union(replacement_keys, MapSet.new(ScheduleOverlays.group_keys(overlays)))

      state = %{
        state
        | overlays: overlays,
          selected_schedule_order:
            ScheduleOrder.retain_keys(
              order: state.selected_schedule_order,
              keys: retained_order_keys
            )
      }

      {:halt, assign(socket, @key, dissolve_singleton_groups(state))}
    else
      {:cont, socket}
    end
  end

  def hooked_info(
        {:schedule_owners,
         {:schedule_owner_metadata_deleted, %{term_code: term_code, owner_key: owner_key}}},
        socket
      ) do
    selected_term_code = socket.assigns.schedule_viewer_state.selected_term_code

    if selected_term_code == term_code do
      {:halt, remove_owner(socket, key: owner_key)}
    else
      {:cont, socket}
    end
  end

  def hooked_info({:schedule_owners, {:term_deleted, %{term_code: term_code}}}, socket) do
    if socket.assigns.schedule_viewer_state.selected_term_code == term_code do
      {:halt,
       socket
       |> WeekSchedule.clear_owners()
       |> assign(@key, reset_selection(socket.assigns[@key]))}
    else
      {:cont, socket}
    end
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  def hooked_event("schedule-details-order:toggle", %{"key" => key}, socket) do
    {:halt, toggle_owner(socket, key: key)}
  end

  def hooked_event("schedule-details-order:view_schedule", %{"key" => key}, socket) do
    {:halt, ensure_owner_selected(socket, key: key)}
  end

  def hooked_event("schedule-details-order:clear_selected", _params, socket) do
    {:halt,
     socket
     |> WeekSchedule.clear_owners()
     |> assign(@key, reset_selection(socket.assigns[@key]))}
  end

  def hooked_event("schedule-details-order:close_schedule", %{"key" => key}, socket) do
    if ScheduleOverlays.group_key?(key) do
      {:halt, close_group(socket, group_key: key)}
    else
      {:halt, remove_owner(socket, key: key)}
    end
  end

  def hooked_event("schedule-details-order:open_overlay_menu", %{"key" => key}, socket) do
    {:halt, assign(socket, @key, %{socket.assigns[@key] | open_overlay_menu_key: key})}
  end

  def hooked_event("schedule-details-order:close_overlay_menu", _params, socket) do
    {:halt, assign(socket, @key, %{socket.assigns[@key] | open_overlay_menu_key: nil})}
  end

  def hooked_event(
        "schedule-details-order:overlay",
        %{"key" => key, "target" => target_key},
        socket
      ) do
    {:halt, overlay(socket, key: key, target_key: target_key)}
  end

  def hooked_event(
        "schedule-details-order:pop_out",
        %{"group" => group_key, "key" => owner_key},
        socket
      ) do
    {:halt, pop_out(socket, group_key: group_key, owner_key: owner_key)}
  end

  def hooked_event("schedule-details-order:separate_all", %{"group" => group_key}, socket) do
    {:halt, separate_all(socket, group_key: group_key)}
  end

  def hooked_event(
        "schedule-details-order:move_schedule",
        %{"key" => key, "direction" => direction},
        socket
      ) do
    order = socket.assigns[@key].selected_schedule_order
    keys = ScheduleOrder.to_list(order)

    case Enum.find_index(keys, &(&1 == key)) do
      nil ->
        Logger.warning("Ignored move for missing schedule #{inspect(key)}")
        {:halt, socket}

      index ->
        reordered_order =
          case direction do
            "up" when index > 0 ->
              ScheduleOrder.move_before(
                order: order,
                dragged_key: key,
                target_key: Enum.at(keys, index - 1)
              )

            "down" when index < length(keys) - 1 ->
              ScheduleOrder.move_before(
                order: order,
                dragged_key: key,
                target_key: Enum.at(keys, index + 2)
              )

            _ ->
              order
          end

        {:halt,
         assign(socket, @key, %{
           socket.assigns[@key]
           | selected_schedule_order: reordered_order
         })}
    end
  end

  def hooked_event(
        "schedule-details-order:reorder_schedule",
        %{"dragged_key" => dragged_key, "target_key" => target_key},
        socket
      ) do
    target_key = normalize_target_key(target_key)

    if ScheduleOrder.member?(
         order: socket.assigns[@key].selected_schedule_order,
         key: dragged_key
       ) do
      reordered_schedule_order =
        ScheduleOrder.move_before(
          order: socket.assigns[@key].selected_schedule_order,
          dragged_key: dragged_key,
          target_key: target_key
        )

      {:halt,
       assign(socket, @key, %{
         socket.assigns[@key]
         | selected_schedule_order: reordered_schedule_order
       })}
    else
      Logger.warning("Ignored reorder for missing dragged schedule #{inspect(dragged_key)}")
      {:halt, socket}
    end
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  # -- Overlay operations --

  # Overlays the card or group at `key` onto `target_key`, which is either a
  # solo card of the same kind (a new group is created in the initiator's
  # place) or an existing group of the same kind (the initiator's schedules
  # join it). A group initiator is flattened into its members, never nested.
  defp overlay(socket, key: key, target_key: target_key) do
    state = socket.assigns[@key]
    order = state.selected_schedule_order

    cond do
      key == target_key or !ScheduleOrder.member?(order: order, key: key) or
          !ScheduleOrder.member?(order: order, key: target_key) ->
        Logger.warning("Ignored overlay of #{inspect(key)} onto #{inspect(target_key)}")
        socket

      !same_kind?(state, socket.assigns.week_schedules, key, target_key) ->
        Logger.warning(
          "Ignored overlay across kinds: #{inspect(key)} onto #{inspect(target_key)}"
        )

        socket

      ScheduleOverlays.group_key?(target_key) ->
        overlays =
          Enum.reduce(entry_owner_keys(state, key), state.overlays, fn owner_key, overlays ->
            ScheduleOverlays.add_member(
              overlays: overlays,
              group_key: target_key,
              owner_key: owner_key
            )
          end)

        assign(socket, @key, %{
          state
          | overlays: drop_group_if_any(overlays, key),
            selected_schedule_order: ScheduleOrder.delete(order: order, key: key),
            open_overlay_menu_key: nil
        })

      true ->
        {group_key, overlays} =
          ScheduleOverlays.create(
            overlays: state.overlays,
            owner_keys: entry_owner_keys(state, key) ++ [target_key]
          )

        # The new group takes the initiator's slot; the initiator gets the first color.
        order =
          order
          |> ScheduleOrder.put_before(key: group_key, before_key: key)
          |> then(&ScheduleOrder.delete(order: &1, key: key))
          |> then(&ScheduleOrder.delete(order: &1, key: target_key))

        assign(socket, @key, %{
          state
          | overlays: drop_group_if_any(overlays, key),
            selected_schedule_order: order,
            open_overlay_menu_key: nil
        })
    end
  end

  defp entry_owner_keys(state, key) do
    if ScheduleOverlays.group_key?(key),
      do: ScheduleOverlays.members(overlays: state.overlays, group_key: key),
      else: [key]
  end

  defp drop_group_if_any(overlays, key) do
    if ScheduleOverlays.group_key?(key),
      do: ScheduleOverlays.delete_group(overlays: overlays, group_key: key),
      else: overlays
  end

  # Removes one member from a group and shows it as a solo card right after
  # the group. A group left with a single member is dissolved into a solo card.
  defp pop_out(socket, group_key: group_key, owner_key: owner_key) do
    state = socket.assigns[@key]
    members = ScheduleOverlays.members(overlays: state.overlays, group_key: group_key)

    if owner_key in members do
      state = %{
        state
        | overlays:
            ScheduleOverlays.remove_member(
              overlays: state.overlays,
              group_key: group_key,
              owner_key: owner_key
            ),
          selected_schedule_order:
            ScheduleOrder.put_after(state.selected_schedule_order,
              key: owner_key,
              after_key: group_key
            )
      }

      assign(socket, @key, dissolve_singleton_groups(state))
    else
      Logger.warning("Ignored pop out of #{inspect(owner_key)} from #{inspect(group_key)}")
      socket
    end
  end

  # Turns a group back into solo cards, in the group's slot.
  defp separate_all(socket, group_key: group_key) do
    state = socket.assigns[@key]
    members = ScheduleOverlays.members(overlays: state.overlays, group_key: group_key)

    order =
      members
      |> Enum.reverse()
      |> Enum.reduce(state.selected_schedule_order, fn owner_key, order ->
        ScheduleOrder.put_after(order, key: owner_key, after_key: group_key)
      end)
      |> then(&ScheduleOrder.delete(order: &1, key: group_key))

    assign(socket, @key, %{
      state
      | overlays: ScheduleOverlays.delete_group(overlays: state.overlays, group_key: group_key),
        selected_schedule_order: order,
        open_overlay_menu_key: nil
    })
  end

  # Closes a group and every schedule in it.
  defp close_group(socket, group_key: group_key) do
    state = socket.assigns[@key]
    members = ScheduleOverlays.members(overlays: state.overlays, group_key: group_key)

    socket =
      Enum.reduce(members, socket, fn owner_key, acc ->
        WeekSchedule.remove_owner(acc, owner_key: owner_key)
      end)

    assign(socket, @key, %{
      state
      | overlays: ScheduleOverlays.delete_group(overlays: state.overlays, group_key: group_key),
        selected_schedule_order:
          ScheduleOrder.delete(order: state.selected_schedule_order, key: group_key),
        open_overlay_menu_key: nil
    })
  end

  # Removes an owner wherever it is shown: as a solo card or inside a group.
  defp remove_owner(socket, key: key) do
    state = socket.assigns[@key]

    state =
      case ScheduleOverlays.owner_group(overlays: state.overlays, owner_key: key) do
        nil ->
          %{
            state
            | selected_schedule_order:
                ScheduleOrder.delete(order: state.selected_schedule_order, key: key)
          }

        group_key ->
          %{
            state
            | overlays:
                ScheduleOverlays.remove_member(
                  overlays: state.overlays,
                  group_key: group_key,
                  owner_key: key
                )
          }
      end

    socket
    |> WeekSchedule.remove_owner(owner_key: key)
    |> assign(@key, dissolve_singleton_groups(state))
  end

  # A group with fewer than two members is shown as a plain card (or nothing).
  defp dissolve_singleton_groups(%__MODULE__{} = state) do
    Enum.reduce(ScheduleOverlays.group_keys(state.overlays), state, fn group_key, state ->
      case ScheduleOverlays.members(overlays: state.overlays, group_key: group_key) do
        [_first, _second | _rest] ->
          state

        members ->
          order =
            members
            |> Enum.reduce(state.selected_schedule_order, fn owner_key, order ->
              ScheduleOrder.put_after(order, key: owner_key, after_key: group_key)
            end)
            |> then(&ScheduleOrder.delete(order: &1, key: group_key))

          %{
            state
            | overlays:
                ScheduleOverlays.delete_group(overlays: state.overlays, group_key: group_key),
              selected_schedule_order: order
          }
      end
    end)
  end

  defp reset_selection(%__MODULE__{} = state) do
    %{
      state
      | selected_schedule_order: ScheduleOrder.new(),
        overlays: ScheduleOverlays.new(),
        open_overlay_menu_key: nil
    }
  end

  defp all_owner_keys(%__MODULE__{} = state) do
    state.selected_schedule_order
    |> ScheduleOrder.to_list()
    |> Enum.flat_map(fn key ->
      if ScheduleOverlays.group_key?(key) do
        ScheduleOverlays.members(overlays: state.overlays, group_key: key)
      else
        [key]
      end
    end)
  end

  # Same-kind cards and groups the card at `key` could be overlaid onto.
  # Empty while the card is alone in its kind — which is when the overlay
  # button stays hidden.
  defp overlay_targets(%__MODULE__{} = state, week_schedules, key) do
    case entry_type(state, week_schedules, key) do
      nil ->
        []

      type ->
        state.selected_schedule_order
        |> ScheduleOrder.to_list()
        |> Enum.reject(&(&1 == key))
        |> Enum.filter(&(entry_type(state, week_schedules, &1) == type))
        |> Enum.map(fn target_key ->
          %{
            key: target_key,
            label: entry_label(state, week_schedules, target_key),
            group?: ScheduleOverlays.group_key?(target_key)
          }
        end)
    end
  end

  defp same_kind?(state, week_schedules, key, other_key) do
    type = entry_type(state, week_schedules, key)
    type != nil and type == entry_type(state, week_schedules, other_key)
  end

  # The owner kind of a solo card or a group. Solo cards are typed from their
  # owner key so the button appears before the schedule finishes loading.
  defp entry_type(state, week_schedules, key) do
    if ScheduleOverlays.group_key?(key) do
      case ScheduleOverlays.members(overlays: state.overlays, group_key: key) do
        [first | _rest] -> entry_type(state, week_schedules, first)
        [] -> nil
      end
    else
      owner_key_type(key)
    end
  end

  defp owner_key_type("professor:" <> _name), do: :professor
  defp owner_key_type("room:" <> _name), do: :room
  defp owner_key_type("academic_program_semester:" <> _name), do: :academic_program_semester
  defp owner_key_type(_key), do: nil

  defp entry_label(state, week_schedules, key) do
    if ScheduleOverlays.group_key?(key) do
      ScheduleOverlays.members(overlays: state.overlays, group_key: key)
      |> Enum.map_join(", ", &entry_label(state, week_schedules, &1))
    else
      case week_schedules[key] do
        %WeekSchedule{week_schedule: %{type: :academic_program_semester} = schedule} ->
          "#{schedule.program_name} · #{schedule.semester_name}"

        %WeekSchedule{week_schedule: %{name: name}} when is_binary(name) ->
          name

        _loading ->
          key |> String.split(":", parts: 2) |> List.last()
      end
    end
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :schedule_details_order_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("schedule-details-order:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("schedule-details-order:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :schedule_details_order_hooks_attached?], true)
    end
  end

  defp refresh_selected_week_schedules(socket, owner_keys: owner_keys, term_code: term_code) do
    Enum.reduce(owner_keys, socket, fn owner_key, acc ->
      WeekSchedule.assign_owner(acc, owner_key: owner_key, selected_term_code: term_code)
    end)
  end

  defp normalize_target_key(nil), do: nil
  defp normalize_target_key(""), do: nil
  defp normalize_target_key(target_key), do: target_key
end
