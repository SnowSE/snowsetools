defmodule SimpleSyllabusReporterWeb.Syllabus.ProfessorSyllabusListItems do
  use SimpleSyllabusReporterWeb, :html

  attr :professor, :string, required: true
  attr :syllabi, :list, required: true
  attr :selected, :map, default: nil
  attr :total_elements, :integer, required: true
  attr :report_counts, :map, required: true
  attr :generating_per_code, :map, required: true
  attr :generating_all, :boolean, default: false

  def professor_syllabi_items(assigns) do
    prof_slug = professor_slug(assigns.professor)
    header_id = "prof-header-#{prof_slug}"
    list_id = "prof-list-#{prof_slug}"
    chevron_id = "prof-chevron-#{prof_slug}"

    {total_met, total_partial, total_not_met, total_run, total_possible, any_generating?} =
      professor_totals(
        assigns.syllabi,
        assigns.report_counts,
        assigns.generating_per_code,
        assigns.total_elements
      )

    assigns =
      assign(assigns,
        header_id: header_id,
        list_id: list_id,
        chevron_id: chevron_id,
        prof_slug: prof_slug,
        total_met: total_met,
        total_partial: total_partial,
        total_not_met: total_not_met,
        total_run: total_run,
        total_possible: total_possible,
        any_generating?: any_generating?,
        has_missing?: total_run < total_possible,
        syllabus_codes: Jason.encode!(Enum.map(assigns.syllabi, & &1["code"]))
      )

    ~H"""
    <div class="flex flex-col">
      <div
        id={@header_id}
        data-prof-slug={@prof_slug}
        class="flex items-center gap-2 px-1 pt-3 pb-1 w-full text-left group/prof cursor-pointer"
      >
        <span
          id={@chevron_id}
          class="hero-chevron-right size-3 text-slate-600 transition-transform shrink-0"
        />
        <span class="text-[10px] font-bold uppercase tracking-widest text-slate-500 group-hover/prof:text-slate-400 flex-1 select-none truncate">
          {@professor}
        </span>
        <%= if @total_elements > 0 && @total_possible > 0 do %>
          <div class="flex items-center gap-1.5 shrink-0">
            <%= if @any_generating? do %>
              <span class="hero-arrow-path size-2.5 animate-spin inline-block ml-0.5 text-indigo-400" />
            <% end %>
            <span class="text-[10px] text-slate-600 tabular-nums text-end">
              {@total_run}/{@total_possible}
            </span>
            <div class="w-16 h-1 bg-slate-700/60 rounded-full overflow-hidden flex">
              <div
                class="h-full transition-all duration-500 bg-[#3d6b52]"
                style={"width: #{@total_met / @total_possible * 100}%"}
              />
              <div
                class="h-full transition-all duration-500 bg-[#7a6a3a]"
                style={"width: #{@total_partial / @total_possible * 100}%"}
              />
              <div
                class="h-full transition-all duration-500 bg-[#7a4040]"
                style={"width: #{@total_not_met / @total_possible * 100}%"}
              />
            </div>
          </div>
        <% end %>
      </div>

      <div id={@list_id} class="hidden">
        <div class="flex flex-col gap-2 pb-0.5 pe-2 ps-4 py-1">
          <%= if @has_missing? && !@any_generating? && !@generating_all do %>
            <button
              id={"gen-prof-#{@prof_slug}"}
              type="button"
              phx-click="generate_missing_for_professor"
              phx-value-codes={@syllabus_codes}
              class={["ml-auto inline-flex items-center gap-1 px-2.5 py-1 rounded-lg self-end",
                     "text-xs font-medium text-indigo-400 bg-indigo-950/30",
                     "hover:text-indigo-300 hover:bg-indigo-950/50 active:bg-indigo-950/70",
                     "transition-all duration-150"
              ]}
              title={"Generate missing reports for #{@professor}"}
            >
              <span class="hero-play size-3" /> Generate missing
            </button>
          <% end %>
          <%= for doc <- Enum.sort_by(@syllabi, &(&1["title"] || &1["course_name"] || "")) do %>
            <% selected? = @selected && @selected["code"] == doc["code"] %>
            <div
              id={"syllabus-#{doc["code"]}-#{professor_slug(@professor)}"}
              phx-click="select"
              phx-value-code={doc["code"]}
              phx-value-title={doc["title"] || doc["course_name"] || "Untitled"}
              phx-value-term={doc["term_name"] || ""}
              class={[
                "group flex flex-col gap-0.5 p-2 rounded-lg cursor-pointer border transition-all relative",
                if(selected?,
                  do: "bg-indigo-950/30 border-indigo-500/40",
                  else:
                    "bg-slate-800/60 border-slate-700 hover:bg-slate-900 hover:border-indigo-500/50"
                )
              ]}
            >
              <span class={[
                "text-sm font-medium leading-snug transition-colors",
                if(selected?,
                  do: "text-indigo-100",
                  else: "text-slate-100 group-hover:text-indigo-100"
                )
              ]}>
                {doc["title"] || doc["course_name"] || "Untitled"}
              </span>
              <div class="flex flex-wrap gap-x-3 gap-y-0.5 ">
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
                <div class="flex items-center gap-2 ">
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
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp professor_totals(syllabi, report_counts, generating_per_code, total_elements) do
    Enum.reduce(syllabi, {0, 0, 0, 0, 0, false}, fn doc,
                                                    {met, partial, not_met, run, possible, gen?} ->
      counts = Map.get(report_counts, doc["code"], %{})
      doc_met = Map.get(counts, "met", 0)
      doc_partial = Map.get(counts, "partially_met", 0)
      doc_not_met = Map.get(counts, "not_met", 0)
      doc_run = doc_met + doc_partial + doc_not_met
      doc_gen? = MapSet.size(Map.get(generating_per_code, doc["code"], MapSet.new())) > 0

      {met + doc_met, partial + doc_partial, not_met + doc_not_met, run + doc_run,
       possible + total_elements, gen? || doc_gen?}
    end)
  end

  defp professor_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
