defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusResultsList do
  use SimpleSyllabusReporterWeb, :html

  attr :syllabi, :list, required: true
  attr :syllabi_empty?, :boolean, required: true
  attr :query, :string, required: true
  attr :loading_search, :boolean, required: true
  attr :selected, :map, default: nil
  attr :total_elements, :integer, required: true
  attr :syllabi_count, :integer, required: true
  attr :report_counts, :map, required: true
  attr :generating_per_code, :map, required: true
  attr :generating_all, :boolean, required: true

  def results_list(assigns) do
    total_generated =
      assigns.report_counts
      |> Map.values()
      |> Enum.flat_map(&Map.values/1)
      |> Enum.sum()

    total_possible = assigns.syllabi_count * assigns.total_elements

    assigns =
      assign(assigns,
        total_generated: total_generated,
        total_possible: total_possible
      )

    ~H"""
    <div class={[
      "flex flex-col min-h-0 flex-1",
      @selected && "hidden sm:flex sm:w-64 sm:flex-none"
    ]}>
      <%= if not @syllabi_empty? && @total_elements > 0 && !@loading_search do %>
        <div class="mb-3 shrink-0">
          <button
            id="generate-all-btn"
            type="button"
            phx-click="generate_all_missing"
            disabled={@generating_all}
            class={[
              "w-full flex flex-col gap-1 px-4 py-2 rounded-lg text-sm font-medium border transition-all",
              if(@generating_all,
                do: "bg-slate-800/60 border-slate-700 text-slate-500 cursor-not-allowed",
                else:
                  "bg-indigo-600/10 border-indigo-500/40 text-indigo-300 hover:bg-indigo-600/20 hover:border-indigo-400 cursor-pointer"
              )
            ]}
          >
            <div class="flex items-center justify-center gap-2">
              <%= if @generating_all do %>
                <span class="hero-arrow-path size-4 animate-spin" /> Generating missing reports…
              <% else %>
                <span class="hero-sparkles size-4" /> Generate all missing reports
              <% end %>
            </div>
            <div id="report-summary" class="w-full mt-1.5 flex items-center justify-between">
              <span class="text-xs text-slate-400">
                <span class="font-semibold text-slate-200">{@total_generated}</span>
                / {@total_possible} reports generated
              </span>
              <%= if @total_generated == @total_possible && @total_possible > 0 do %>
                <span class="text-xs text-green-400 font-medium">All complete</span>
              <% end %>
            </div>
          </button>
        </div>
      <% end %>

      <div
        :if={@syllabi_empty? && @query != "" && !@loading_search}
        id="syllabi-empty"
        class="text-slate-500 text-sm italic py-4"
      >
        No syllabi found for "{@query}".
      </div>
      <div
        id="syllabi-list"
        phx-update="stream"
        class="overflow-y-auto flex-1 min-h-0 space-y-1"
      >
        <div
          :for={{id, doc} <- @syllabi}
          id={id}
          phx-click="select"
          phx-value-code={doc["code"]}
          phx-value-title={doc["title"] || doc["course_name"] || "Untitled"}
          phx-value-term={doc["term_name"] || ""}
          class={[
            "group flex flex-col gap-0.5 px-4 py-3 rounded-lg cursor-pointer border transition-all mb-2 relative",
            if(@selected && @selected["code"] == doc["code"],
              do: "bg-indigo-950/30 border-indigo-500/40 ",
              else: "bg-slate-800/60 border-slate-700 hover:bg-slate-900 hover:border-indigo-500/50"
            )
          ]}
        >
          <% selected? = @selected && @selected["code"] == doc["code"] %>

          <span class={[
            "text-sm font-medium leading-snug transition-colors",
            if(selected?, do: "text-indigo-100", else: "text-slate-100 group-hover:text-indigo-100")
          ]}>
            {doc["title"] || doc["course_name"] || "Untitled"}
          </span>
          <div class="flex flex-wrap gap-x-3 gap-y-0.5 mt-0.5">
            <span :if={doc["term_name"] || doc["term"]} class="text-xs text-slate-400">
              {doc["term_name"] || doc["term"]}
            </span>
          </div>
          <%= if @total_elements > 0 do %>
            <% counts = Map.get(@report_counts, doc["code"], %{}) %>
            <% met = Map.get(counts, "met", 0) %>
            <% not_met = Map.get(counts, "not_met", 0) %>
            <% partially_met = Map.get(counts, "partially_met", 0) %>
            <% total_run = met + not_met + partially_met %>
            <% item_generating? =
              MapSet.size(Map.get(@generating_per_code, doc["code"], MapSet.new())) > 0 %>
            <div class="flex items-center gap-2 mt-1.5">
              <div class="flex-1 h-1.5 bg-slate-700/60 rounded-full overflow-hidden flex">
                <div
                  class="h-full transition-all duration-500 bg-[#3d6b52]"
                  style={"width: #{met / @total_elements * 100}%"}
                />
                <div
                  class="h-full transition-all duration-500 bg-[#7a6a3a]"
                  style={"width: #{partially_met / @total_elements * 100}%"}
                />
                <div
                  class="h-full transition-all duration-500 bg-[#7a4040]"
                  style={"width: #{not_met / @total_elements * 100}%"}
                />
              </div>
              <span class="text-xs text-slate-500 shrink-0 tabular-nums">
                {total_run}/{@total_elements}
                <%= if item_generating? do %>
                  <span class="hero-arrow-path size-3 animate-spin inline-block ml-0.5 text-indigo-400" />
                <% end %>
              </span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
