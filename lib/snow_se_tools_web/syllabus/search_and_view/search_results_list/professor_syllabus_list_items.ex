defmodule SnowSeToolsWeb.Syllabus.ProfessorSyllabusListItems do
  use SnowSeToolsWeb, :html

  import SnowSeToolsWeb.Components.ReportCompletionBar

  attr :professor, :string, required: true
  attr :syllabi, :list, required: true
  attr :selected, :map, default: nil
  attr :total_elements, :integer, required: true
  attr :report_counts, :map, required: true
  attr :generating_per_code, :map, required: true
  attr :generating_all, :boolean, default: false
  attr :target, :any, default: nil

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
        syllabus_codes:
          Jason.encode!(
            assigns.syllabi
            |> Enum.reject(&unpublished_doc?/1)
            |> Enum.map(& &1["code"])
          )
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
          <div class="shrink-0">
            <.report_completion_bar
              met={@total_met}
              not_met={@total_not_met}
              partially_met={@total_partial}
              total={@total_possible}
              generating?={@any_generating?}
              bar_class="w-16"
            />
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
              phx-target={@target}
              class={[
                "ml-auto inline-flex items-center gap-1 px-2.5 py-1 rounded-lg self-end",
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
            <.syllabus_item
              doc={doc}
              professor={@professor}
              selected={@selected}
              total_elements={@total_elements}
              report_counts={@report_counts}
              generating_per_code={@generating_per_code}
              target={@target}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :doc, :map, required: true
  attr :professor, :string, required: true
  attr :selected, :map, default: nil
  attr :total_elements, :integer, required: true
  attr :report_counts, :map, required: true
  attr :generating_per_code, :map, required: true
  attr :target, :any, default: nil

  defp syllabus_item(assigns) do
    selected? = assigns.selected && assigns.selected["code"] == assigns.doc["code"]
    assigns = assign(assigns, selected?: selected?, unpublished?: unpublished_doc?(assigns.doc))

    ~H"""
    <% counts = Map.get(@report_counts, @doc["code"], %{}) %>
    <% met = Map.get(counts, "met", 0) %>
    <% not_met = Map.get(counts, "not_met", 0) %>
    <% partially_met = Map.get(counts, "partially_met", 0) %>
    <% total_run = met + not_met + partially_met %>
    <% item_generating? =
      MapSet.size(Map.get(@generating_per_code, @doc["code"], MapSet.new())) > 0 %>
    <div
      id={"syllabus-#{@doc["code"]}-#{professor_slug(@professor)}"}
      phx-click="select"
      phx-value-code={@doc["code"]}
      phx-value-title={@doc["title"] || @doc["course_name"] || "Untitled"}
      phx-value-term={@doc["term_name"] || ""}
      phx-value-source={@doc["source"]}
      phx-value-term_code={get_in(@doc, ["snow_course", "term_code"])}
      phx-value-crn={get_in(@doc, ["snow_course", "crn"])}
      phx-value-subject_code={get_in(@doc, ["snow_course", "subject_code"])}
      phx-value-course_number={get_in(@doc, ["snow_course", "course_number"])}
      phx-value-section_number={get_in(@doc, ["snow_course", "section_number"])}
      phx-value-course_name={get_in(@doc, ["snow_course", "course_name"])}
      phx-value-primary_instructor_name={get_in(@doc, ["snow_course", "primary_instructor_name"])}
      phx-target={@target}
      class={[
        "group flex flex-col gap-0.5 p-2 rounded-lg cursor-pointer border transition-all relative",
        if(@selected?,
          do: "bg-indigo-950/40 border-indigo-500/40",
          else: "bg-slate-800/40 border-slate-800 hover:bg-slate-900 hover:border-indigo-500/50"
        )
      ]}
    >
      <span class={[
        "text-sm font-medium leading-snug transition-colors",
        if(@selected?, do: "text-indigo-100", else: "text-slate-100 group-hover:text-indigo-100")
      ]}>
        {@doc["title"] || @doc["course_name"] || "Untitled"}
      </span>
      <div class="flex flex-wrap gap-x-3 gap-y-0.5">
        <span :if={@doc["term_name"] || @doc["term"]} class="text-xs text-slate-400">
          {@doc["term_name"] || @doc["term"]}
        </span>
        <span
          :if={@unpublished?}
          class="inline-flex items-center gap-1 rounded bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-amber-200"
        >
          Not published
        </span>
      </div>
      <%= if @total_elements > 0 && !@unpublished? do %>
        <.report_completion_bar
          met={met}
          not_met={not_met}
          partially_met={partially_met}
          total={@total_elements}
          generating?={item_generating?}
        />
        <%= if total_run == @total_elements && (not_met + partially_met > 0) && !item_generating? do %>
          <button
            id={"regen-non-met-#{@doc["code"]}-#{professor_slug(@professor)}"}
            type="button"
            phx-click="regenerate_non_met"
            phx-value-code={@doc["code"]}
            phx-target={@target}
            class={[
              "mt-1 self-end inline-flex items-center gap-1 px-2 py-0.5 rounded-md",
              "text-xs font-medium text-amber-200 bg-amber-950/30 border border-amber-700/10",
              "hover:text-amber-300 hover:bg-amber-950/50 active:bg-amber-950/70",
              "transition-all duration-150"
            ]}
            title="Re-generate non-met and partially met reports"
          >
            <span class="hero-arrow-path size-3" /> Re-run non-met
          </button>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp professor_totals(syllabi, report_counts, generating_per_code, total_elements) do
    Enum.reduce(syllabi, {0, 0, 0, 0, 0, false}, fn doc,
                                                    {met, partial, not_met, run, possible, gen?} ->
      if unpublished_doc?(doc) do
        {met, partial, not_met, run, possible, gen?}
      else
        counts = Map.get(report_counts, doc["code"], %{})
        doc_met = Map.get(counts, "met", 0)
        doc_partial = Map.get(counts, "partially_met", 0)
        doc_not_met = Map.get(counts, "not_met", 0)
        doc_run = doc_met + doc_partial + doc_not_met
        doc_gen? = MapSet.size(Map.get(generating_per_code, doc["code"], MapSet.new())) > 0

        {met + doc_met, partial + doc_partial, not_met + doc_not_met, run + doc_run,
         possible + total_elements, gen? || doc_gen?}
      end
    end)
  end

  defp professor_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp unpublished_doc?(doc), do: doc["source"] == "snow_courses"
end
