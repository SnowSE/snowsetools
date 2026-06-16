defmodule SnowSeToolsWeb.FlashComponents do
  use Phoenix.Component
  use Gettext, backend: SnowSeToolsWeb.Gettext

  alias Phoenix.LiveView.JS

  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Renders flash notices.

  Info flashes dismiss when clicking anywhere on them. Error flashes only
  dismiss when the user explicitly clicks the × button.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={@kind == :info && JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={["fixed top-4 right-4 z-50", @kind == :info && "cursor-pointer"]}
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 w-80 sm:w-96 rounded-lg px-4 py-3 shadow-xl border",
        @kind == :info && "bg-slate-800/90 border-slate-600/50 text-slate-200",
        @kind == :error && "bg-red-950/90 border-red-800/40 text-red-200"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="size-5 shrink-0 mt-0.5 text-slate-400"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="size-5 shrink-0 mt-0.5 text-red-400"
        />
        <div class="flex-1 min-w-0">
          <p :if={@title} class="font-semibold text-sm mb-0.5">{@title}</p>
          <p class="text-sm leading-snug">{msg}</p>
        </div>
        <button
          type="button"
          phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
          class="shrink-0 cursor-pointer opacity-40 hover:opacity-70 transition-opacity"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
