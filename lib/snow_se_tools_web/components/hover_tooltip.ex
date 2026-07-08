defmodule SnowSeToolsWeb.Components.HoverTooltip do
  use SnowSeToolsWeb, :html

  @doc """
  A rich hover tooltip. Wrap any element in `<.hover_tooltip>` and pass a
  `label` slot to render the tooltip content on hover.

  ## Usage

      <.hover_tooltip>
        <:label>
          <div>Always visible</div>
        </:label>
        <:body>
          <div class="text-sm font-medium">Appears on hover</div>
        </:body>
      </.hover_tooltip>
  """

  slot :label, required: true
  slot :body, required: true
  attr :id, :string, required: true
  attr :class, :string, default: nil

  def hover_tooltip(assigns) do
    ~H"""
    <div
      id={@id}
      class={["group/tooltip relative inline-flex max-w-full", @class]}
      phx-hook=".HoverTooltip"
    >
      <div data-tooltip-trigger class="inline-flex w-full">
        {render_slot(@label)}
      </div>
      <template data-tooltip-template>
        <div
          role="tooltip"
          class="pointer-events-none fixed left-0 top-0 z-9999 w-max max-w-64 rounded-lg border border-slate-700/80 bg-slate-950 px-3 py-2.5 text-left text-slate-100 shadow-xl shadow-slate-950/50 opacity-0 transition-[opacity,transform] duration-150 will-change-transform"
          style="transform: translateY(-4px);"
        >
          {render_slot(@body)}
        </div>
      </template>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".HoverTooltip">
      export default {
        mounted() {
          this.margin = Number.parseInt(this.el.dataset.tooltipMargin || "8", 10);
          this.trigger = this.el.querySelector("[data-tooltip-trigger]");
          this.template = this.el.querySelector("[data-tooltip-template]");
          this.tooltip = null;
          this.visible = false;
          this.removeTimer = null;

          if (!this.trigger || !this.template) {
            return;
          }

          this.show = this.show.bind(this);
          this.hide = this.hide.bind(this);
          this.position = this.position.bind(this);
          this.sync = this.sync.bind(this);

          this.trigger.addEventListener("mouseenter", this.show);
          this.trigger.addEventListener("focusin", this.show);
          this.trigger.addEventListener("mouseleave", this.hide);
          this.trigger.addEventListener("focusout", this.hide);
        },

        updated() {
          if (this.visible) {
            this.sync();
          }
        },

        destroyed() {
          this.trigger?.removeEventListener("mouseenter", this.show);
          this.trigger?.removeEventListener("focusin", this.show);
          this.trigger?.removeEventListener("mouseleave", this.hide);
          this.trigger?.removeEventListener("focusout", this.hide);
          window.clearTimeout(this.removeTimer);
          this.removeTooltip();
        },

        show() {
          window.clearTimeout(this.removeTimer);

          if (!this.tooltip) {
            this.mountTooltip();
          }

          this.visible = true;
          this.position();
          this.tooltip.style.opacity = "1";
          this.tooltip.style.transform = "translateY(0px)";
        },

        hide() {
          this.visible = false;

          if (!this.tooltip) {
            return;
          }

          this.tooltip.style.opacity = "0";
          this.tooltip.style.transform = "translateY(-4px)";
          this.removeTimer = window.setTimeout(() => this.removeTooltip(), 180);
        },

        sync() {
          if (!this.tooltip) {
            return;
          }

          const nextTooltip = this.template.content.firstElementChild.cloneNode(true);
          nextTooltip.style.opacity = this.tooltip.style.opacity;
          nextTooltip.style.transform = this.tooltip.style.transform;
          this.tooltip.replaceWith(nextTooltip);
          this.tooltip = nextTooltip;
          this.position();
        },

        mountTooltip() {
          const nextTooltip = this.template.content.firstElementChild.cloneNode(true);
          nextTooltip.style.opacity = "0";
          nextTooltip.style.transform = "translateY(-4px)";
          document.body.appendChild(nextTooltip);
          this.tooltip = nextTooltip;
        },

        removeTooltip() {
          if (this.tooltip) {
            this.tooltip.remove();
            this.tooltip = null;
          }
        },

        position() {
          if (!this.tooltip || !this.visible || !this.trigger) {
            return;
          }

          const triggerRect = this.trigger.getBoundingClientRect();
          const tooltipRect = this.tooltip.getBoundingClientRect();
          const margin = Number.isFinite(this.margin) ? this.margin : 8;
          const viewportWidth = window.innerWidth;
          const viewportHeight = window.innerHeight;
          const spaceAbove = triggerRect.top - margin;
          const spaceBelow = viewportHeight - triggerRect.bottom - margin;
          const fitsAbove = tooltipRect.height <= spaceAbove;
          const fitsBelow = tooltipRect.height <= spaceBelow;
          const placeAbove = fitsAbove || !fitsBelow;

          let top = placeAbove
            ? triggerRect.top - tooltipRect.height - margin
            : triggerRect.bottom + margin;

          if (top < margin) {
            top = margin;
          }

          if (top + tooltipRect.height > viewportHeight - margin) {
            top = Math.max(margin, viewportHeight - tooltipRect.height - margin);
          }

          let left = triggerRect.left + triggerRect.width / 2 - tooltipRect.width / 2;
          left = Math.max(margin, Math.min(left, viewportWidth - tooltipRect.width - margin));

          this.tooltip.style.top = `${Math.round(top)}px`;
          this.tooltip.style.left = `${Math.round(left)}px`;
        },
      };
    </script>
    """
  end
end
