defmodule SimpleSyllabusReporterWeb.Layouts do
  use SimpleSyllabusReporterWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_user, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-slate-950 text-slate-100">
      <AppHeader.header current_user={@current_user} />
      <main class="flex-1 flex flex-col min-h-0 overflow-hidden">
        {render_slot(@inner_block)}
      </main>
    </div>
    <.flash_group flash={@flash} />
    <div id="session-refresh-hook" phx-hook=".SessionRefresh" phx-update="ignore" class="hidden">
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".SessionRefresh">
      export default {
        mounted() {
          this.handleEvent("session_refresh", () => {
            fetch("/auth/refresh", { credentials: "same-origin" })
              .catch(() => { window.location.href = "/auth/login"; })
              .then(resp => {
                if (resp && !resp.ok) { window.location.href = "/auth/login"; }
              });
          });
        }
      }
    </script>
    """
  end
end
