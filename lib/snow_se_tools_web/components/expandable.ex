defmodule SnowSeToolsWeb.Components.Expandable do
  use SnowSeToolsWeb, :html

  attr :id, :string, required: true
  attr :class, :string, default: nil
  slot :title_row, required: true
  slot :body, required: true

  def expandable(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".Expandable"
      class={["group   bg-slate-950/35", @class]}
    >
      <div
        data-expandable-trigger
        class={[
          "flex cursor-pointer list-none items-center gap-3 px-3 py-2 text-left transition hover:bg-slate-900/50",
          "select-none rounded-lg"
        ]}
        role="button"
        tabindex="0"
        aria-expanded="false"
      >
        <div class="min-w-0 flex-1">
          {render_slot(@title_row)}
        </div>

        <span data-expandable-chevron class="shrink-0 transition-transform duration-300">
          <.icon
            name="hero-chevron-down"
            class="size-4 text-slate-500"
          />
        </span>
      </div>

      <div
        data-expandable-body
        class="overflow-hidden px-3 transition-[height] duration-300 ease-out"
        style="height: 0px; transition: height 300ms ease-out;"
      >
        <div>
          {render_slot(@body)}
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Expandable">
        export default {
          mounted() {
            this.open = false;
            this.trigger = this.el.querySelector("[data-expandable-trigger]");
            this.body = this.el.querySelector("[data-expandable-body]");
            this.chevron = this.el.querySelector("[data-expandable-chevron]");

            if (!this.trigger || !this.body) {
              return;
            }

            this.body.style.height = "0px";
            this.trigger.addEventListener("click", () => this.toggle());
            this.trigger.addEventListener("keydown", (event) => {
              if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                this.toggle();
              }
            });
            this.body.addEventListener("transitionend", () => this.finishTransition());
          },

          updated() {
            if (!this.body || !this.trigger) {
              return;
            }

            this.syncClasses();
            this.body.style.height = this.open ? "auto" : "0px";
          },

          toggle() {
            if (!this.body || !this.trigger) {
              return;
            }

            this.open = !this.open;
            this.syncClasses();

            if (this.open) {
              this.expand();
            } else {
              this.collapse();
            }
          },

          expand() {
            this.body.style.height = "0px";
            requestAnimationFrame(() => {
              this.body.style.height = `${this.body.scrollHeight}px`;
            });
          },

          collapse() {
            this.body.style.height = `${this.body.getBoundingClientRect().height}px`;
            this.body.offsetHeight;
            requestAnimationFrame(() => {
              this.body.style.height = "0px";
            });
          },

          syncClasses() {
            this.trigger.setAttribute("aria-expanded", String(this.open));
            this.el.classList.toggle("is-open", this.open);
            this.trigger.classList.toggle("bg-slate-900/50", this.open);

            if (this.chevron) {
              this.chevron.classList.toggle("rotate-180", this.open);
            }
          },

          finishTransition() {
            if (!this.body) {
              return;
            }

            if (this.open) {
              this.body.style.height = "auto";
            }
          },
        };
      </script>
    </div>
    """
  end
end
