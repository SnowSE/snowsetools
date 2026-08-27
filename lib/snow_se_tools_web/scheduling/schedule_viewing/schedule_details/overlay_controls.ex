defmodule SnowSeToolsWeb.Scheduling.OverlayControls do
  @moduledoc """
  The "Overlay with…" button and its menu. Shown on a card only when another
  card or group of the same kind is on screen; the button's color is the kind's
  color, so it is obvious which cards can combine.
  """
  use SnowSeToolsWeb, :html

  alias SnowSeToolsWeb.Scheduling.ScheduleOverlays

  @doc "Classes/style for a card wrapper given its size (`%{width: nil | px | :full}`)."
  def card_width_attrs(%{width: :full}), do: %{class: "w-full", style: nil}

  def card_width_attrs(%{width: width}) when is_integer(width),
    do: %{class: nil, style: "width: #{width}px"}

  def card_width_attrs(_size), do: %{class: "w-[700px]", style: nil}

  attr :entry_key, :string, required: true
  attr :size, :map, required: true

  @doc "Maximize / restore buttons for a card header."
  def size_button(assigns) do
    ~H"""
    <button
      :if={@size.width != nil or @size.scale != 1.0}
      type="button"
      id={"card-restore-#{:erlang.phash2(@entry_key)}"}
      phx-click="schedule-details-order:restore_size"
      phx-value-key={@entry_key}
      class="rounded p-1 text-slate-500 transition-colors hover:bg-slate-800 hover:text-slate-200"
      aria-label="Restore default size"
      title="Restore default size"
    >
      <.icon name="hero-arrows-pointing-in" class="size-4" />
    </button>
    <button
      :if={@size.width != :full}
      type="button"
      id={"card-maximize-#{:erlang.phash2(@entry_key)}"}
      phx-click="schedule-details-order:maximize"
      phx-value-key={@entry_key}
      class="rounded p-1 text-slate-500 transition-colors hover:bg-slate-800 hover:text-slate-200"
      aria-label="Maximize"
      title="Maximize"
    >
      <.icon name="hero-arrows-pointing-out" class="size-4" />
    </button>
    """
  end

  @doc "The drag grip in a card's bottom-right corner."
  def resize_grip(assigns) do
    ~H"""
    <div
      data-resize-grip
      title="Drag to resize"
      class="absolute bottom-1.5 right-1.5 z-20 flex size-5 cursor-nwse-resize items-end justify-end text-slate-600 transition-colors hover:text-indigo-300"
    >
      <svg
        viewBox="0 0 12 12"
        class="size-3"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
      >
        <path d="M11 1L1 11M11 6L6 11" />
      </svg>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :entry_key, :string, required: true
  attr :owner_type, :atom, required: true
  attr :targets, :list, required: true
  attr :open?, :boolean, default: false
  attr :label, :string, default: "Overlay with"

  def overlay_with_menu(assigns) do
    assigns = assign(assigns, :kind, ScheduleOverlays.kind_style(assigns.owner_type))

    ~H"""
    <div
      id={@id}
      class="relative"
      phx-click-away={@open? && "schedule-details-order:close_overlay_menu"}
    >
      <button
        type="button"
        id={"#{@id}-button"}
        phx-click={
          if @open?,
            do: "schedule-details-order:close_overlay_menu",
            else: "schedule-details-order:open_overlay_menu"
        }
        phx-value-key={@entry_key}
        aria-haspopup="menu"
        aria-expanded={to_string(@open?)}
        class={[
          "inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 text-xs font-medium transition-colors",
          @kind.button
        ]}
      >
        <.icon name="hero-square-2-stack" class="size-3.5" />
        {@label}
        <.icon name="hero-chevron-down" class="size-3" />
      </button>

      <div
        :if={@open?}
        id={"#{@id}-list"}
        role="menu"
        class="absolute right-0 z-50 mt-1 w-64 overflow-hidden rounded-lg border border-slate-700 bg-slate-900 text-sm shadow-xl shadow-black/40"
      >
        <div class="px-3 py-2 text-[11px] uppercase tracking-wide text-slate-500">
          Overlay with
        </div>
        <%= for target <- @targets do %>
          <button
            type="button"
            role="menuitem"
            id={"#{@id}-target-#{:erlang.phash2(target.key)}"}
            phx-click="schedule-details-order:overlay"
            phx-value-key={@entry_key}
            phx-value-target={target.key}
            class="flex w-full items-center gap-2 px-3 py-2 text-left text-slate-200 transition hover:bg-slate-800/70"
          >
            <.icon
              name={if target.group?, do: "hero-square-2-stack", else: "hero-calendar"}
              class="size-4 shrink-0 text-slate-500"
            />
            <span class="min-w-0 flex-1 truncate">{target.label}</span>
            <span :if={target.group?} class="text-xs text-slate-500">group</span>
          </button>
        <% end %>
        <div class="border-t border-slate-800 px-3 py-2 text-[11px] text-slate-600">
          Only {@kind.label} can be overlaid together.
        </div>
      </div>
    </div>
    """
  end
end
