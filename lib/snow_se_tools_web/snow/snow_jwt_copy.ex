defmodule SnowSeToolsWeb.Snow.SnowJwtCopy do
  use SnowSeToolsWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def js_snippet do
    "copy(
  JSON.parse(
    localStorage.getItem(\"oidc.user:https://kc.snow.edu/realms/snowcollege/:portal\")
  ).access_token
);
console.log(\"Auth token copied to clipboard\");
"
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-4">
      <div class="relative">
        <pre
          phx-no-curly-interpolation
          class="overflow-x-auto rounded-xl border border-slate-800 bg-slate-950 px-4 py-3 text-xs leading-6 text-slate-300"
        ><code><%= js_snippet() %></code></pre>
        <button
          type="button"
          id={"#{@id}-copy-button"}
          phx-hook=".SnowJwtCopy"
          phx-update="ignore"
          class="absolute right-2 top-2 rounded-xl border border-slate-700 bg-slate-900 px-3 py-1.5 text-xs font-semibold text-slate-200 shadow-lg transition hover:bg-slate-800"
        >
          Get JWT from my.snow.edu
        </button>
      </div>

      <.form
        for={to_form(%{"jwt_token" => @value}, as: :snow_jwt_copy)}
        id={"#{@id}-form"}
        phx-change="validate"
        phx-submit="validate"
        phx-target={@target}
      >
        <label class="block space-y-2">
          <span class="block text-sm font-medium text-slate-300">JWT token</span>
          <input
            name="snow_jwt_copy[jwt_token]"
            value={@value}
            autocomplete="off"
            class="w-full rounded-xl border border-slate-700 bg-slate-950/60 px-4 py-3 text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
            placeholder="Paste JWT from my.snow.edu"
          />
        </label>
      </.form>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SnowJwtCopy">
        export default {
          mounted() {
            const snippet = `copy(
              JSON.parse(
                localStorage.getItem("oidc.user:https://kc.snow.edu/realms/snowcollege/:portal")
              ).access_token
            );
            console.log("Auth token copied to clipboard");`

            this.el.addEventListener("click", async () => {
              try {
                await navigator.clipboard.writeText(snippet)
                window.open("https://my.snow.edu", "_blank")
              } catch (_error) {
                window.open("https://my.snow.edu", "_blank")
              }
            })
          }
        }
      </script>
    </div>
    """
  end
end
