defmodule SnowSeToolsWeb.Components.ReportCompletionBar do
  use SnowSeToolsWeb, :html

  attr :met, :integer, required: true
  attr :not_met, :integer, required: true
  attr :partially_met, :integer, required: true
  attr :total, :integer, required: true
  attr :not_generated, :integer, default: nil
  attr :generating?, :boolean, default: false
  attr :bar_class, :string, default: "flex-1"

  def report_completion_bar(assigns) do
    assigns = assign(assigns, :run, assigns.met + assigns.not_met + assigns.partially_met)

    ~H"""
    <div class="flex items-center gap-2">
      <div class={[@bar_class, "h-1.5 bg-slate-700/60 rounded-full overflow-hidden flex"]}>
        <div
          class="h-full transition-all duration-500 bg-[#79C59B]"
          style={"width: #{safe_pct(@met, @total)}%"}
        />
        <div
          class="h-full transition-all duration-500 bg-[#7a6a3a]"
          style={"width: #{safe_pct(@partially_met, @total)}%"}
        />
        <div
          class="h-full transition-all duration-500 bg-[#3D2020]"
          style={"width: #{safe_pct(@not_met, @total)}%"}
        />
        <%= if @not_generated do %>
          <div
            class="h-full transition-all duration-500 bg-slate-600/50"
            style={"width: #{safe_pct(@not_generated, @total)}%"}
          />
        <% end %>
      </div>
      <span class="text-xs text-slate-500 shrink-0 tabular-nums flex items-center">
        <span class="inline-block text-right min-w-[3ch]">{@run}</span>/<span class="inline-block min-w-[3ch]">{@total}</span>
        <span class={[
          "hero-arrow-path size-3 inline-block ml-0.5 text-indigo-400",
          if(@generating?, do: "animate-spin", else: "invisible")
        ]} />
      </span>
    </div>
    """
  end

  defp safe_pct(_count, 0), do: 0
  defp safe_pct(count, total), do: count / total * 100
end
