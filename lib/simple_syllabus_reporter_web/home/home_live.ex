defmodule SimpleSyllabusReporterWeb.Home.HomeLive do
  use SimpleSyllabusReporterWeb, :live_view

  alias SimpleSyllabusReporter.ConfigDB
  alias SimpleSyllabusReporter.Reports.ReportGeneratorDomainManger
  alias SimpleSyllabusReporter.Reports.ReportGenerationStatus
  alias SimpleSyllabusReporter.Syllabi.SyllabusDomainManager

  on_mount {SimpleSyllabusReporterWeb.UserAuth, :ensure_authenticated}

  @color_positive "#71E48C9C"
  @color_negative "#7E122D"
  @color_warning "#A0904F"
  @color_neutral "#475569"
  @color_border "#21252D"
  @color_legend "#94a3b8"

  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        ReportGenerationStatus.subscribe()
        ConfigDB.subscribe()
        ReportGeneratorDomainManger.request_totals(self())
        start_async(socket, :fetch_departments, fn -> SyllabusDomainManager.get_departments() end)
      else
        socket
      end

    current_term_id = ConfigDB.get_current_term()
    terms = ConfigDB.list_available_terms()

    current_term_name =
      case Enum.find(terms, fn t -> t["term_id"] == current_term_id end) do
        nil -> "All terms"
        term -> term["term_name"]
      end

    {:ok,
     assign(socket,
       page_title: "Home",
       totals: nil,
       by_school: [],
       departments: %{},
       current_term_name: current_term_name,
       chart_colors: %{
         met: @color_positive,
         not_met: @color_negative,
         partially_met: @color_warning,
         not_generated: @color_neutral,
         border: @color_border,
         legend: @color_legend
       }
     )}
  end

  def handle_info({:totals_loaded, %{"totals" => totals, "by_school" => by_school}}, socket) do
    {:noreply,
     socket
     |> assign(:totals, totals)
     |> assign(:by_school, by_school)
     |> push_chart_event(totals)}
  end

  def handle_info(%ReportGenerationStatus.ItemResult{}, socket) do
    ReportGeneratorDomainManger.request_totals(self())
    {:noreply, socket}
  end

  def handle_async(:fetch_departments, {:ok, {:ok, departments}}, socket) do
    dept_map = Map.new(departments, fn d -> {d["entity_id"], d["name"]} end)
    {:noreply, assign(socket, :departments, dept_map)}
  end

  def handle_async(:fetch_departments, _result, socket) do
    {:noreply, socket}
  end

  def handle_info({:term_changed, term_id}, socket) do
    terms = ConfigDB.list_available_terms()

    current_term_name =
      case Enum.find(terms, fn t -> t["term_id"] == term_id end) do
        nil -> "All terms"
        term -> term["term_name"]
      end

    ReportGeneratorDomainManger.request_totals(self())
    {:noreply, assign(socket, :current_term_name, current_term_name)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp push_chart_event(socket, nil), do: socket

  defp push_chart_event(socket, totals) do
    push_event(socket, "chart_data", %{
      met: totals["met"] || 0,
      not_met: totals["not_met"] || 0,
      partially_met: totals["partially_met"] || 0,
      not_generated: totals["not_generated"] || 0,
      total_syllabi: totals["total_syllabi"] || 0
    })
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} socket={@socket} current_path={@current_path}>
      <div class="max-w-5xl mx-auto px-6 py-10 space-y-10">

        <div class="flex items-baseline justify-between">
          <span class="text-sm text-slate-400">{@current_term_name}</span>
        </div>

        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">

          <div class="bg-slate-800/50 border border-slate-700 rounded-xl p-6">
            <h2 class="text-sm font-medium text-slate-300 mb-4 text-center">Report Status</h2>
            <div id="status-chart-wrapper" phx-update="ignore">
              <canvas
                id="status-chart"
                phx-hook=".StatusChart"
                height="80"
                data-color-met={@chart_colors.met}
                data-color-not-met={@chart_colors.not_met}
                data-color-partially-met={@chart_colors.partially_met}
                data-color-not-generated={@chart_colors.not_generated}
                data-color-border={@chart_colors.border}
                data-color-legend={@chart_colors.legend}
              ></canvas>
            </div>
          </div>

        </div>

        <%= if @by_school != [] do %>
          <div class="space-y-3">
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for row <- Enum.sort_by(Enum.filter(@by_school, fn r -> Map.has_key?(@departments, r["org_id"]) end), fn r -> Map.get(@departments, r["org_id"]) end) do %>
                <.link
                  navigate={"/syllabi?q=#{URI.encode(Map.get(@departments, row["org_id"]))}" }
                  class="block bg-slate-800/50 border border-slate-700 rounded-xl p-5 space-y-3 hover:border-slate-800 hover:bg-slate-900/50 transition-colors"
                >
                  <h3 class="text-sm font-semibold text-slate-200 truncate text-center">
                    {Map.get(@departments, row["org_id"], row["org_id"])}
                  </h3>
                  <div id={"school-chart-wrap-#{row["org_id"]}"} phx-update="ignore">
                    <canvas
                      id={"school-chart-#{row["org_id"]}"}
                      phx-hook=".SchoolChart"
                      height="50"
                      data-met={row["met"]}
                      data-not-met={row["not_met"]}
                      data-partially-met={row["partially_met"]}
                      data-not-generated={row["not_generated"]}
                      data-color-met={@chart_colors.met}
                      data-color-not-met={@chart_colors.not_met}
                      data-color-partially-met={@chart_colors.partially_met}
                      data-color-not-generated={@chart_colors.not_generated}
                      data-color-border={@chart_colors.border}
                      data-color-legend={@chart_colors.legend}
                    ></canvas>
                  </div>
                  <div class="grid grid-cols-4 gap-1 text-center">
                    <div class="rounded-lg bg-green-500/10 border border-green-500/20 py-1.5">
                      <div class="text-base font-bold text-green-200">{row["met"]}</div>
                      <div class="text-xs text-green-200/60">Met</div>
                    </div>
                    <div class="rounded-lg bg-amber-500/10 border border-amber-500/20 py-1.5">
                      <div class="text-base font-bold text-amber-200">{row["partially_met"]}</div>
                      <div class="text-xs text-amber-200/60">Partial</div>
                    </div>
                    <div class="rounded-lg bg-red-500/10 border border-red-500/20 py-1.5">
                      <div class="text-base font-bold text-red-200">{row["not_met"]}</div>
                      <div class="text-xs text-red-200/60">Not Met</div>
                    </div>
                    <div class="rounded-lg bg-slate-500/10 border border-slate-500/20 py-1.5">
                      <div class="text-base font-bold text-slate-200">{row["not_generated"]}</div>
                      <div class="text-xs text-slate-200/60">Not Generated</div>
                    </div>
                  </div>
                </.link>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".StatusChart">
        import Chart from "chart.js/auto"

        export default {
          mounted() {
            const d = this.el.dataset
            this.chart = new Chart(this.el, {
              type: "doughnut",
              data: {
                labels: ["Met", "Not Met", "Partially Met", "Not Generated"],
                datasets: [{
                  data: [0, 0, 0, 0],
                  backgroundColor: [d.colorMet, d.colorNotMet, d.colorPartiallyMet, d.colorNotGenerated],
                  borderColor: d.colorBorder,
                  borderWidth: 2,
                  hoverOffset: 6,
                }]
              },
              options: {
                cutout: "50%",
                rotation: -90,
                circumference: 180,
                layout: { padding: { bottom: -40 } },
                plugins: {
                  legend: { labels: { color: d.colorLegend, font: { size: 12 } } },
                  tooltip: { callbacks: { label: ctx => ` ${ctx.formattedValue} items` } },
                },
                animation: { animateRotate: true, duration: 600 },
              }
            })
            this.handleEvent("chart_data", data => {
              this.chart.data.datasets[0].data = [data.met, data.not_met, data.partially_met, data.not_generated]
              this.chart.update()
            })
          },
          destroyed() { this.chart?.destroy() }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SchoolChart">
        import Chart from "chart.js/auto"

        export default {
          mounted() { this.chart = this.buildChart() },
          updated() {
            if (!this.chart) { this.chart = this.buildChart(); return }
            const d = this.el.dataset
            this.chart.data.datasets[0].data = [+d.met, +d.notMet, +d.partiallyMet, +d.notGenerated]
            this.chart.update()
          },
          destroyed() { this.chart?.destroy() },
          buildChart() {
            const d = this.el.dataset
            return new Chart(this.el, {
              type: "doughnut",
              data: {
                labels: ["Met", "Not Met", "Partially Met", "Not Generated"],
                datasets: [{
                  data: [+d.met, +d.notMet, +d.partiallyMet, +d.notGenerated],
                  backgroundColor: [d.colorMet, d.colorNotMet, d.colorPartiallyMet, d.colorNotGenerated],
                  borderColor: d.colorBorder,
                  borderWidth: 2,
                  hoverOffset: 4,
                }]
              },
              options: {
                cutout: "50%",
                rotation: -90,
                circumference: 180,
                layout: { padding: { bottom: -30 } },
                plugins: {
                  legend: { display: false },
                  tooltip: { callbacks: { label: ctx => ` ${ctx.formattedValue} items` } },
                },
                animation: { animateRotate: true, duration: 400 },
              }
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end
end
