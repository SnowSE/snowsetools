defmodule SimpleSyllabusReporterWeb.SyllabusLive do
  use SimpleSyllabusReporterWeb, :live_view

  alias SimpleSyllabusReporter.SimpleSyllabusApi

  on_mount {SimpleSyllabusReporterWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Syllabus Search")
      |> assign(:query, "")
      |> assign(:loading_search, false)
      |> assign(:loading_detail, false)
      |> assign(:search_error, nil)
      |> assign(:detail_error, nil)
      |> assign(:selected, nil)
      |> stream_configure(:syllabi, dom_id: fn item -> item["code"] end)
      |> stream(:syllabi, [])
      |> assign(:syllabi_empty?, true)

    {:ok, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:query, query)
      |> assign(:loading_search, true)
      |> assign(:search_error, nil)
      |> assign(:selected, nil)
      |> stream(:syllabi, [], reset: true)
      |> assign(:syllabi_empty?, true)

    {:noreply,
     socket
     |> start_async(:search, fn -> SimpleSyllabusApi.search_syllabi(query) end)}
  end

  def handle_event("select", %{"code" => code, "title" => title}, socket) do
    socket =
      socket
      |> assign(:loading_detail, true)
      |> assign(:detail_error, nil)
      |> assign(:selected, %{"code" => code, "title" => title})

    {:noreply,
     socket |> start_async(:fetch_detail, fn -> SimpleSyllabusApi.get_syllabus_details(code) end)}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :selected, nil)}
  end

  def handle_async(:search, {:ok, {:ok, %{items: docs}}}, socket) do
    socket =
      socket
      |> assign(:loading_search, false)
      |> assign(:syllabi_empty?, docs == [])
      |> stream(:syllabi, docs, reset: true)

    {:noreply, socket}
  end

  def handle_async(:search, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:loading_search, false)
      |> assign(:search_error, reason)

    {:noreply, socket}
  end

  def handle_async(:search, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:loading_search, false)
      |> assign(:search_error, inspect(reason))

    {:noreply, socket}
  end

  def handle_async(:fetch_detail, {:ok, {:ok, doc}}, socket) do
    socket =
      socket
      |> assign(:loading_detail, false)
      |> assign(:selected, doc)

    {:noreply, socket}
  end

  def handle_async(:fetch_detail, {:ok, {:error, reason}}, socket) do
    socket =
      socket
      |> assign(:loading_detail, false)
      |> assign(:detail_error, reason)

    {:noreply, socket}
  end

  def handle_async(:fetch_detail, {:exit, reason}, socket) do
    socket =
      socket
      |> assign(:loading_detail, false)
      |> assign(:detail_error, inspect(reason))

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-5xl mx-auto px-4 py-10">
        <%!-- Search form --%>
        <form id="syllabus-search-form" phx-submit="search" class="flex gap-3 mb-8">
          <input
            id="search-query-input"
            type="text"
            name="query"
            value={@query}
            placeholder="Instructor name, e.g. Alex Mickelson"
            class="flex-1 bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition"
            autofocus
          />
          <button
            type="submit"
            id="search-submit-btn"
            disabled={@loading_search}
            class="px-5 py-2.5 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-medium rounded-lg transition-colors"
          >
            <%= if @loading_search do %>
              Searching…
            <% else %>
              Search
            <% end %>
          </button>
        </form>

        <%!-- Search error --%>
        <%= if @search_error do %>
          <div
            id="search-error"
            class="mb-6 rounded-lg bg-red-900/40 border border-red-700 px-4 py-3 text-red-300 text-sm"
          >
            Error: {@search_error}
          </div>
        <% end %>

        <div class="flex gap-6 items-start">
          <%!-- Results list --%>
          <div class={["flex-1 min-w-0", @selected && "hidden sm:block sm:w-64 sm:flex-none"]}>
            <div id="syllabi-list" phx-update="stream">
              <div class={[
                "hidden text-slate-500 text-sm italic py-4",
                @syllabi_empty? && @query != "" && !@loading_search && "only:block"
              ]}>
                No syllabi found for "{@query}".
              </div>
              <div
                :for={{id, doc} <- @streams.syllabi}
                id={id}
                phx-click="select"
                phx-value-code={doc["code"]}
                phx-value-title={doc["title"] || doc["course_name"] || "Untitled"}
                class={[
                  "group flex flex-col gap-0.5 px-4 py-3 rounded-lg cursor-pointer border transition-all mb-2",
                  "bg-slate-800/60 border-slate-700 hover:bg-slate-800 hover:border-indigo-500",
                  @selected && @selected["code"] == doc["code"] && "border-indigo-500 bg-slate-800"
                ]}
              >
                <span class="text-slate-100 text-sm font-medium leading-snug group-hover:text-white transition-colors">
                  {doc["title"] || doc["course_name"] || "Untitled"}
                </span>
                <div class="flex flex-wrap gap-x-3 gap-y-0.5 mt-0.5">
                  <span :if={doc["term_name"] || doc["term"]} class="text-xs text-slate-400">
                    {doc["term_name"] || doc["term"]}
                  </span>
                  <span :if={doc["course_number"] || doc["number"]} class="text-xs text-slate-500">
                    {doc["course_number"] || doc["number"]}
                  </span>
                  <span :if={doc["code"]} class="text-xs text-slate-600 font-mono">
                    {doc["code"]}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <%!-- Detail panel --%>
          <%= if @selected do %>
            <div
              id="detail-panel"
              class="flex-1 min-w-0 bg-slate-800/60 border border-slate-700 rounded-xl overflow-hidden"
            >
              <div class="flex items-center justify-between px-5 py-4 border-b border-slate-700">
                <h2 class="text-slate-100 font-semibold text-base truncate pr-4">
                  {@selected["title"] || @selected["course_name"] || "Syllabus Details"}
                </h2>
                <button
                  id="close-detail-btn"
                  type="button"
                  phx-click="close_detail"
                  class="text-slate-400 hover:text-slate-100 transition-colors shrink-0 cursor-pointer"
                  aria-label="Close"
                >
                  <span class="hero-x-mark size-5" />
                </button>
              </div>

              <%= if @loading_detail do %>
                <div
                  id="detail-loading"
                  class="flex items-center justify-center py-16 text-slate-400 text-sm gap-2"
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
                    class="px-5 py-5 space-y-4 text-sm text-slate-300 max-h-[70vh] overflow-y-auto"
                  >
                    <%!-- Meta fields --%>
                    <div class="grid grid-cols-2 gap-3">
                      <div
                        :if={@selected["course_number"] || @selected["number"]}
                        class="bg-slate-900/50 rounded-lg px-3 py-2"
                      >
                        <div class="text-xs text-slate-500 mb-0.5">Course Number</div>
                        <div class="text-slate-200">
                          {@selected["course_number"] || @selected["number"]}
                        </div>
                      </div>
                      <div
                        :if={@selected["term_name"] || @selected["term"]}
                        class="bg-slate-900/50 rounded-lg px-3 py-2"
                      >
                        <div class="text-xs text-slate-500 mb-0.5">Term</div>
                        <div class="text-slate-200">
                          {@selected["term_name"] || @selected["term"]}
                        </div>
                      </div>
                      <div
                        :if={@selected["editor"] || @selected["instructor"]}
                        class="bg-slate-900/50 rounded-lg px-3 py-2"
                      >
                        <div class="text-xs text-slate-500 mb-0.5">Instructor</div>
                        <div class="text-slate-200">
                          {@selected["editor"] || @selected["instructor"]}
                        </div>
                      </div>
                      <div :if={@selected["code"]} class="bg-slate-900/50 rounded-lg px-3 py-2">
                        <div class="text-xs text-slate-500 mb-0.5">Code</div>
                        <div class="text-slate-200 font-mono text-xs">{@selected["code"]}</div>
                      </div>
                    </div>

                    <%!-- Sections / pages --%>
                    <%= if pages = @selected["pages"] || @selected["sections"] do %>
                      <div class="space-y-3">
                        <h3 class="text-slate-400 text-xs font-semibold uppercase tracking-wider">
                          Sections
                        </h3>
                        <%= for section <- pages do %>
                          <div class="border border-slate-700 rounded-lg px-4 py-3 space-y-1">
                            <div :if={section["title"]} class="text-slate-100 font-medium">
                              {section["title"]}
                            </div>
                            <div
                              :if={section["body"] || section["content"]}
                              class="text-slate-400 text-xs leading-relaxed"
                            >
                              {section["body"] || section["content"]}
                            </div>
                          </div>
                        <% end %>
                      </div>
                    <% end %>

                    <%!-- Raw fallback: show all top-level keys not already shown --%>
                    <% shown_keys =
                      ~w(title course_name course_number number term_name term editor instructor code pages sections) %>
                    <% extra = Map.drop(@selected, shown_keys) %>
                    <%= if map_size(extra) > 0 do %>
                      <div class="space-y-2">
                        <h3 class="text-slate-400 text-xs font-semibold uppercase tracking-wider">
                          Additional Info
                        </h3>
                        <%= for {key, val} <- extra, is_binary(val) or is_number(val) do %>
                          <div class="flex gap-2 text-xs">
                            <span class="text-slate-500 shrink-0 w-32 truncate">{key}</span>
                            <span class="text-slate-300 break-all">{val}</span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
