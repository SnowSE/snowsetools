defmodule SnowSeToolsWeb.Scheduling.ScheduleLayoutsChrome do
  @moduledoc """
  The layout menu's furniture: the chip naming the layout on screen, the rows of
  the load menu, the notes and undo toast, and the save dialog.

  Everything here is a pure function of what it is handed. `ScheduleLayouts`
  holds the state and decides what to show; this decides how it looks.
  """

  use SnowSeToolsWeb, :html

  @max_name_length 80

  @scopes %{
    "local" => %{
      label: "This browser",
      short: "Browser",
      description: "Stays on this machine. Nobody else sees it.",
      dot: "bg-slate-400",
      text: "text-slate-400",
      border: "border-slate-500/60"
    },
    "user" => %{
      label: "My account",
      short: "Mine",
      description: "Follows you to any browser you sign in from.",
      dot: "bg-indigo-400",
      text: "text-indigo-300",
      border: "border-indigo-400/60"
    },
    "shared" => %{
      label: "Shared with everyone",
      short: "Shared",
      description: "Anyone with scheduling access can load it.",
      dot: "bg-teal-400",
      text: "text-teal-300",
      border: "border-teal-400/60"
    }
  }

  @scope_order ["local", "user", "shared"]

  def max_name_length, do: @max_name_length

  attr :loaded, :map, required: true
  attr :dirty?, :boolean, required: true
  attr :detached?, :boolean, required: true

  def loaded_chip(assigns) do
    assigns = assign(assigns, :scope, scope_style(assigns.loaded.scope))

    ~H"""
    <div
      id="schedule-layouts-current"
      class="inline-flex h-7 max-w-xs items-center gap-2 rounded-full border border-slate-700 bg-slate-900 pl-2 pr-3 text-xs"
      title={chip_title(@loaded, @dirty?, @detached?)}
    >
      <span class={[
        "size-2 shrink-0 rounded-full",
        @detached? && "bg-teal-400",
        !@detached? && @scope.dot
      ]} />
      <span class="truncate text-slate-200">
        {if @detached?, do: "Copy of #{@loaded.name}", else: @loaded.name}
      </span>
      <span :if={@detached?} class="shrink-0 text-teal-300">· unsaved copy</span>
      <span :if={!@detached? && @dirty?} class="shrink-0 text-amber-300">· edited</span>
      <span :if={!@dirty?} class="shrink-0 text-slate-500">· saved</span>
    </div>
    """
  end

  slot :inner_block, required: true

  def menu_header(assigns) do
    ~H"""
    <div class="px-2.5 pb-1 pt-2 text-[10px] uppercase tracking-[0.12em] text-slate-500">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :event, :string, required: true
  attr :mode, :string, default: nil
  attr :icon, :string, required: true
  attr :disabled, :boolean, default: false
  attr :danger, :boolean, default: false
  slot :inner_block, required: true

  def menu_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-mode={@mode}
      disabled={@disabled}
      class={[
        "flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-xs transition-colors",
        !@danger && "text-slate-300 enabled:hover:bg-slate-800 enabled:hover:text-slate-100",
        @danger && "text-red-300 enabled:hover:bg-red-950/60 enabled:hover:text-red-100",
        "disabled:cursor-not-allowed disabled:opacity-35"
      ]}
    >
      <.icon name={@icon} class="size-3.5 shrink-0" />
      <span class="truncate">{render_slot(@inner_block)}</span>
    </button>
    """
  end

  attr :layout, :map, required: true
  attr :current?, :boolean, default: false

  def layout_row(assigns) do
    assigns =
      assigns
      |> assign(:scope, scope_style(assigns.layout["scope"]))
      |> assign(:meta, layout_meta(assigns.layout))

    ~H"""
    <button
      type="button"
      id={"schedule-layout-#{@layout["id"]}"}
      phx-click="schedule-layouts:load"
      phx-value-id={@layout["id"]}
      class={[
        "flex w-full items-stretch gap-2.5 rounded-md border p-2 text-left transition-colors",
        @current? && "border-indigo-400/60 bg-slate-900",
        !@current? && "border-transparent hover:border-slate-700 hover:bg-slate-900"
      ]}
    >
      <span class={["w-0.5 shrink-0 rounded-full", @scope.dot]} />
      <span class="min-w-0 flex-1">
        <span class="block truncate text-xs font-medium text-slate-100">{@layout["name"]}</span>
        <span class="block truncate text-[10px] text-slate-500">{@meta}</span>
      </span>
      <span class={[
        "h-fit shrink-0 rounded-full border px-1.5 py-0.5 text-[9px] uppercase tracking-wider",
        @scope.border,
        @scope.text
      ]}>
        {@scope.short}
      </span>
    </button>
    """
  end

  attr :note, :any, required: true

  def note(assigns) do
    {level, text} = assigns.note
    assigns = assigns |> assign(:level, level) |> assign(:text, text)

    ~H"""
    <div
      id="schedule-layouts-note"
      class={[
        "flex items-start gap-2 rounded-md border px-3 py-2 text-xs",
        @level == :info && "border-slate-700 bg-slate-900/70 text-slate-300",
        @level == :warn && "border-amber-500/40 bg-amber-950/40 text-amber-200",
        @level == :error && "border-red-500/40 bg-red-950/40 text-red-200"
      ]}
    >
      <.icon
        name={if @level == :info, do: "hero-information-circle", else: "hero-exclamation-triangle"}
        class="size-4 shrink-0"
      />
      <span class="flex-1">{@text}</span>
      <button
        type="button"
        phx-click="schedule-layouts:dismiss_note"
        class="shrink-0 rounded p-0.5 opacity-70 transition-opacity hover:opacity-100"
        aria-label="Dismiss"
      >
        <.icon name="hero-x-mark" class="size-3.5" />
      </button>
    </div>
    """
  end

  attr :undo, :map, required: true

  def undo_toast(assigns) do
    ~H"""
    <div
      id="schedule-layouts-undo"
      class="fixed bottom-4 left-4 z-50 flex items-center gap-3 rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-xs text-slate-200 shadow-2xl shadow-black/60"
    >
      <span>{@undo.message}</span>
      <button
        type="button"
        phx-click="schedule-layouts:undo_load"
        class="font-semibold text-indigo-300 transition-colors hover:text-indigo-100"
      >
        Undo
      </button>
      <button
        type="button"
        phx-click="schedule-layouts:dismiss_undo"
        class="rounded p-0.5 text-slate-500 transition-colors hover:text-slate-200"
        aria-label="Dismiss"
      >
        <.icon name="hero-x-mark" class="size-3.5" />
      </button>
    </div>
    """
  end

  attr :dialog, :map, required: true
  attr :editor?, :boolean, required: true

  def save_dialog(assigns) do
    assigns =
      assigns
      |> assign(:scope_choices, scope_choices(editor?: assigns.editor?))
      |> assign(:max_name_length, @max_name_length)

    ~H"""
    <div
      id="schedule-layouts-dialog"
      class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 p-4"
      phx-window-keydown="schedule-layouts:close_dialog"
      phx-key="Escape"
    >
      <div class="w-full max-w-md rounded-xl border border-slate-700 bg-slate-900 p-4 shadow-2xl shadow-black/70">
        <h2 class="mb-3 text-sm font-semibold text-slate-100">{dialog_title(@dialog.mode)}</h2>

        <form
          id="schedule-layout-form"
          phx-change="schedule-layouts:dialog_change"
          phx-submit="schedule-layouts:save"
        >
          <div class="mb-3">
            <label
              for="schedule-layout-name"
              class="mb-1.5 block text-[10px] uppercase tracking-[0.1em] text-slate-500"
            >
              Name
            </label>
            <input
              type="text"
              id="schedule-layout-name"
              name="name"
              value={@dialog.name}
              maxlength={@max_name_length}
              autocomplete="off"
              class="w-full rounded-md border border-slate-700 bg-slate-950 px-2.5 py-1.5 text-sm text-slate-100 focus:border-indigo-400 focus:outline-none"
            />

            <p
              :if={@dialog.suggesting?}
              class="mt-1.5 flex items-center gap-1.5 text-[11px] text-slate-500"
            >
              <span class="size-2.5 animate-spin rounded-full border border-indigo-400 border-t-transparent motion-reduce:animate-none" />
              Suggesting a name… you can type over it
            </p>
            <p
              :if={!@dialog.suggesting? && @dialog.suggestions != []}
              class="mt-1.5 text-[11px] text-slate-500"
            >
              Suggested for you ·
              <button
                type="button"
                phx-click="schedule-layouts:suggest_again"
                class="text-indigo-300 underline transition-colors hover:text-indigo-100"
              >
                try another
              </button>
            </p>
            <p :if={@dialog.suggestion_failed?} class="mt-1.5 text-[11px] text-slate-500">
              Couldn't reach the naming model — this name came from what's on screen.
            </p>
          </div>

          <div
            :if={@dialog.collision}
            class="mb-3 rounded-md border border-amber-500/40 bg-amber-950/30 p-2.5"
          >
            <p class="mb-2 text-xs text-amber-200">
              A layout named “{String.trim(@dialog.name)}” is already saved there.
            </p>
            <div class="flex flex-col gap-1.5">
              <label
                :for={{value, label} <- [{"replace", "Replace it"}, {"copy", "Save a copy instead"}]}
                class="flex cursor-pointer items-center gap-2 text-xs text-slate-200"
              >
                <input
                  type="radio"
                  name="collision"
                  value={value}
                  checked={@dialog.collision.choice == value}
                  class="accent-indigo-400"
                />
                {label}
              </label>
            </div>
          </div>

          <div :if={@dialog.mode != "rename"} class="mb-4">
            <span class="mb-1.5 block text-[10px] uppercase tracking-[0.1em] text-slate-500">
              Where to save it
            </span>
            <div class="flex flex-col gap-1.5">
              <label
                :for={choice <- @scope_choices}
                class={[
                  "flex cursor-pointer items-start gap-2.5 rounded-md border p-2 transition-colors",
                  @dialog.scope == choice.scope && "border-indigo-400/70 bg-indigo-500/10",
                  @dialog.scope != choice.scope && "border-slate-800 hover:bg-slate-800/50"
                ]}
              >
                <input
                  type="radio"
                  name="scope"
                  value={choice.scope}
                  checked={@dialog.scope == choice.scope}
                  class="mt-0.5 accent-indigo-400"
                />
                <span class="min-w-0">
                  <span class="flex items-center gap-1.5 text-xs text-slate-100">
                    <span class={["size-2 rounded-full", choice.dot]} />
                    {choice.label}
                  </span>
                  <span class="mt-0.5 block text-[11px] leading-snug text-slate-500">
                    {choice.description}
                  </span>
                </span>
              </label>
            </div>
          </div>

          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="schedule-layouts:close_dialog"
              class="rounded-md border border-slate-700 px-3 py-1.5 text-xs font-medium text-slate-300 transition-colors hover:bg-slate-800 hover:text-slate-100"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={String.trim(@dialog.name) == ""}
              class="rounded-md border border-indigo-400/60 bg-indigo-500/20 px-3 py-1.5 text-xs font-medium text-indigo-100 transition-colors enabled:hover:bg-indigo-500/35 disabled:cursor-not-allowed disabled:opacity-40"
            >
              {submit_label(@dialog)}
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  def scope_style(scope), do: Map.get(@scopes, scope, @scopes["local"])

  def scope_choices(editor?: editor?) do
    @scope_order
    |> Enum.filter(&(editor? or &1 != "shared"))
    |> Enum.map(fn scope -> Map.put(@scopes[scope], :scope, scope) end)
  end

  @doc "The load menu's layouts, grouped by where they are saved."
  def scope_groups(layouts) do
    @scope_order
    |> Enum.map(fn scope ->
      @scopes[scope]
      |> Map.put(:scope, scope)
      |> Map.put(:layouts, Enum.filter(layouts, &(&1["scope"] == scope)))
    end)
    |> Enum.reject(&(&1.layouts == []))
  end

  defp layout_meta(layout) do
    [
      layout["term_code"] && "Term #{layout["term_code"]}",
      card_count_label(layout["entries"]),
      layout["scope"] == "shared" && layout["owner_email"] && "by #{layout["owner_email"]}"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  defp card_count_label(entries) when is_list(entries) do
    case length(entries) do
      1 -> "1 card"
      count -> "#{count} cards"
    end
  end

  defp card_count_label(_entries), do: nil

  defp chip_title(loaded, _dirty?, true),
    do: "Edited from the shared layout “#{loaded.name}”. Saving makes your own copy."

  defp chip_title(loaded, true, _detached?), do: "“#{loaded.name}” has unsaved changes."
  defp chip_title(loaded, _dirty?, _detached?), do: "Showing the saved layout “#{loaded.name}”."

  defp dialog_title("copy"), do: "Save as my copy"
  defp dialog_title("rename"), do: "Rename layout"
  defp dialog_title(_mode), do: "Save layout"

  defp submit_label(%{collision: %{choice: "copy"}}), do: "Save copy"
  defp submit_label(%{collision: %{choice: "replace"}}), do: "Replace"
  defp submit_label(%{mode: "rename"}), do: "Rename"
  defp submit_label(_dialog), do: "Save"
end
