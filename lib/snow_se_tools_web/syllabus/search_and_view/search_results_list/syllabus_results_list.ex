defmodule SnowSeToolsWeb.Syllabus.SyllabusSearchResultsList do
  use SnowSeToolsWeb, :live_component

  import SnowSeToolsWeb.Syllabus.ProfessorSyllabusListItems

  alias SnowSeTools.Syllabi.SyllabusDomainManager
  alias SnowSeTools.Reports.ReportGeneratorDomainManger
  alias SnowSeTools.Reports.ReportGenerationStatus
  alias SnowSeTools.Reports.ReportGeneratorDomainManger

  # ----- mount -----

  def mount(socket) do
    socket =
      if connected?(socket) do
        start_async(socket, :fetch_departments, fn -> SyllabusDomainManager.get_departments() end)
      else
        socket
      end

    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:selected_term_id, nil)
     |> assign(:selected_term_name, "All terms")
     |> assign(:departments, [])
     |> assign(:selected, nil)
     |> assign(:elements, [])
     |> assign(:total_elements, 0)
     |> assign(:loading_search, false)
     |> assign(:search_error, nil)
     |> assign(:search_cached_at, nil)
     |> assign(:syllabi_empty?, true)
     |> assign(:syllabi_docs, %{})
     |> assign(:report_counts, %{})
     |> assign(:generating_per_code, %{})
     |> assign(:generating_all, false)
     |> assign(:search_pending?, false)
     |> assign(:code_to_slug, %{})
     |> assign(:professors_meta, %{})
     |> stream(:professor_groups, [])}
  end

  # ----- update/2 -----

  # Forwarded from parent: generation pending update
  def update(%{pending_update: pending}, socket) do
    syllabi_codes = socket.assigns.syllabi_docs |> Map.keys() |> MapSet.new()

    generating_per_code =
      Enum.reduce(pending, %{}, fn {code, element_id}, acc ->
        if MapSet.member?(syllabi_codes, code) do
          Map.update(acc, code, MapSet.new([element_id]), &MapSet.put(&1, element_id))
        else
          acc
        end
      end)

    prev_generating_codes = Map.keys(socket.assigns.generating_per_code)
    all_affected = Enum.uniq(Map.keys(generating_per_code) ++ prev_generating_codes)

    {:ok,
     socket
     |> assign(:generating_per_code, generating_per_code)
     |> assign(:generating_all, map_size(generating_per_code) > 0)
     |> restream_professors_for_codes(all_affected)}
  end

  # Forwarded from parent: incremental counts update from a single ItemResult
  def update(%{report_counts_update: {code, old_status, new_status}}, socket) do
    report_counts =
      Map.update(
        socket.assigns.report_counts,
        code,
        %{new_status => 1},
        fn counts ->
          counts
          |> then(fn c ->
            if old_status, do: Map.update(c, old_status, 0, &max(0, &1 - 1)), else: c
          end)
          |> Map.update(new_status, 1, &(&1 + 1))
        end
      )

    {:ok,
     socket
     |> assign(:report_counts, report_counts)
     |> restream_professors_for_codes([code])}
  end

  # Forwarded from parent: batch counts loaded after search
  def update(%{report_counts_loaded: {:ok, counts}}, socket) do
    codes = Map.keys(counts)

    {:ok,
     socket
     |> assign(:report_counts, Map.merge(socket.assigns.report_counts, counts))
     |> restream_professors_for_codes(codes)}
  end

  def update(%{report_counts_loaded: _error}, socket), do: {:ok, socket}

  # Normal prop update from parent re-render
  def update(assigns, socket) do
    prev_query = socket.assigns.query
    query = Map.get(assigns, :query, prev_query)
    query_changed? = is_binary(query) and query != prev_query
    selected_term_id = Map.get(assigns, :selected_term_id, socket.assigns.selected_term_id)
    term_changed? = selected_term_id != socket.assigns.selected_term_id

    elements = Map.get(assigns, :elements, socket.assigns.elements)

    socket =
      socket
      |> assign(:selected, Map.get(assigns, :selected, socket.assigns.selected))
      |> assign(:query, query)
      |> assign(:selected_term_id, selected_term_id)
      |> assign(
        :selected_term_name,
        Map.get(assigns, :selected_term_name, socket.assigns.selected_term_name)
      )
      |> assign(:elements, elements)
      |> assign(:total_elements, length(elements))

    socket = if query_changed? || term_changed?, do: trigger_search(socket, query), else: socket
    {:ok, socket}
  end

  # ----- handle_event -----

  def handle_event("select", %{"code" => code, "title" => title, "term" => term} = params, socket) do
    query_params =
      %{
        "q" => socket.assigns.query,
        "code" => code,
        "title" => title,
        "term" => term
      }
      |> maybe_put_snow_course_params(params)

    {:noreply, push_patch(socket, to: ~p"/syllabi?#{query_params}")}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{socket.assigns.query}")}
  end

  def handle_event("generate_all_missing", _params, socket) do
    codes =
      missing_codes(
        socket.assigns.syllabi_docs,
        socket.assigns.report_counts,
        socket.assigns.total_elements
      )

    ReportGeneratorDomainManger.generate_missing_for_codes(codes, socket.assigns.elements,
      term_id: socket.assigns.selected_term_id
    )

    {:noreply, assign(socket, :generating_all, true)}
  end

  def handle_event("generate_missing_for_professor", %{"codes" => codes_json}, socket) do
    codes =
      case Jason.decode(codes_json) do
        {:ok, list} -> list
        _ -> []
      end

    codes_with_missing =
      missing_codes_from_list(
        codes,
        socket.assigns.report_counts,
        socket.assigns.total_elements
      )

    ReportGeneratorDomainManger.generate_missing_for_codes(
      codes_with_missing,
      socket.assigns.elements,
      term_id: socket.assigns.selected_term_id
    )

    {:noreply, assign(socket, :generating_all, true)}
  end

  def handle_event("regenerate_non_met", %{"code" => code}, socket) do
    ReportGeneratorDomainManger.regenerate_non_met_for_code(code, socket.assigns.elements,
      term_id: socket.assigns.selected_term_id
    )

    {:noreply, socket}
  end

  # ----- handle_async -----

  def handle_async(:fetch_departments, {:ok, {:ok, departments}}, socket) do
    socket = assign(socket, :departments, departments)

    socket =
      if socket.assigns.search_pending? do
        trigger_search(socket, socket.assigns.query)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:fetch_departments, _result, socket), do: {:noreply, socket}

  def handle_async(:search, {:ok, {:ok, %{items: docs, cached_at: cached_at}}}, socket) do
    codes = published_codes(docs)

    if connected?(socket) do
      ReportGenerationStatus.request_pending(codes)

      ReportGeneratorDomainManger.set_syllabi_codes(codes,
        term_id: socket.assigns.selected_term_id
      )
    end

    syllabi_docs = Map.new(docs, &{&1["code"], &1})
    {code_to_slug, professors_meta, stream_items} = build_professor_groups(syllabi_docs)

    ReportGeneratorDomainManger.request_report_counts(codes, self(),
      term_id: socket.assigns.selected_term_id
    )

    {:noreply,
     socket
     |> assign(:loading_search, false)
     |> assign(:search_cached_at, cached_at)
     |> assign(:syllabi_empty?, docs == [])
     |> assign(:syllabi_docs, syllabi_docs)
     |> assign(:report_counts, %{})
     |> assign(:generating_per_code, %{})
     |> assign(:generating_all, false)
     |> assign(:code_to_slug, code_to_slug)
     |> assign(:professors_meta, professors_meta)
     |> stream(:professor_groups, stream_items, reset: true)}
  end

  def handle_async(:search, {:ok, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:loading_search, false) |> assign(:search_error, reason)}
  end

  def handle_async(:search, {:exit, reason}, socket) do
    {:noreply, socket |> assign(:loading_search, false) |> assign(:search_error, inspect(reason))}
  end

  # ----- render -----

  def render(assigns) do
    ~H"""
    <div class="flex flex-col min-h-0 w-[400px] shrink-0">
      <%= if @search_error do %>
        <div
          id="search-error"
          class="mb-3 rounded-lg bg-red-900/40 border border-red-700 px-4 py-3 text-red-300 text-sm"
        >
          {@search_error}
        </div>
      <% end %>

      <% total_generated =
        @report_counts |> Map.values() |> Enum.flat_map(&Map.values/1) |> Enum.sum()

      total_possible = published_count(@syllabi_docs) * @total_elements %>

      <%= if not @syllabi_empty? && @total_elements > 0 && total_possible > 0 && !@loading_search do %>
        <div class="mb-3 shrink-0">
          <button
            id="generate-all-btn"
            type="button"
            phx-click="generate_all_missing"
            phx-target={@myself}
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
                <span class="font-semibold text-slate-200">{total_generated}</span>
                / {total_possible} reports generated
              </span>
              <%= if total_generated == total_possible && total_possible > 0 do %>
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
        :if={@loading_search}
        id="syllabi-loading"
        class="flex flex-col items-center justify-center gap-3 py-16 text-slate-500"
      >
        <span class="hero-arrow-path size-6 animate-spin text-indigo-400" />
        <span class="text-sm">Loading syllabi…</span>
      </div>

      <%= if @search_cached_at do %>
        <div
          id="cache-indicator"
          class="mb-2 shrink-0 flex items-center gap-1.5 text-xs text-slate-500"
        >
          <span class="hero-clock size-3" />
          Cached {@search_cached_at |> Calendar.strftime("%b %d at %H:%M")}
        </div>
      <% end %>

      <div
        id="syllabi-list"
        phx-hook=".ProfessorExpansion"
        class={["overflow-y-auto flex-1 min-h-0", @loading_search && "hidden"]}
      >
        <div id="professor-groups" phx-update="stream">
          <div :for={{dom_id, group} <- @streams.professor_groups} id={dom_id}>
            <.professor_syllabi_items
              professor={group.professor}
              syllabi={Enum.map(group.codes, &@syllabi_docs[&1]) |> Enum.reject(&is_nil/1)}
              selected={@selected}
              total_elements={@total_elements}
              report_counts={@report_counts}
              generating_per_code={@generating_per_code}
              generating_all={@generating_all}
              target={@myself}
            />
          </div>
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
    </div>
    """
  end

  # ----- private -----

  defp trigger_search(socket, query) do
    term_id = socket.assigns.selected_term_id

    cond do
      query == "" ->
        socket
        |> assign(:loading_search, false)
        |> assign(:search_error, nil)
        |> assign(:search_pending?, false)
        |> assign(:syllabi_empty?, true)
        |> assign(:syllabi_docs, %{})
        |> assign(:report_counts, %{})
        |> assign(:generating_per_code, %{})
        |> assign(:generating_all, false)
        |> stream(:professor_groups, [], reset: true)

      email?(query) ->
        socket
        |> assign(:loading_search, true)
        |> assign(:syllabi_empty?, true)
        |> assign(:search_error, nil)
        |> assign(:search_pending?, false)
        |> start_async(:search, fn ->
          SyllabusDomainManager.search_by_email(query, term_id: term_id)
        end)

      socket.assigns.departments == [] ->
        socket
        |> assign(:loading_search, true)
        |> assign(:syllabi_empty?, true)
        |> assign(:search_error, nil)
        |> assign(:search_pending?, true)

      dept = find_department(socket.assigns.departments, query) ->
        socket
        |> assign(:loading_search, true)
        |> assign(:syllabi_empty?, true)
        |> assign(:search_error, nil)
        |> assign(:search_pending?, false)
        |> start_async(:search, fn ->
          SyllabusDomainManager.search_by_org(dept["entity_id"], term_id: term_id)
        end)

      true ->
        assign(socket, loading_search: false, search_error: "No matching department found")
    end
  end

  defp find_department(_departments, ""), do: nil

  defp find_department(departments, name) do
    normalized_name = String.downcase(name)

    Enum.find(departments, fn dept ->
      String.downcase(dept["name"] || "") == normalized_name
    end)
  end

  defp email?(query), do: String.contains?(query, "@")

  defp build_professor_groups(syllabi_docs) do
    hidden_professors = ["Chris Pinedo", "Engineering ADA"]

    groups =
      syllabi_docs
      |> Map.values()
      |> Enum.flat_map(fn doc ->
        case doc["editors"] || [] do
          [] -> [{"Unknown", doc["code"]}]
          editors -> Enum.map(editors, fn e -> {e["full_name"] || "Unknown", doc["code"]} end)
        end
      end)
      |> Enum.reject(fn {name, _} ->
        String.downcase(name) in Enum.map(hidden_professors, &String.downcase/1)
      end)
      |> Enum.group_by(fn {name, _} -> name end, fn {_, code} -> code end)
      |> Enum.sort_by(fn {name, _} ->
        if name == "Unknown", do: "zzz", else: String.downcase(name)
      end)

    code_to_slug =
      Enum.flat_map(groups, fn {name, codes} ->
        slug = professor_slug(name)
        Enum.map(codes, &{&1, slug})
      end)
      |> Map.new()

    professors_meta =
      Map.new(groups, fn {name, codes} ->
        slug = professor_slug(name)
        {slug, %{professor: name, codes: codes}}
      end)

    stream_items =
      Enum.map(groups, fn {name, codes} ->
        slug = professor_slug(name)
        %{id: "prof-#{slug}", slug: slug, professor: name, codes: codes}
      end)

    {code_to_slug, professors_meta, stream_items}
  end

  defp restream_professors_for_codes(socket, []), do: socket

  defp restream_professors_for_codes(socket, codes) do
    code_set = MapSet.new(codes)

    socket.assigns.professors_meta
    |> Enum.filter(fn {_slug, %{codes: prof_codes}} ->
      Enum.any?(prof_codes, &MapSet.member?(code_set, &1))
    end)
    |> Enum.reduce(socket, fn {slug, %{professor: professor, codes: prof_codes}}, acc ->
      stream_insert(acc, :professor_groups, %{
        id: "prof-#{slug}",
        slug: slug,
        professor: professor,
        codes: prof_codes
      })
    end)
  end

  defp missing_codes(syllabi_docs, report_counts, total_elements) do
    syllabi_docs
    |> Map.values()
    |> Enum.filter(&published_doc?/1)
    |> Enum.map(& &1["code"])
    |> missing_codes_from_list(report_counts, total_elements)
  end

  defp missing_codes_from_list(codes, report_counts, total_elements) do
    Enum.filter(codes, fn code ->
      counts = Map.get(report_counts, code, %{})

      run =
        Map.get(counts, "met", 0) + Map.get(counts, "not_met", 0) +
          Map.get(counts, "partially_met", 0)

      run < total_elements
    end)
  end

  defp professor_slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp published_codes(docs) do
    docs
    |> Enum.filter(&published_doc?/1)
    |> Enum.map(& &1["code"])
  end

  defp published_count(syllabi_docs) do
    syllabi_docs
    |> Map.values()
    |> Enum.count(&published_doc?/1)
  end

  defp published_doc?(doc), do: doc["source"] != "snow_courses"

  defp maybe_put_snow_course_params(query_params, %{"source" => "snow_courses"} = params) do
    query_params
    |> Map.put("source", "snow_courses")
    |> Map.put("syllabus_status", "unpublished")
    |> Map.put("term_code", params["term_code"] || "")
    |> Map.put("crn", params["crn"] || "")
    |> Map.put("subject_code", params["subject_code"] || "")
    |> Map.put("course_number", params["course_number"] || "")
    |> Map.put("section_number", params["section_number"] || "")
    |> Map.put("course_name", params["course_name"] || "")
    |> Map.put("primary_instructor_name", params["primary_instructor_name"] || "")
  end

  defp maybe_put_snow_course_params(query_params, _params), do: query_params
end
