defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusLive do
  use SimpleSyllabusReporterWeb, :live_view

  alias SimpleSyllabusReporter.SimpleSyllabusApi
  alias SimpleSyllabusReporterWeb.Syllabus.SyllabusDetail

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
      |> assign(:syllabi_docs, %{})

    {:ok, socket}
  end

  def handle_params(%{"q" => query} = params, _uri, socket) when byte_size(query) > 0 do
    code = params["code"]
    title = params["title"]
    term = params["term"] || ""
    prev_query = socket.assigns.query
    prev_code = socket.assigns[:selected] && socket.assigns.selected["code"]

    query_changed? = query != prev_query
    code_changed? = code != prev_code

    socket =
      if query_changed? do
        socket
        |> assign(:query, query)
        |> assign(:loading_search, true)
        |> assign(:search_error, nil)
        |> stream(:syllabi, [], reset: true)
        |> assign(:syllabi_empty?, true)
        |> start_async(:search, fn -> SimpleSyllabusApi.search_syllabi(query) end)
      else
        socket
      end

    socket =
      cond do
        code && code_changed? ->
          docs_by_code = socket.assigns.syllabi_docs

          socket
          |> reinsert_syllabus(docs_by_code, prev_code)
          |> reinsert_syllabus(docs_by_code, code)
          |> assign(:loading_detail, true)
          |> assign(:detail_error, nil)
          |> assign(:selected, %{
            "code" => code,
            "title" => (socket.assigns.selected || %{})["title"] || title || code,
            "term" => term
          })
          |> start_async(:fetch_detail, fn -> SimpleSyllabusApi.get_syllabus_details(code) end)

        is_nil(code) && code_changed? ->
          socket
          |> reinsert_syllabus(socket.assigns.syllabi_docs, prev_code)
          |> assign(:selected, nil)

        true ->
          socket
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}
  end

  def handle_event("select", %{"code" => code, "title" => title, "term" => term}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/syllabi?q=#{socket.assigns.query}&code=#{code}&title=#{title}&term=#{term}"
     )}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{socket.assigns.query}")}
  end

  def handle_async(:search, {:ok, {:ok, %{items: docs}}}, socket) do
    socket =
      socket
      |> assign(:loading_search, false)
      |> assign(:syllabi_empty?, docs == [])
      |> assign(:syllabi_docs, Map.new(docs, &{&1["code"], &1}))
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
    prev = socket.assigns.selected

    merged =
      Map.merge(doc, %{
        "code" => prev["code"],
        "title" => prev["title"],
        "term" => prev["term"]
      })

    socket =
      socket
      |> assign(:loading_detail, false)
      |> assign(:selected, merged)

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

  defp reinsert_syllabus(socket, _docs_by_code, nil), do: socket

  defp reinsert_syllabus(socket, docs_by_code, code) do
    case Map.get(docs_by_code, code) do
      nil -> socket
      doc -> stream_insert(socket, :syllabi, doc)
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col h-full min-h-0 max-w-5xl mx-auto w-full px-4 pt-8 pb-4">
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

        <div class="flex gap-6 min-h-0 flex-1 overflow-hidden">
          <%!-- Results list --%>
          <div class={[
            "flex flex-col min-h-0 flex-1",
            @selected && "hidden sm:flex sm:w-64 sm:flex-none"
          ]}>
            <div
              id="syllabi-list"
              phx-update="stream"
              class="overflow-y-auto flex-1 min-h-0 space-y-1"
            >
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
                phx-value-term={doc["term_name"] || ""}
                class={[
                  "group flex flex-col gap-0.5 px-4 py-3 rounded-lg cursor-pointer border transition-all mb-2",
                  "bg-slate-800/60 border-slate-700 hover:bg-slate-800 hover:border-indigo-500",
                  @selected && @selected["code"] == doc["code"] &&
                    "border-purple-400/70 bg-slate-800 ring-1 ring-purple-400/30"
                ]}
              >
                <span class="text-slate-100 text-sm font-medium leading-snug group-hover:text-white transition-colors">
                  {doc["title"] || doc["course_name"] || "Untitled"}
                </span>
                <div class="flex flex-wrap gap-x-3 gap-y-0.5 mt-0.5">
                  <span :if={doc["term_name"] || doc["term"]} class="text-xs text-slate-400">
                    {doc["term_name"] || doc["term"]}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <%!-- Detail panel --%>
          <%= if @selected do %>
            <SyllabusDetail.detail_panel
              selected={@selected}
              loading_detail={@loading_detail}
              detail_error={@detail_error}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
