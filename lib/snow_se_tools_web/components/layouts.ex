defmodule SnowSeToolsWeb.Layouts do
  use SnowSeToolsWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_user, :map, default: nil
  attr :current_path, :string, default: nil
  attr :socket, :any, default: nil
  slot :inner_block, required: true
  slot :modal, doc: "optional modal content rendered above the page content"

  def app(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-slate-950 text-slate-100">
      <AppHeader.header current_user={@current_user} current_path={assigns[:current_path]}>
        <:center :if={@socket}>
          {live_render(@socket, SnowSeToolsWeb.AI.QueueStatusLive, id: "queue-status")}
        </:center>
      </AppHeader.header>
      <main class="flex-1 overflow-y-auto">
        {render_slot(@inner_block)}
      </main>
    </div>
    <.flash_group flash={@flash} />
    <div id="modal-root" class="relative z-50">
      <%= for modal <- @modal do %>
        {render_slot(modal)}
      <% end %>
    </div>
    <div id="session-refresh-hook" phx-hook=".SessionRefresh" phx-update="ignore" class="hidden">
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SessionRefresh">
      export default {
        mounted() {
          this.refreshing = false;
          this.handleEvent("session_refresh", () => {
            if (this.refreshing) {
              console.log("[SessionRefresh] Refresh already in progress, skipping duplicate trigger");
              return;
            }
            this.refreshing = true;
            console.log("[SessionRefresh] Timer fired, calling /auth/refresh");
            fetch("/auth/refresh", { credentials: "same-origin" })
              .then(resp => {
                if (!resp.ok) {
                  console.error("[SessionRefresh] Refresh failed, status=", resp.status, "- redirecting to login");
                  window.location.href = "/auth/login";
                  return;
                }
                console.log("[SessionRefresh] Refresh HTTP 200, reading new exp");
                return resp.json();
              })
              .then(data => {
                if (data && data.exp) {
                  console.log("[SessionRefresh] Got new exp=", data.exp, "- notifying server");
                  this.pushEvent("session_refreshed", { exp: data.exp });
                } else {
                  console.warn("[SessionRefresh] No exp in response, cannot reschedule");
                }
              })
              .catch(err => {
                console.error("[SessionRefresh] Fetch error:", err, "- redirecting to login");
                window.location.href = "/auth/login";
              })
              .finally(() => {
                this.refreshing = false;
              });
          });
        }
      }
    </script>
    """
  end
end
