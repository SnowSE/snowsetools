defmodule SnowSeToolsWeb.Syllabus.SchoolOverviewsComponent do
  use SnowSeToolsWeb, :live_component

  @color_positive "#71E48C9C"
  @color_negative "#7E122D"
  @color_warning "#A0904F"
  @color_neutral "#475569"
  @color_border "#21252D"
  @color_legend "#94a3b8"

  def update(assigns, socket) do
    previous_totals = socket.assigns[:totals]

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:chart_colors, fn -> chart_colors() end)

    socket =
      assign(
        socket,
        :school_rows,
        school_rows(
          by_school: Map.get(socket.assigns, :by_school, []),
          departments: Map.get(socket.assigns, :departments, %{})
        )
      )

    socket =
      if Map.has_key?(assigns, :totals) and previous_totals != assigns.totals do
        push_event(socket, "chart_data", chart_data(assigns.totals))
      else
        socket
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="max-w-5xl mx-auto px-6 py-10">
      <div class="space-y-10">
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

        <%= if @school_rows != [] do %>
          <div class="space-y-3">
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <%= for row <- @school_rows do %>
                <.link
                  navigate={"/syllabi?q=#{URI.encode(row.department_name)}"}
                  class="block bg-slate-800/50 border border-slate-700 rounded-xl p-5 space-y-3 hover:border-slate-800 hover:bg-slate-900/50 transition-colors"
                >
                  <h3 class="text-sm font-semibold text-slate-200 truncate text-center">
                    {row.department_name}
                  </h3>
                  <div id={"school-chart-wrap-#{row.org_id}"} phx-update="ignore">
                    <canvas
                      id={"school-chart-#{row.org_id}"}
                      phx-hook=".SchoolChart"
                      height="50"
                      data-met={row.met}
                      data-not-met={row.not_met}
                      data-partially-met={row.partially_met}
                      data-not-generated={row.not_generated}
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
                      <div class="text-base font-bold text-green-200">{row.met}</div>
                      <div class="text-xs text-green-200/60">Met</div>
                    </div>
                    <div class="rounded-lg bg-amber-500/10 border border-amber-500/20 py-1.5">
                      <div class="text-base font-bold text-amber-200">{row.partially_met}</div>
                      <div class="text-xs text-amber-200/60">Partial</div>
                    </div>
                    <div class="rounded-lg bg-red-500/10 border border-red-500/20 py-1.5">
                      <div class="text-base font-bold text-red-200">{row.not_met}</div>
                      <div class="text-xs text-red-200/60">Not Met</div>
                    </div>
                    <div class="rounded-lg bg-slate-500/10 border border-slate-500/20 py-1.5">
                      <div class="text-base font-bold text-slate-200">{row.not_generated}</div>
                      <div class="text-xs text-slate-200/60">Not Generated</div>
                    </div>
                  </div>
                </.link>
              <% end %>
            </div>
          </div>
        <% end %>

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
      </div>
    </div>
    """
  end

  defp chart_colors do
    %{
      met: @color_positive,
      not_met: @color_negative,
      partially_met: @color_warning,
      not_generated: @color_neutral,
      border: @color_border,
      legend: @color_legend
    }
  end

  defp chart_data(nil),
    do: %{met: 0, not_met: 0, partially_met: 0, not_generated: 0, total_syllabi: 0}

  defp chart_data(totals) do
    %{
      met: Map.get(totals, "met", 0),
      not_met: Map.get(totals, "not_met", 0),
      partially_met: Map.get(totals, "partially_met", 0),
      not_generated: Map.get(totals, "not_generated", 0),
      total_syllabi: Map.get(totals, "total_syllabi", 0)
    }
  end

  defp school_rows(by_school: by_school, departments: departments) do
    by_school
    |> Enum.filter(fn row -> Map.has_key?(departments, row["org_id"]) end)
    |> Enum.sort_by(fn row -> Map.get(departments, row["org_id"]) end)
    |> Enum.map(fn row ->
      department_name = Map.get(departments, row["org_id"], row["org_id"])

      %{
        org_id: row["org_id"],
        department_name: department_name,
        met: row["met"],
        not_met: row["not_met"],
        partially_met: row["partially_met"],
        not_generated: row["not_generated"]
      }
    end)
  end
end
