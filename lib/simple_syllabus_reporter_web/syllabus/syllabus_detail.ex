defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusDetail do
  use SimpleSyllabusReporterWeb, :html

  import Phoenix.HTML, only: [raw: 1]

  alias SimpleSyllabusReporterWeb.Syllabus.RequirementsButtonGroup
  alias SimpleSyllabusReporterWeb.Syllabus.ReportDetail

  attr :selected, :map, required: true
  attr :loading_detail, :boolean, required: true
  attr :detail_error, :any, default: nil
  attr :elements, :list, required: true
  attr :loading_elements, :boolean, default: true
  attr :selected_element_id, :string, default: nil
  attr :report_items, :map, required: true
  attr :generating, :any, required: true
  attr :generation_errors, :map, required: true
  attr :correcting_element_id, :string, default: nil

  def detail_panel(assigns) do
    assigns =
      assign(assigns, :doc_data, if(assigns.loading_detail, do: nil, else: assigns.selected))

    ~H"""
    <div
      id="detail-panel"
      class="flex flex-col min-h-0 overflow-hidden gap-2"
    >
      <div class="flex items-center gap-3 min-w-0 shrink-0">
        <div class="flex-1 flex items-baseline gap-2 min-w-0">
          <h2 class="text-slate-100 font-semibold text-sm truncate shrink-0 max-w-xs">
            {@selected["title"] || @selected["code"] || "Syllabus Details"}
          </h2>
          <span
            :if={!@loading_detail && @doc_data && @doc_data["sub_title"]}
            class="text-slate-500 text-xs truncate"
          >
            {@doc_data["sub_title"]}
          </span>
        </div>
        <a
          href={simplesyllabus_url(@selected)}
          target="_blank"
          rel="noopener noreferrer"
          class="shrink-0 inline-flex items-center gap-1 text-xs text-slate-400 hover:text-indigo-300 transition-colors"
          title="View on Simple Syllabus"
        >
          <span class="hero-arrow-top-right-on-square size-3.5" /> View
        </a>
        <% missing_count = Enum.count(@elements, fn e -> not Map.has_key?(@report_items, e["id"]) end) %>
        <button
          id="generate-missing-selected-btn"
          type="button"
          phx-click="generate_missing_for_selected"
          disabled={
            @loading_elements or @loading_detail or missing_count == 0 or MapSet.size(@generating) > 0
          }
          class={[
            "shrink-0 inline-flex items-center gap-1 text-xs text-indigo-400 hover:text-indigo-300 disabled:opacity-40 disabled:cursor-not-allowed transition-colors cursor-pointer",
            missing_count > 0 && "bg-indigo-950/50 py-1 px-2 rounded"
          ]}
          title="Generate missing reports for this syllabus"
        >
          <span class="hero-sparkles size-3.5" />
          <%= if missing_count > 0 do %>
            Generate {missing_count} missing
          <% else %>
            All generated
          <% end %>
        </button>
        <button
          id="close-detail-btn"
          type="button"
          phx-click="close_detail"
          class="shrink-0 text-slate-400 hover:text-slate-100 transition-colors cursor-pointer"
          aria-label="Close"
        >
          <span class="hero-x-mark size-4" />
        </button>
      </div>

      <RequirementsButtonGroup.requirements_button_group
        elements={@elements}
        report_items={@report_items}
        generating={@generating}
        selected_element_id={@selected_element_id}
        loading={@loading_elements}
      />

      <%= if @loading_detail do %>
        <div id="detail-loading" class="flex flex-col flex-1 min-h-0 gap-3">
          <%!-- Skeleton button group --%>
          <div class="flex gap-1 flex-wrap shrink-0 pb-1">
            <%= for w <- ["w-20", "w-28", "w-24", "w-16", "w-24", "w-20"] do %>
              <div class={["h-7 rounded-lg bg-slate-800 animate-pulse", w]} />
            <% end %>
          </div>
          <%!-- Skeleton report items --%>
          <div class="flex flex-col gap-4 overflow-y-auto flex-1 min-h-0">
            <%= for _ <- 1..4 do %>
              <div class="flex flex-col gap-2 rounded-xl bg-slate-900/60 px-4 py-4 animate-pulse">
                <div class="flex items-center justify-between gap-3">
                  <div class="h-3.5 w-40 rounded bg-slate-700" />
                  <div class="h-6 w-20 rounded-lg bg-slate-800" />
                </div>
                <div class="h-3 w-full rounded bg-slate-800/80" />
                <div class="h-3 w-3/4 rounded bg-slate-800/80" />
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <%= if @detail_error do %>
          <div id="detail-error" class="px-5 py-4 text-red-300 text-sm">
            Error: {@detail_error}
          </div>
        <% else %>
          <div
            id="detail-content"
            class="flex flex-col flex-1 overflow-y-auto min-h-0 gap-3"
          >
            <ReportDetail.report_detail
              selected_element_id={@selected_element_id}
              elements={@elements}
              report_items={@report_items}
              generating={@generating}
              generation_errors={@generation_errors}
              syllabus={@selected}
              correcting_element_id={@correcting_element_id}
              class=""
            />

            <div class="text-sm text-slate-300 bg-slate-900/70 rounded-xl p-2 shrink-0">
              <% instructors = instructor_accounts(@doc_data["editors"] || []) %>
              <%= if instructors != [] do %>
                <div class="flex flex-wrap gap-2 mb-2">
                  <%= for account <- instructors do %>
                    <span class="inline-flex items-center gap-1.5 bg-slate-700/50 border border-slate-600 text-slate-300 text-xs px-2.5 py-1.5 rounded-lg">
                      <span class="hero-user size-3 opacity-60" />
                      {account["email"]}
                    </span>
                  <% end %>
                </div>
              <% end %>

              <% components = Enum.sort_by(@doc_data["components"] || [], & &1["sort_order"]) %>
              <%= if components != [] do %>
                <%= for component <- components do %>
                  <div class="syllabus-content">
                    {raw(component["html"])}
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  def detail_panel_placeholder(assigns) do
    ~H"""
    <div
      id="detail-panel-placeholder"
      class="flex flex-col flex-1 min-h-0 items-center justify-center gap-3 rounded-xl border border-dashed border-slate-700/60 text-slate-600"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="w-10 h-10 opacity-40"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
        stroke-width="1.5"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 0 0 2.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 0 0-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75 2.25 2.25 0 0 0-.1-.664m-5.8 0A2.251 2.251 0 0 1 13.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25Z"
        />
      </svg>
      <p class="text-sm">Select a syllabus to view details</p>
    </div>
    """
  end

  defp simplesyllabus_url(doc) do
    code = doc["code"] || ""

    term_name =
      cond do
        is_map(doc["term"]) -> doc["term"]["name"] || ""
        is_binary(doc["term"]) -> doc["term"]
        true -> ""
      end

    title = doc["title"] || code

    slug =
      (term_name <> " " <> title)
      |> String.trim()
      |> String.replace(" ", "-")
      |> URI.encode(&URI.char_unreserved?/1)

    "https://snow.simplesyllabus.com/en-US/doc/#{code}/#{slug}?mode=view"
  end

  defp instructor_accounts(editors) do
    editors
    |> Enum.filter(fn editor ->
      role_types = get_in(editor, ["role", "role_types"]) || []
      "instructor" in role_types
    end)
    |> Enum.flat_map(fn editor -> editor["accounts"] || [] end)
  end
end
