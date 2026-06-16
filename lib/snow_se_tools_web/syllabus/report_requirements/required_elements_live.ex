defmodule SnowSeToolsWeb.Reports.RequiredElementsLive do
  use SnowSeToolsWeb, :live_view

  alias SnowSeTools.Reports.RequiredElementDB
  alias SnowSeTools.Reports.ReportInstructionDB
  alias SnowSeTools.Reports.ReportGeneratorDomainManger

  import SnowSeToolsWeb.Reports.ElementsList
  import SnowSeToolsWeb.Reports.ElementDetail

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Required Elements")
      |> assign(:editing, nil)
      |> assign(:form_errors, %{})
      |> assign(:confirm_delete, nil)
      |> assign(:expanded_id, nil)
      |> assign(:instructions, [])
      |> assign(:editing_instruction, nil)
      |> assign(:instruction_errors, %{})
      |> assign(:confirm_delete_instruction, nil)
      |> assign(:element_counts, nil)
      |> load_elements()

    {:ok, socket}
  end

  def handle_event("generate_missing_for_element", %{"id" => element_id}, socket) do
    case RequiredElementDB.get(element_id) do
      {:ok, element} ->
        all_codes = ReportGeneratorDomainManger.get_syllabi_codes()
        ReportGeneratorDomainManger.generate_async_all_missing(element, all_codes)
        {:noreply, put_flash(socket, :info, "Queued generation for missing syllabi.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Element not found.")}
    end
  end

  def handle_event("regenerate_unmet_for_element", %{"id" => element_id}, socket) do
    case RequiredElementDB.get(element_id) do
      {:ok, element} ->
        ReportGeneratorDomainManger.generate_async_all_unmet(element, nil)

        {:noreply,
         put_flash(socket, :info, "Queued regeneration for unmet/partially met syllabi.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Element not found.")}
    end
  end

  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, editing: :new, form_errors: %{})}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case RequiredElementDB.get(id) do
      {:ok, element} -> {:noreply, assign(socket, editing: element, form_errors: %{})}
      _ -> {:noreply, put_flash(socket, :error, "Element not found.")}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, editing: nil, form_errors: %{})}
  end

  def handle_event("save", %{"element" => attrs}, socket) do
    result =
      case socket.assigns.editing do
        :new -> RequiredElementDB.create(attrs)
        element -> RequiredElementDB.update(element["id"], attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(editing: nil, form_errors: %{})
         |> load_elements()
         |> put_flash(:info, "Saved.")}

      {:error, {:validation, errors}} ->
        {:noreply, assign(socket, :form_errors, format_errors(errors))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Database error. Please try again.")}
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete, id)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case RequiredElementDB.delete(id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:confirm_delete, nil)
         |> assign(:expanded_id, nil)
         |> assign(:instructions, [])
         |> load_elements()
         |> put_flash(:info, "Deleted.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:confirm_delete, nil)
         |> put_flash(:error, "Could not delete element.")}
    end
  end

  def handle_event("toggle_requirements", %{"id" => id}, socket) do
    if socket.assigns.expanded_id == id do
      {:noreply,
       assign(socket,
         expanded_id: nil,
         instructions: [],
         element_counts: nil,
         editing_instruction: nil,
         instruction_errors: %{},
         confirm_delete_instruction: nil
       )}
    else
      socket =
        socket
        |> load_instructions(id)
        |> load_element_counts(id)
        |> subscribe_element_coverage(id)

      {:noreply,
       assign(socket,
         expanded_id: id,
         editing_instruction: nil,
         instruction_errors: %{},
         confirm_delete_instruction: nil
       )}
    end
  end

  def handle_event("new_req", _params, socket) do
    {:noreply, assign(socket, editing_instruction: :new, instruction_errors: %{})}
  end

  def handle_event("edit_req", %{"id" => id}, socket) do
    case ReportInstructionDB.get(id) do
      {:ok, req} -> {:noreply, assign(socket, editing_instruction: req, instruction_errors: %{})}
      _ -> {:noreply, put_flash(socket, :error, "Instruction not found.")}
    end
  end

  def handle_event("cancel_req", _params, socket) do
    {:noreply, assign(socket, editing_instruction: nil, instruction_errors: %{})}
  end

  def handle_event("save_req", %{"req" => attrs}, socket) do
    element_id = socket.assigns.expanded_id

    result =
      case socket.assigns.editing_instruction do
        :new -> ReportInstructionDB.create(element_id, attrs)
        req -> ReportInstructionDB.update(req["id"], attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(editing_instruction: nil, instruction_errors: %{})
         |> load_instructions(element_id)}

      {:error, {:validation, errors}} ->
        {:noreply, assign(socket, :instruction_errors, format_errors(errors))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Database error. Please try again.")}
    end
  end

  def handle_event("confirm_delete_req", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_instruction, id)}
  end

  def handle_event("cancel_delete_req", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_instruction, nil)}
  end

  def handle_event("delete_req", %{"id" => id}, socket) do
    element_id = socket.assigns.expanded_id

    case ReportInstructionDB.delete(id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:confirm_delete_instruction, nil)
         |> load_instructions(element_id)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:confirm_delete_instruction, nil)
         |> put_flash(:error, "Could not delete instruction.")}
    end
  end

  defp load_elements(socket) do
    case RequiredElementDB.list_all() do
      {:ok, elements} -> assign(socket, :elements, elements)
      {:error, _} -> assign(socket, :elements, [])
    end
  end

  def handle_info({:element_coverage_updated, element_id, counts}, socket) do
    socket =
      if socket.assigns.expanded_id == element_id do
        assign(socket, :element_counts, counts)
      else
        socket
      end

    {:noreply, socket}
  end

  defp load_instructions(socket, element_id) do
    case ReportInstructionDB.list_for_element(element_id) do
      {:ok, items} -> assign(socket, :instructions, items)
      {:error, _} -> assign(socket, :instructions, [])
    end
  end

  defp load_element_counts(socket, element_id) do
    counts = ReportGeneratorDomainManger.get_element_coverage(element_id)
    assign(socket, :element_counts, counts)
  end

  defp subscribe_element_coverage(socket, element_id) do
    ReportGeneratorDomainManger.subscribe_element_coverage(element_id)
    socket
  end

  defp format_errors(errors) when is_list(errors) do
    Map.new(errors, fn {field, msg} -> {to_string(field), msg} end)
  end

  def render(assigns) do
    ~H"""
    <div class="w-6xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-xl font-semibold text-slate-100">Required Elements</h1>
        </div>
        <button
          id="new-element-btn"
          type="button"
          phx-click="new"
          class="inline-flex items-center gap-1.5 px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-slate-50 text-sm font-medium rounded-lg transition-colors"
        >
          <span class="hero-plus size-4" /> New Element
        </button>
      </div>

      <% selected = Enum.find(@elements, &(&1["id"] == @expanded_id)) %>
      <div class="flex gap-5 items-start h-[calc(100vh-10rem)] min-h-0">
        <.elements_list elements={@elements} expanded_id={@expanded_id} />
        <.element_detail
          selected={selected}
          editing={@editing}
          form_errors={@form_errors}
          confirm_delete={@confirm_delete}
          instructions={@instructions}
          editing_instruction={@editing_instruction}
          instruction_errors={@instruction_errors}
          confirm_delete_instruction={@confirm_delete_instruction}
          element_counts={@element_counts}
        />
      </div>
    </div>
    """
  end
end
