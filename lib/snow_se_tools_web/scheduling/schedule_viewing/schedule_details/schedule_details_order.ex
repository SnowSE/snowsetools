defmodule SnowSeToolsWeb.Scheduling.ScheduleDetailsOrder do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeToolsWeb.Scheduling.ScheduleOrder
  alias SnowSeToolsWeb.Scheduling.WeekSchedule

  defstruct [
    :selected_schedule_order
  ]

  @key :schedule_details_order

  def assign_component(socket) do
    socket
    |> assign(@key, %__MODULE__{
      selected_schedule_order: ScheduleOrder.new()
    })
    |> maybe_attach_hooks()
  end

  def render(assigns) do
    ~H"""
    <section class="min-w-0 flex-1 overflow-y-auto">
      <div class="flex items-center justify-between gap-2 px-1 pb-3">
        <div class="text-sm font-medium text-slate-200">Selected schedules</div>
        <button
          id="clear-selected-schedules"
          type="button"
          phx-click="schedule-details-order:clear_selected"
          disabled={ScheduleOrder.size(@state.selected_schedule_order) == 0}
          class={[
            "inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs transition",
            if(ScheduleOrder.size(@state.selected_schedule_order) == 0,
              do: "invisible cursor-not-allowed",
              else: "bg-red-950/50 text-red-300 hover:bg-red-900/70 hover:text-red-100"
            )
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
        class="flex flex-wrap justify-center gap-3"
      >
        <%= for owner_key <- ScheduleOrder.to_list(@state.selected_schedule_order) do %>
          <%= if week_schedule = @week_schedules[owner_key] do %>
            <WeekSchedule.render state={week_schedule} />
          <% else %>
            <div
              id={"selected-schedule-placeholder-#{owner_key}"}
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

          this.el.addEventListener("dragstart", this.onDragStart);
          this.el.addEventListener("dragover", this.onDragOver);
          this.el.addEventListener("drop", this.onDrop);
          this.el.addEventListener("dragend", this.onDragEnd);
        },

        destroyed() {
          this.el.removeEventListener("dragstart", this.onDragStart);
          this.el.removeEventListener("dragover", this.onDragOver);
          this.el.removeEventListener("drop", this.onDrop);
          this.el.removeEventListener("dragend", this.onDragEnd);
        },

        setDropTarget(card) {
          if (this.dropTargetCard === card) {
            return;
          }

          const beforeRects = this.captureCardRects();

          this.removeDropSpacer();

          if (this.dropTargetCard) {
            this.dropTargetCard.classList.remove(
              "outline",
              "outline-2",
              "outline-indigo-400/60",
              "outline-offset-4",
              "bg-indigo-950/20"
            );
            this.dropTargetCard.removeAttribute("data-drop-target");
          }

          this.dropTargetCard = card;

          if (!card) {
            this.animateReflow(beforeRects);
            return;
          }

          card.setAttribute("data-drop-target", "true");
          card.classList.add(
            "outline",
            "outline-2",
            "outline-indigo-400/60",
            "outline-offset-4",
            "bg-indigo-950/20"
          );

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
    |> refresh_selected_week_schedules(
      selected_schedule_order: state.selected_schedule_order,
      term_code: term_code
    )
    |> assign(@key, state)
  end

  def sync_selected_term(socket, term_code: nil) do
    socket
    |> WeekSchedule.clear_owners()
    |> assign(@key, %{
      socket.assigns[@key]
      | selected_schedule_order: ScheduleOrder.new()
    })
  end

  def hooked_info(
        {:schedule_owners,
         {:term_schedule_owners_replaced,
          %{term_code: term_code, schedule_owners: schedule_owners}}},
        socket
      ) do
    selected_term_code = socket.assigns.schedule_viewer_state.selected_term_code

    if selected_term_code == term_code do
      replacement_keys = MapSet.new(schedule_owners, & &1.key)

      selected_schedule_order =
        ScheduleOrder.retain_keys(
          order: socket.assigns[@key].selected_schedule_order,
          keys: replacement_keys
        )

      removed_keys =
        socket.assigns[@key].selected_schedule_order
        |> ScheduleOrder.to_list()
        |> Enum.reject(&MapSet.member?(replacement_keys, &1))

      socket =
        Enum.reduce(removed_keys, socket, fn owner_key, acc ->
          WeekSchedule.remove_owner(acc, owner_key: owner_key)
        end)

      {:halt,
       assign(socket, @key, %{
         socket.assigns[@key]
         | selected_schedule_order: selected_schedule_order
       })}
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
      {:halt,
       socket
       |> WeekSchedule.remove_owner(owner_key: owner_key)
       |> assign(@key, %{
         socket.assigns[@key]
         | selected_schedule_order:
             ScheduleOrder.delete(
               order: socket.assigns[@key].selected_schedule_order,
               key: owner_key
             )
       })}
    else
      {:cont, socket}
    end
  end

  def hooked_info({:schedule_owners, {:term_deleted, %{term_code: term_code}}}, socket) do
    if socket.assigns.schedule_viewer_state.selected_term_code == term_code do
      {:halt,
       socket
       |> WeekSchedule.clear_owners()
       |> assign(@key, %{
         socket.assigns[@key]
         | selected_schedule_order: ScheduleOrder.new()
       })}
    else
      {:cont, socket}
    end
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  def hooked_event("schedule-details-order:toggle", %{"key" => key}, socket) do
    selected_term_code = socket.assigns.schedule_viewer_state.selected_term_code

    if ScheduleOrder.member?(order: socket.assigns[@key].selected_schedule_order, key: key) do
      {:halt,
       socket
       |> WeekSchedule.remove_owner(owner_key: key)
       |> assign(@key, %{
         socket.assigns[@key]
         | selected_schedule_order:
             ScheduleOrder.delete(
               order: socket.assigns[@key].selected_schedule_order,
               key: key
             )
       })}
    else
      socket =
        if is_binary(selected_term_code) do
          WeekSchedule.assign_owner(socket,
            owner_key: key,
            selected_term_code: selected_term_code
          )
        else
          socket
        end

      {:halt,
       assign(socket, @key, %{
         socket.assigns[@key]
         | selected_schedule_order:
             ScheduleOrder.put(order: socket.assigns[@key].selected_schedule_order, key: key)
       })}
    end
  end

  def hooked_event("schedule-details-order:clear_selected", _params, socket) do
    {:halt,
     socket
     |> WeekSchedule.clear_owners()
     |> assign(@key, %{
       socket.assigns[@key]
       | selected_schedule_order: ScheduleOrder.new()
     })}
  end

  def hooked_event("schedule-details-order:close_schedule", %{"key" => key}, socket) do
    {:halt,
     socket
     |> WeekSchedule.remove_owner(owner_key: key)
     |> assign(@key, %{
       socket.assigns[@key]
       | selected_schedule_order:
           ScheduleOrder.delete(
             order: socket.assigns[@key].selected_schedule_order,
             key: key
           )
     })}
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

  defp refresh_selected_week_schedules(socket, opts)
       when is_list(opts) do
    selected_schedule_order = Keyword.fetch!(opts, :selected_schedule_order)
    term_code = Keyword.fetch!(opts, :term_code)

    Enum.reduce(ScheduleOrder.to_list(selected_schedule_order), socket, fn owner_key, acc ->
      WeekSchedule.assign_owner(acc, owner_key: owner_key, selected_term_code: term_code)
    end)
  end

  defp normalize_target_key(nil), do: nil
  defp normalize_target_key(""), do: nil
  defp normalize_target_key(target_key), do: target_key
end
