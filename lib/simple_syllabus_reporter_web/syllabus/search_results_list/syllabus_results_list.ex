defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusSearchResultsList do
  use SimpleSyllabusReporterWeb, :html

  import SimpleSyllabusReporterWeb.Syllabus.ProfessorSyllabusListItems

  attr :syllabi_docs, :map, required: true
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
        total_possible: total_possible,
        professors_grouped: group_by_professor(assigns.syllabi_docs)
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

      <div id="syllabi-list" phx-hook=".ProfessorExpansion" class="overflow-y-auto flex-1 min-h-0">
        <%= for {professor, syllabi} <- @professors_grouped do %>
          <.professor_syllabi_items
            professor={professor}
            syllabi={syllabi}
            selected={@selected}
            total_elements={@total_elements}
            report_counts={@report_counts}
            generating_per_code={@generating_per_code}
          />
        <% end %>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ProfessorExpansion">
      const STORAGE_KEY = "professor_expanded";

      function getExpanded() {
        try { return new Set(JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]")); }
        catch { return new Set(); }
      }

      function saveExpanded(expanded) {
        localStorage.setItem(STORAGE_KEY, JSON.stringify([...expanded]));
      }

      export default {
        mounted() {
          this.applyExpanded();
          this.el.addEventListener("click", e => {
            const btn = e.target.closest("[data-prof-slug]");
            if (!btn) return;
            const slug = btn.dataset.profSlug;
            const expanded = getExpanded();
            if (expanded.has(slug)) expanded.delete(slug);
            else expanded.add(slug);
            saveExpanded(expanded);
            this.applyExpanded();
          });
        },
        updated() { this.applyExpanded(); },
        applyExpanded() {
          const expanded = getExpanded();
          this.el.querySelectorAll("[data-prof-slug]").forEach(btn => {
            const slug = btn.dataset.profSlug;
            const listEl = document.getElementById(`prof-list-${slug}`);
            const chevronEl = document.getElementById(`prof-chevron-${slug}`);
            if (!listEl || !chevronEl) return;
            const isExpanded = expanded.has(slug);
            listEl.classList.toggle("hidden", !isExpanded);
            chevronEl.classList.toggle("rotate-90", isExpanded);
          });
        }
      };
    </script>
    """
  end

  defp group_by_professor(syllabi_docs) do
    hidden_professors = [
      "Chris Pinedo",
      "Engineering ADA"
    ]

    syllabi_docs
    |> Map.values()
    |> Enum.flat_map(fn doc ->
      case doc["editors"] || [] do
        [] -> [{"Unknown", doc}]
        editors -> Enum.map(editors, fn e -> {e["full_name"] || "Unknown", doc} end)
      end
    end)
    |> Enum.reject(fn {name, _} ->
      String.downcase(name) in Enum.map(hidden_professors, &String.downcase/1)
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, doc} -> doc end)
    |> Enum.sort_by(fn {name, _} ->
      if name == "Unknown", do: "zzz", else: String.downcase(name)
    end)
  end
end
