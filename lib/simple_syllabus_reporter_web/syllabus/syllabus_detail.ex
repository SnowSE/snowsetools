defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusDetail do
  use SimpleSyllabusReporterWeb, :html

  import Phoenix.HTML, only: [raw: 1]

  attr :selected, :map, required: true
  attr :loading_detail, :boolean, required: true
  attr :detail_error, :any, default: nil

  def detail_panel(assigns) do
    assigns =
      assign(assigns, :doc_data, if(assigns.loading_detail, do: nil, else: assigns.selected))

    ~H"""
    <div
      id="detail-panel"
      class="flex flex-col flex-1 min-h-0  overflow-hidden "
    >
      <div class="flex items-center gap-3  min-w-0">
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

      <%= if @loading_detail do %>
        <div
          id="detail-loading"
          class="flex flex-1 items-center justify-center py-16 text-slate-400 text-sm gap-2"
        >
          <span class="hero-arrow-path size-4 animate-spin" /> Loading…
        </div>
      <% else %>
        <%= if @detail_error do %>
          <div id="detail-error" class="px-5 py-4 text-red-300 text-sm">
            Error: {@detail_error}
          </div>
        <% else %>
          <div
            id="detail-content"
            class="pt-2  text-sm text-slate-300 flex-1 overflow-y-auto min-h-0 bg-slate-800/60 rounded-xl p-2"
          >
            <%!-- Instructors --%>
            <% instructors = instructor_accounts(@doc_data["editors"] || []) %>
            <%= if instructors != [] do %>
              <div class="">
                <div class="flex flex-wrap gap-2">
                  <%= for account <- instructors do %>
                    <span class="inline-flex items-center gap-1.5 bg-slate-700/50 border border-slate-600 text-slate-300 text-xs px-2.5 py-1.5 rounded-lg">
                      <span class="hero-user size-3 opacity-60" />
                      {account["email"]}
                    </span>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Syllabus sections --%>
            <% components = Enum.sort_by(@doc_data["components"] || [], & &1["sort_order"]) %>
            <%= if components != [] do %>
              <div class="">
                <%= for component <- components do %>
                  <div class="syllabus-content">
                    {raw(component["html"])}
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
