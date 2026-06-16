defmodule SnowSeToolsWeb.Syllabus.SyllabusReportLive do
  use SnowSeToolsWeb, :live_view

  alias SnowSeTools.Syllabi.SyllabusDomainManager
  alias SnowSeTools.Reports.ReportGeneratorDomainManger
  alias SnowSeTools.Reports.ReportGenerationStatus
  alias SnowSeToolsWeb.Syllabus.ReportCorrection
  alias SnowSeToolsWeb.Syllabus.ReportDetail
  alias SnowSeToolsWeb.Syllabus.RequirementsButtonGroup

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    if connected?(socket), do: ReportGenerationStatus.subscribe()
    if connected?(socket), do: ReportGeneratorDomainManger.request_elements(self())

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
     |> assign(:correcting_element_id, nil)}
  end

  def handle_params(%{"code" => code}, _uri, socket) when byte_size(code) > 0 do
    if connected?(socket) do
      ReportGenerationStatus.request_pending([code])
    end

    if connected?(socket), do: ReportGeneratorDomainManger.request_items_for_code(code, self())

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
     |> start_async(:fetch_syllabus, fn -> SyllabusDomainManager.get_detail(code) end)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: ~p"/syllabi")}
  end

  def handle_event("select_element", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_element_id, id)}
  end

  def handle_event("open_correction", %{"id" => element_id}, socket) do
    {:noreply, assign(socket, :correcting_element_id, element_id)}
  end

  def handle_event("cancel_correction", _params, socket) do
    {:noreply, assign(socket, :correcting_element_id, nil)}
  end

  def handle_event("save_correction", params, socket) do
    ReportCorrection.handle_save_correction(params, socket, socket.assigns.syllabus)
  end

  def handle_event("generate_report", %{"id" => element_id}, socket) do
    element = Enum.find(socket.assigns.elements, fn e -> e["id"] == element_id end)
    ReportGeneratorDomainManger.generate_async(socket.assigns.syllabus, element)

    {:noreply,
     socket
     |> assign(:generating, MapSet.put(socket.assigns.generating, element_id))
     |> assign(:generation_errors, Map.delete(socket.assigns.generation_errors, element_id))}
  end

  def handle_info(
        %ReportGenerationStatus.PendingUpdate{pending: pending},
        socket
      ) do
    code = socket.assigns.code

    element_ids =
      Enum.reduce(pending, MapSet.new(), fn {c, id}, acc ->
        if c == code, do: MapSet.put(acc, id), else: acc
      end)

    {:noreply, assign(socket, :generating, element_ids)}
  end

  def handle_info(
        %ReportGenerationStatus.ItemResult{element_id: element_id, result: {:ok, item}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:report_items, Map.put(socket.assigns.report_items, element_id, item))
     |> assign(:generating, MapSet.delete(socket.assigns.generating, element_id))}
  end

  def handle_info(
        %ReportGenerationStatus.ItemResult{element_id: element_id, result: {:error, reason}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:generating, MapSet.delete(socket.assigns.generating, element_id))
     |> assign(
       :generation_errors,
       Map.put(socket.assigns.generation_errors, element_id, inspect(reason))
     )}
  end

  def handle_info({:elements_loaded, {:ok, elements}}, socket) do
    {:noreply, socket |> assign(:elements, elements) |> assign(:loading_elements, false)}
  end

  def handle_info({:elements_loaded, _error}, socket) do
    {:noreply, assign(socket, :loading_elements, false)}
  end

  def handle_info({:report_items_loaded, {:ok, items_map}}, socket) do
    {:noreply, assign(socket, :report_items, items_map)}
  end

  def handle_info({:report_items_loaded, _error}, socket) do
    {:noreply, socket}
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

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} socket={@socket} current_path={@current_path}>
      <div class="flex flex-col h-full min-h-0 gap-2 p-4 max-w-7xl mx-auto w-full">
        <div class="flex items-center gap-3">
          <.link
            navigate={~p"/syllabi"}
            class="text-slate-500 hover:text-slate-200 transition-colors shrink-0"
            title="Back to search"
          >
            <span class="hero-arrow-left size-4" />
          </.link>
          <%= if @loading_syllabus do %>
            <div class="flex items-center gap-2 text-slate-400 text-xs">
              <span class="hero-arrow-path size-3.5 animate-spin" /> Loading…
            </div>
          <% else %>
            <%= if @syllabus do %>
              <div class="min-w-0 flex items-baseline gap-2">
                <h1 class="text-slate-100 font-semibold text-sm truncate">
                  {@syllabus["sub_title"]}
                </h1>
                <p class="text-slate-500 text-xs shrink-0">
                  {@code}
                  <%= if @syllabus["sub_title"] && @syllabus["sub_title"] != "" do %>
                    · {@syllabus["title"] || @code}
                  <% end %>
                </p>
              </div>
            <% else %>
              <h1 class="text-slate-100 font-semibold text-sm">{@code}</h1>
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

        <div class="flex flex-col flex-1 min-h-0 overflow-hidden gap-2">
          <RequirementsButtonGroup.requirements_button_group
            elements={@elements}
            report_items={@report_items}
            generating={@generating}
            selected_element_id={@selected_element_id}
            loading={@loading_elements}
          />

          <ReportDetail.report_detail
            selected_element_id={@selected_element_id}
            elements={@elements}
            report_items={@report_items}
            generating={@generating}
            generation_errors={@generation_errors}
            syllabus={@syllabus}
            correcting_element_id={@correcting_element_id}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
