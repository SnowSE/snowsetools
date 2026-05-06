defmodule SimpleSyllabusReporterWeb.Syllabus.RequirementsButtonGroup do
  use SimpleSyllabusReporterWeb, :html

  attr :elements, :list, required: true
  attr :report_items, :map, required: true
  attr :generating, :any, required: true
  attr :selected_element_id, :string, default: nil
  attr :loading, :boolean, default: false

  def requirements_button_group(assigns) do
    ~H"""
    <div class="flex gap-1 flex-wrap shrink-0 pb-1">
      <%= if @loading do %>
        <div id="req-loading" class="text-slate-500 text-xs py-1 px-2">
          <span class="hero-arrow-path size-3 animate-spin inline-block" />
        </div>
      <% else %>
        <%= for element <- @elements do %>
          <% item = Map.get(@report_items, element["id"]) %>
          <% generating? = MapSet.member?(@generating, element["id"]) %>
          <% selected? = @selected_element_id == element["id"] %>
          <button
            id={"req-btn-#{element["id"]}"}
            type="button"
            phx-click="select_element"
            phx-value-id={element["id"]}
            class={[
              "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium whitespace-nowrap transition-all cursor-pointer shrink-0",
              if(selected?,
                do: "ring-1 ring-inset ring-indigo-500/40 " <> selected_bg(item),
                else: unselected_bg(item)
              )
            ]}
          >
            {element["name"]}
            <%= if generating? do %>
              <span class="hero-arrow-path size-2.5 animate-spin text-indigo-400" />
            <% else %>
              <%= if item && !is_nil(item["status"]) do %>
                <span class={[
                  "text-[9px] px-1 py-0.5 rounded leading-none font-semibold",
                  badge_classes(item["status"])
                ]}>
                  {status_label(item["status"])}
                </span>
              <% end %>
            <% end %>
          </button>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp status_label("met"), do: "Met"
  defp status_label("not_met"), do: "Not Met"
  defp status_label("partially_met"), do: "Partial"
  defp status_label(_), do: nil

  defp badge_classes("met"), do: "bg-green-900/50 text-green-400"
  defp badge_classes("not_met"), do: "bg-red-900/50 text-red-400"
  defp badge_classes("partially_met"), do: "bg-yellow-900/40 text-yellow-400"
  defp badge_classes(_), do: "bg-slate-800 text-slate-500"

  # Subtle tinted background when selected — blends status colour with indigo selection
  defp selected_bg(%{"status" => "met"}), do: "bg-green-900/20 text-green-200/70"
  defp selected_bg(%{"status" => "not_met"}), do: "bg-red-900/20 text-red-200/70"
  defp selected_bg(%{"status" => "partially_met"}), do: "bg-yellow-900/15 text-yellow-200/70"
  defp selected_bg(_), do: "bg-indigo-600/20 text-indigo-200"

  defp unselected_bg(%{"status" => "met"}),
    do: "bg-green-900/10 hover:bg-green-900/20 text-green-200/70 hover:text-green-200/70"

  defp unselected_bg(%{"status" => "not_met"}),
    do: "bg-red-900/10 hover:bg-red-900/20 text-red-200/70 hover:text-red-200/70"

  defp unselected_bg(%{"status" => "partially_met"}),
    do: "bg-yellow-900/10 hover:bg-yellow-900/15 text-yellow-200/70 hover:text-yellow-200/70"

  defp unselected_bg(_),
    do: "bg-slate-800/50 hover:bg-slate-800/80 text-slate-400 hover:text-slate-200"
end
