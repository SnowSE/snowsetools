defmodule SnowSeToolsWeb.Snow.SnowJwtCopy do
  use SnowSeToolsWeb, :live_component

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:show_helper, fn -> true end)
      |> assign_new(:placeholder, fn -> "Paste JWT from my.snow.edu" end)
      |> assign_new(:js_snippet, fn -> js_snippet() end)

    {:ok, socket}
  end

  def js_snippet do
    "copy(
  JSON.parse(
    localStorage.getItem(\"oidc.user:https://kc.snow.edu/realms/snowcollege/:portal\")
  ).access_token
);
console.log(\"Auth token copied to clipboard\");"
  end

  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook=".SnowJwtCopy" class="space-y-4">
      <%= if @show_helper do %>
        <div class="space-y-2">
          <button
            type="button"
            id={"#{@id}-copy-button"}
            data-snippet={@js_snippet}
            data-snow-jwt-copy-button
            class="rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 text-xs font-semibold text-slate-200 transition hover:bg-slate-800"
          >
            Get JWT from my.snow.edu
          </button>

          <details class="text-xs text-slate-500">
            <summary class="cursor-pointer select-none hover:text-slate-300">Show JavaScript</summary>
            <pre
              phx-no-curly-interpolation
              class="mt-2 overflow-x-auto rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 leading-6 text-slate-300"
            ><code>{@js_snippet}</code></pre>
          </details>
        </div>
      <% end %>

      <label class="block space-y-2">
        <span class="block text-sm font-medium text-slate-300">{@label}</span>
        <input
          id={"#{@id}-input"}
          name={@name}
          value={@value}
          autocomplete="off"
          data-snow-jwt-copy-input
          class="w-full rounded-xl border border-slate-700 bg-slate-950/60 px-4 py-3 text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
          placeholder={@placeholder}
        />
      </label>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SnowJwtCopy">
        export default {
          mounted() {
            this.el.addEventListener("click", async (event) => {
              const button = event.target.closest("[data-snow-jwt-copy-button]")
              if (!button) return

              try {
                await navigator.clipboard.writeText(button.dataset.snippet)
              } catch (_error) {
                // Without the clipboard the snippet is still shown under "Show JavaScript".
              }

              const input = this.el.querySelector("[data-snow-jwt-copy-input]")
              if (input) {
                input.focus()
                input.select()
              }

              window.open("https://my.snow.edu", "_blank")
            })

            this.el.addEventListener("keydown", (event) => {
              if (event.key !== "Enter") return
              if (!event.target.closest("[data-snow-jwt-copy-input]")) return

              const form = this.el.closest("form")
              if (!form) return

              event.preventDefault()
              form.requestSubmit()
            })
          }
        }
      </script>
    </div>
    """
  end
end
