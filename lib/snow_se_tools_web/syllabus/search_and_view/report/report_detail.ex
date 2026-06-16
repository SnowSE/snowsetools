defmodule SnowSeToolsWeb.Syllabus.ReportDetail do
  use SnowSeToolsWeb, :html

  alias SnowSeToolsWeb.Syllabus.ReportCorrection

  attr :selected_element_id, :string, default: nil
  attr :elements, :list, required: true
  attr :report_items, :map, required: true
  attr :generating, :any, required: true
  attr :generation_errors, :map, required: true
  attr :syllabus, :map, default: nil
  attr :class, :string, default: "flex-1 min-w-0 overflow-y-auto"
  attr :correcting_element_id, :string, default: nil

  def report_detail(assigns) do
    ~H"""
    <div class={@class}>
      <div class="mb-4 flex items-start gap-2 rounded-lg border border-blue-700/50 bg-blue-950/20 px-3 py-2.5 text-blue-100">
        <span class="hero-exclamation-triangle size-4  my-auto shrink-0" />
        <p>
          This syllabus check is unofficial, AI generated, and probably inaccurate
        </p>
      </div>
      <%= if @selected_element_id do %>
        <% element = Enum.find(@elements, fn e -> e["id"] == @selected_element_id end) %>
        <%= if element do %>
          <% item = Map.get(@report_items, element["id"]) %>
          <% generating? = MapSet.member?(@generating, element["id"]) %>
          <% error = Map.get(@generation_errors, element["id"]) %>
          <div
            id={"report-item-#{element["id"]}"}
            class="flex flex-col gap-3"
          >
            <div class="flex items-start justify-between gap-3 pb-2">
              <div class="min-w-0">
                <h2 class="text-sm font-semibold text-slate-100 leading-snug">{element["name"]}</h2>
                <%= if element["description"] && element["description"] != "" do %>
                  <p class="text-slate-500 text-xs mt-0.5 leading-snug">{element["description"]}</p>
                <% end %>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <%= if item && !is_nil(item["status"]) do %>
                  <span class={[
                    "text-xs px-2 py-0.5 rounded font-medium",
                    status_classes(item["status"])
                  ]}>
                    {status_label(item["status"])}
                  </span>
                <% end %>
                <button
                  id={"generate-btn-#{element["id"]}"}
                  type="button"
                  phx-click="generate_report"
                  phx-value-id={element["id"]}
                  disabled={generating? || is_nil(@syllabus)}
                  class={[
                    "inline-flex items-center gap-1.5 px-3 py-1 rounded-lg text-xs font-medium transition-all",
                    if(generating? || is_nil(@syllabus),
                      do: "bg-slate-800/70 text-slate-500 cursor-not-allowed",
                      else: "bg-indigo-600 hover:bg-indigo-500 text-slate-50 cursor-pointer"
                    )
                  ]}
                >
                  <%= if generating? do %>
                    <span class="hero-arrow-path size-3 animate-spin" /> Generating…
                  <% else %>
                    <%= if item do %>
                      <span class="hero-arrow-path size-3" /> Re-generate
                    <% else %>
                      <span class="hero-sparkles size-3" /> Generate
                    <% end %>
                  <% end %>
                </button>
              </div>
            </div>

            <%= if error do %>
              <div
                id={"gen-error-#{element["id"]}"}
                class="rounded-lg bg-red-900/20 px-3 py-2 text-red-300 text-xs"
              >
                <div class="flex items-center gap-1.5 font-medium mb-0.5">
                  <span class="hero-exclamation-circle size-3.5" /> Generation failed
                </div>
                {error}
              </div>
            <% end %>

            <%= if item do %>
              <div class="rounded-lg bg-slate-900/50 divide-slate-800/50">
                <div class="px-4 py-3">
                  <p class="text-[10px] font-semibold uppercase tracking-wider text-slate-500 mb-1">
                    Finding
                  </p>
                  <p class="text-slate-200 text-sm leading-relaxed">{item["description"]}</p>
                </div>

                <%= if item["evidence"] && item["evidence"] != "" do %>
                  <div class="px-4 py-3">
                    <p class="text-[10px] font-semibold uppercase tracking-wider text-slate-500 mb-1">
                      Evidence
                    </p>
                    <blockquote class="border-l-2 border-indigo-600/40 pl-3 text-slate-300 text-xs leading-relaxed italic">
                      {item["evidence"]}
                    </blockquote>
                  </div>
                <% end %>

                <%= if item["additional_considerations"] && item["additional_considerations"] != "" do %>
                  <div class="px-4 py-3">
                    <p class="text-[10px] font-semibold uppercase tracking-wider text-slate-500 mb-1">
                      Considerations
                    </p>
                    <p class="text-slate-300  leading-relaxed">
                      {item["additional_considerations"]}
                    </p>
                  </div>
                <% end %>
              </div>

              <ReportCorrection.correction_panel
                element_id={element["id"]}
                finding={item["description"]}
                evidence={item["evidence"] || ""}
                considerations={item["additional_considerations"] || ""}
                status={item["status"]}
                syllabus={@syllabus}
                open={@correcting_element_id == element["id"]}
              />
            <% end %>

            <%= if generating? && is_nil(item) do %>
              <div class="flex flex-col gap-2">
                <%= for _ <- 1..3 do %>
                  <div class="rounded-lg bg-slate-900/50 px-4 py-3 animate-pulse">
                    <div class="h-2 bg-slate-700 rounded w-20 mb-2" />
                    <div class="h-1.5 bg-slate-800 rounded w-full mb-1.5" />
                    <div class="h-1.5 bg-slate-800 rounded w-4/5" />
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  def status_label("met"), do: "Met"
  def status_label("not_met"), do: "Not Met"
  def status_label("partially_met"), do: "Partially Met"
  def status_label(_), do: nil

  def status_classes("met"), do: "bg-green-900/40 text-green-400"
  def status_classes("not_met"), do: "bg-red-900/40 text-red-400"
  def status_classes("partially_met"), do: "bg-yellow-900/30 text-yellow-400"
  def status_classes(_), do: "bg-slate-800 text-slate-500"
end
