defmodule SnowSeToolsWeb.Syllabus.SyllabusDetail do
  use SnowSeToolsWeb, :html

  import Phoenix.HTML, only: [raw: 1]

  alias SnowSeToolsWeb.Syllabus.RequirementsButtonGroup
  alias SnowSeToolsWeb.Syllabus.ReportDetail

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
      assigns
      |> assign(:doc_data, if(assigns.loading_detail, do: nil, else: assigns.selected))
      |> assign(:unpublished?, unpublished_snow_course?(assigns.selected))
      |> assign(:snow_course, assigns.selected["snow_course"] || %{})

    ~H"""
    <div
      id="detail-panel"
      class="flex flex-col flex-1 min-h-0 overflow-hidden gap-2"
    >
      <div class="flex items-center gap-3 min-w-0 shrink-0">
        <div class="flex-1 flex items-baseline gap-2 min-w-0">
          <h2 class="text-slate-100 font-semibold text-sm truncate shrink-0 max-w-xs">
            {@selected["title"] || @selected["code"] || "Syllabus Details"}
          </h2>
          <span
            :if={@unpublished?}
            class="rounded bg-amber-500/10 px-2 py-0.5 text-[10px] font-semibold uppercase text-amber-200"
          >
            Not published
          </span>
          <span
            :if={!@unpublished? && !@loading_detail && @doc_data && @doc_data["sub_title"]}
            class="text-slate-500 text-xs truncate"
          >
            {@doc_data["sub_title"]}
          </span>
        </div>
        <a
          :if={!@unpublished?}
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
          :if={!@unpublished?}
          id="generate-missing-selected-btn"
          type="button"
          phx-click="generate_missing_for_selected"
          disabled={
            @loading_elements or @loading_detail or missing_count == 0 or MapSet.size(@generating) > 0
          }
          class={[
            "shrink-0 inline-flex items-center gap-1 text-indigo-200  px-1 rounded border border-indigo-800
               disabled:cursor-not-allowed disabled:cursor-none transition-colors ",
            missing_count <= 0 && " text-slate-500 cursor-default",
            missing_count > 0 &&
              "bg-indigo-950/50 py-1 px-2 rounded text-xs cursor-pointer hover:text-indigo-100 hover:bg-indigo-950"
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
        :if={!@unpublished?}
        elements={@elements}
        report_items={@report_items}
        generating={@generating}
        selected_element_id={@selected_element_id}
        loading={@loading_elements}
      />

      <%= if @unpublished? do %>
        <div
          id="unpublished-snow-course-detail"
          class="flex flex-col gap-4 rounded-xl border border-amber-500/15 bg-amber-500/5 p-5 text-sm text-slate-300"
        >
          <div>
            <p class="font-medium text-amber-100">
              This section is expected from Banner, but no Simple Syllabus document has been published yet.
            </p>
            <p class="mt-1 text-slate-400">
              Report generation will be available after the syllabus appears in Simple Syllabus sync results.
            </p>
          </div>

          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <div class="text-[10px] font-semibold uppercase tracking-widest text-slate-500">
                Course
              </div>
              <div class="mt-1 text-slate-100">
                {course_label(@snow_course)}
              </div>
            </div>
            <div>
              <div class="text-[10px] font-semibold uppercase tracking-widest text-slate-500">
                CRN
              </div>
              <div class="mt-1 text-slate-100">{blank_fallback(@snow_course["crn"])}</div>
            </div>
            <div>
              <div class="text-[10px] font-semibold uppercase tracking-widest text-slate-500">
                Term
              </div>
              <div class="mt-1 text-slate-100">
                {blank_fallback(@selected["term_name"] || @selected["term"])}
              </div>
            </div>
            <div>
              <div class="text-[10px] font-semibold uppercase tracking-widest text-slate-500">
                Instructor
              </div>
              <div class="mt-1 text-slate-100">
                {blank_fallback(@snow_course["primary_instructor_name"])}
              </div>
            </div>
          </div>
        </div>
      <% else %>
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
      <% end %>
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

  defp unpublished_snow_course?(%{"source" => "snow_courses"}), do: true
  defp unpublished_snow_course?(_selected), do: false

  defp course_label(snow_course) do
    [
      snow_course["subject_code"],
      snow_course["course_number"],
      snow_course["section_number"]
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> case do
      "" -> blank_fallback(snow_course["course_name"])
      code -> code <> " " <> blank_fallback(snow_course["course_name"])
    end
  end

  defp blank_fallback(value) when is_binary(value) do
    if String.trim(value) == "", do: "Not cached", else: value
  end

  defp blank_fallback(_value), do: "Not cached"

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: true

  def detail_panel_placeholder(assigns) do
    ~H"""
    <div class="flex flex-col flex-1 items-center justify-center gap-3 text-slate-600 border-2 border-dashed border-slate-800 rounded-xl">
      <span class="hero-document-text size-10" />
      <p class="text-sm">Select a syllabus to view details</p>
    </div>
    """
  end
end
