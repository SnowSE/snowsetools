defmodule SimpleSyllabusReporterWeb.Reports.RequiredElementsLive do
  use SimpleSyllabusReporterWeb, :live_view

  alias SimpleSyllabusReporter.Reports.RequiredElement
  alias SimpleSyllabusReporter.Reports.ReportInstruction

  import SimpleSyllabusReporterWeb.Reports.ElementsList
  import SimpleSyllabusReporterWeb.Reports.ElementDetail

  on_mount {SimpleSyllabusReporterWeb.UserAuth, :ensure_authenticated}

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
      |> load_elements()

    {:ok, socket}
  end

  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, editing: :new, form_errors: %{})}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case RequiredElement.get(id) do
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
        :new -> RequiredElement.create(attrs)
        element -> RequiredElement.update(element["id"], attrs)
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
    case RequiredElement.delete(id) do
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
         editing_instruction: nil,
         instruction_errors: %{},
         confirm_delete_instruction: nil
       )}
    else
      socket = load_instructions(socket, id)

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
    case ReportInstruction.get(id) do
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
        :new -> ReportInstruction.create(element_id, attrs)
        req -> ReportInstruction.update(req["id"], attrs)
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

    case ReportInstruction.delete(id) do
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
    case RequiredElement.list_all() do
      {:ok, elements} -> assign(socket, :elements, elements)
      {:error, _} -> assign(socket, :elements, [])
    end
  end

  defp load_instructions(socket, element_id) do
    case ReportInstruction.list_for_element(element_id) do
      {:ok, items} -> assign(socket, :instructions, items)
      {:error, _} -> assign(socket, :instructions, [])
    end
  end

  defp format_errors(errors) when is_list(errors) do
    Map.new(errors, fn {field, msg} -> {to_string(field), msg} end)
  end

  defp format_errors(errors), do: %{"base" => inspect(errors)}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} socket={@socket}>
      <div class="w-6xl mx-auto px-4 py-8">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-xl font-semibold text-slate-100">Required Elements</h1>
          </div>
          <button
            id="new-element-btn"
            type="button"
            phx-click="new"
            class="inline-flex items-center gap-1.5 px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium rounded-lg transition-colors"
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
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
