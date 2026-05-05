defmodule SimpleSyllabusReporterWeb.Syllabus.SyllabusReportLive do
  use SimpleSyllabusReporterWeb, :live_view

  alias SimpleSyllabusReporter.SimpleSyllabusApi
  alias SimpleSyllabusReporter.Reports.RequiredElement
  alias SimpleSyllabusReporter.Reports.GeneratedReport
  alias SimpleSyllabusReporter.Reports.GeneratedReportItem
  alias SimpleSyllabusReporter.Reports.ReportGenerator

  on_mount {SimpleSyllabusReporterWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Syllabus Report")
     |> assign(:code, nil)
     |> assign(:syllabus, nil)
     |> assign(:loading_syllabus, false)
     |> assign(:syllabus_error, nil)
     |> assign(:elements, [])
     |> assign(:loading_elements, true)
     |> assign(:selected_element_id, nil)
     |> assign(:report_items, %{})
     |> assign(:generating, MapSet.new())
     |> assign(:generation_errors, %{})
     |> start_async(:fetch_elements, fn -> RequiredElement.list_all() end)}
  end

  def handle_params(%{"code" => code}, _uri, socket) when byte_size(code) > 0 do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SimpleSyllabusReporter.PubSub, ReportGenerator.report_topic(code))
      Phoenix.PubSub.subscribe(SimpleSyllabusReporter.PubSub, ReportGenerator.pending_topic(code))
      ReportGenerator.request_pending([code])
    end

    {:noreply,
     socket
     |> assign(:code, code)
     |> assign(:loading_syllabus, true)
     |> assign(:syllabus, nil)
     |> assign(:syllabus_error, nil)
     |> assign(:selected_element_id, nil)
     |> assign(:report_items, %{})
     |> assign(:generation_errors, %{})
     |> assign(:generating, MapSet.new())
     |> start_async(:fetch_syllabus, fn -> SimpleSyllabusApi.get_syllabus_details(code) end)
     |> start_async(:fetch_existing_items, fn -> existing_items_for_code(code) end)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/syllabi")}
  end

  def handle_event("select_element", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_element_id, id)}
  end

  def handle_event("generate_report", %{"id" => element_id}, socket) do
    element = Enum.find(socket.assigns.elements, fn e -> e["id"] == element_id end)
    ReportGenerator.generate_async(socket.assigns.syllabus, element)

    {:noreply,
     socket
     |> assign(:generating, MapSet.put(socket.assigns.generating, element_id))
     |> assign(:generation_errors, Map.delete(socket.assigns.generation_errors, element_id))}
  end

  def handle_info({:pending_update, code, element_ids}, socket) do
    if socket.assigns.code == code do
      {:noreply, assign(socket, :generating, element_ids)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:report_item_result, _code, element_id, {:ok, item}}, socket) do
    {:noreply,
     socket
     |> assign(:report_items, Map.put(socket.assigns.report_items, element_id, item))}
  end

  def handle_info({:report_item_result, _code, element_id, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(
       :generation_errors,
       Map.put(socket.assigns.generation_errors, element_id, inspect(reason))
     )}
  end

  def handle_async(:fetch_elements, {:ok, {:ok, elements}}, socket) do
    {:noreply, socket |> assign(:elements, elements) |> assign(:loading_elements, false)}
  end

  def handle_async(:fetch_elements, _result, socket) do
    {:noreply, assign(socket, :loading_elements, false)}
  end

  def handle_async(:fetch_syllabus, {:ok, {:ok, doc}}, socket) do
    {:noreply, socket |> assign(:syllabus, doc) |> assign(:loading_syllabus, false)}
  end

  def handle_async(:fetch_syllabus, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket |> assign(:loading_syllabus, false) |> assign(:syllabus_error, inspect(reason))}
  end

  def handle_async(:fetch_syllabus, {:exit, reason}, socket) do
    {:noreply,
     socket |> assign(:loading_syllabus, false) |> assign(:syllabus_error, inspect(reason))}
  end

  def handle_async(:fetch_existing_items, {:ok, {:ok, items_map}}, socket) do
    {:noreply, assign(socket, :report_items, items_map)}
  end

  def handle_async(:fetch_existing_items, _result, socket) do
    {:noreply, socket}
  end

  defp existing_items_for_code(code) do
    case GeneratedReport.get_latest_for_syllabus(code) do
      {:ok, report} -> GeneratedReportItem.list_for_report_as_map(report["id"])
      {:error, :not_found} -> {:ok, %{}}
      {:error, _} = err -> err
    end
  end

  defp status_label("met"), do: "Met"
  defp status_label("not_met"), do: "Not Met"
  defp status_label("partially_met"), do: "Partially Met"
  defp status_label(_), do: nil

  defp status_classes("met"),
    do: "bg-green-900/40 text-green-400 border-green-700/50"

  defp status_classes("not_met"),
    do: "bg-red-900/40 text-red-400 border-red-700/50"

  defp status_classes("partially_met"),
    do: "bg-yellow-900/40 text-yellow-400 border-yellow-700/50"

  defp status_classes(_), do: "bg-slate-700/50 text-slate-500 border-slate-600"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col h-full min-h-0 gap-6 p-6 max-w-7xl mx-auto w-full">
        <%!-- Page header --%>
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/syllabi"}
            class="text-slate-400 hover:text-slate-100 transition-colors"
            title="Back to search"
          >
            <span class="hero-arrow-left size-5" />
          </.link>
          <%= if @loading_syllabus do %>
            <div class="flex items-center gap-2 text-slate-400 text-sm">
              <span class="hero-arrow-path size-4 animate-spin" /> Loading syllabus…
            </div>
          <% else %>
            <%= if @syllabus do %>
              <div class="min-w-0">
                <h1 class="text-slate-100 font-semibold text-lg truncate">
                  {@syllabus["title"] || @code}
                </h1>
                <p class="text-slate-500 text-sm">
                  {@code}
                  <%= if @syllabus["sub_title"] && @syllabus["sub_title"] != "" do %>
                    · {@syllabus["sub_title"]}
                  <% end %>
                </p>
              </div>
            <% else %>
              <h1 class="text-slate-100 font-semibold text-lg">{@code}</h1>
            <% end %>
          <% end %>
        </div>

        <%= if @syllabus_error do %>
          <div
            id="syllabus-error"
            class="rounded-lg bg-red-900/40 border border-red-700 px-4 py-3 text-red-300 text-sm"
          >
            Could not load syllabus: {@syllabus_error}
          </div>
        <% end %>

        <%!-- Main two-column layout --%>
        <div class="flex gap-6 flex-1 min-h-0 overflow-hidden">
          <%!-- Left: elements list --%>
          <div class="w-64 shrink-0 flex flex-col gap-2 overflow-y-auto">
            <h2 class="text-slate-400 text-xs font-semibold uppercase tracking-wider px-1 shrink-0">
              Required Elements
            </h2>
            <%= if @loading_elements do %>
              <div
                id="elements-loading"
                class="text-slate-500 text-sm text-center py-8"
              >
                <span class="hero-arrow-path size-4 animate-spin inline-block" />
              </div>
            <% else %>
              <%= for element <- @elements do %>
                <% item = Map.get(@report_items, element["id"]) %>
                <% generating? = MapSet.member?(@generating, element["id"]) %>
                <% selected? = @selected_element_id == element["id"] %>
                <button
                  id={"element-btn-#{element["id"]}"}
                  type="button"
                  phx-click="select_element"
                  phx-value-id={element["id"]}
                  class={[
                    "w-full text-left px-4 py-3 rounded-xl border transition-all cursor-pointer",
                    if(selected?,
                      do: "bg-indigo-600/15 border-indigo-500/50 ring-1 ring-indigo-500/20",
                      else:
                        "bg-slate-900/60 border-slate-700/60 hover:border-slate-500 hover:bg-slate-900"
                    )
                  ]}
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class={[
                      "text-sm font-medium leading-snug truncate",
                      if(selected?, do: "text-indigo-200", else: "text-slate-100")
                    ]}>
                      {element["name"]}
                    </span>
                    <%= if generating? do %>
                      <span class="hero-arrow-path size-3.5 animate-spin text-indigo-400 shrink-0" />
                    <% else %>
                      <%= if item do %>
                        <span class={[
                          "text-xs px-1.5 py-0.5 rounded border shrink-0",
                          status_classes(item["status"])
                        ]}>
                          {status_label(item["status"])}
                        </span>
                      <% end %>
                    <% end %>
                  </div>
                </button>
              <% end %>
            <% end %>
          </div>

          <%!-- Right: report item detail --%>
          <div class="flex-1 min-w-0 overflow-y-auto">
            <%= cond do %>
              <% is_nil(@selected_element_id) -> %>
                <div
                  id="report-empty-state"
                  class="flex flex-col items-center justify-center h-full text-slate-500 text-sm gap-2 py-24"
                >
                  <span class="hero-clipboard-document-list size-10 opacity-30" />
                  <p>Select a required element to view or generate its report.</p>
                </div>
              <% true -> %>
                <% element = Enum.find(@elements, fn e -> e["id"] == @selected_element_id end) %>
                <%= if element do %>
                  <% item = Map.get(@report_items, element["id"]) %>
                  <% generating? = MapSet.member?(@generating, element["id"]) %>
                  <% error = Map.get(@generation_errors, element["id"]) %>
                  <div
                    id={"report-item-#{element["id"]}"}
                    class="flex flex-col gap-6"
                  >
                    <%!-- Element header --%>
                    <div class="rounded-xl border border-slate-800 bg-slate-900/40 px-6 py-5">
                      <div class="flex items-start justify-between gap-4">
                        <div class="min-w-0">
                          <h2 class="text-lg font-semibold text-slate-100">{element["name"]}</h2>
                          <%= if element["description"] && element["description"] != "" do %>
                            <p class="text-slate-400 text-sm mt-1">{element["description"]}</p>
                          <% end %>
                        </div>
                        <div class="flex items-center gap-3 shrink-0">
                          <%= if item && !is_nil(item["status"]) do %>
                            <span class={[
                              "text-sm px-3 py-1 rounded-lg border font-medium",
                              status_classes(item["status"])
                            ]}>
                              {status_label(item["status"])}
                            </span>
                          <% end %>
                          <button
                            id={"generate-btn-#{element["id"]}"}
                            type="button"
                            phx-click="generate_report"
                            phx-value-id={element["id"]}
                            disabled={generating? || is_nil(@syllabus)}
                            class={[
                              "inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all",
                              if(generating? || is_nil(@syllabus),
                                do:
                                  "bg-slate-700/50 text-slate-500 cursor-not-allowed border border-slate-700",
                                else:
                                  "bg-indigo-600 hover:bg-indigo-500 text-white cursor-pointer border border-indigo-500"
                              )
                            ]}
                          >
                            <%= if generating? do %>
                              <span class="hero-arrow-path size-4 animate-spin" /> Generating…
                            <% else %>
                              <%= if item do %>
                                <span class="hero-arrow-path size-4" /> Re-generate
                              <% else %>
                                <span class="hero-sparkles size-4" /> Generate Report
                              <% end %>
                            <% end %>
                          </button>
                        </div>
                      </div>
                    </div>

                    <%!-- Generation error --%>
                    <%= if error do %>
                      <div
                        id={"gen-error-#{element["id"]}"}
                        class="rounded-xl border border-red-800 bg-red-900/20 px-5 py-4 text-red-300 text-sm"
                      >
                        <div class="flex items-center gap-2 font-medium mb-1">
                          <span class="hero-exclamation-circle size-4" /> Generation failed
                        </div>
                        {error}
                      </div>
                    <% end %>

                    <%!-- Report item content --%>
                    <%= if item do %>
                      <%!-- Description --%>
                      <div class="rounded-xl border border-slate-800 bg-slate-900/40 px-6 py-5">
                        <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
                          Finding
                        </h3>
                        <p class="text-slate-200 text-sm leading-relaxed">{item["description"]}</p>
                      </div>

                      <%!-- Evidence --%>
                      <%= if item["evidence"] && item["evidence"] != "" do %>
                        <div class="rounded-xl border border-slate-800 bg-slate-900/40 px-6 py-5">
                          <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
                            Evidence
                          </h3>
                          <blockquote class="border-l-2 border-indigo-500/50 pl-4 text-slate-300 text-sm leading-relaxed italic">
                            {item["evidence"]}
                          </blockquote>
                        </div>
                      <% end %>

                      <%!-- Additional considerations --%>
                      <%= if item["additional_considerations"] && item["additional_considerations"] != "" do %>
                        <div class="rounded-xl border border-slate-800 bg-slate-900/40 px-6 py-5">
                          <h3 class="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
                            Additional Considerations
                          </h3>
                          <p class="text-slate-300 text-sm leading-relaxed">
                            {item["additional_considerations"]}
                          </p>
                        </div>
                      <% end %>
                    <% end %>

                    <%!-- Generating placeholder --%>
                    <%= if generating? && is_nil(item) do %>
                      <div class="flex flex-col gap-3">
                        <%= for _ <- 1..3 do %>
                          <div class="rounded-xl border border-slate-800 bg-slate-900/40 px-6 py-5 animate-pulse">
                            <div class="h-3 bg-slate-700 rounded w-24 mb-4" />
                            <div class="h-2 bg-slate-800 rounded w-full mb-2" />
                            <div class="h-2 bg-slate-800 rounded w-5/6" />
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
