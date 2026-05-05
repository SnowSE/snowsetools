defmodule SimpleSyllabusReporterWeb.Reports.ElementDetail do
  use SimpleSyllabusReporterWeb, :html

  import SimpleSyllabusReporterWeb.Reports.ElementForm
  import SimpleSyllabusReporterWeb.Reports.RequirementsPanel

  attr :selected, :any, required: true
  attr :editing, :any, required: true
  attr :form_errors, :map, required: true
  attr :confirm_delete, :any, required: true
  attr :instructions, :list, required: true
  attr :editing_instruction, :any, required: true
  attr :instruction_errors, :map, required: true
  attr :confirm_delete_instruction, :any, required: true

  def element_detail(assigns) do
    ~H"""
    <div class="w-0 flex-1">
      <%= cond do %>
        <% @editing != nil -> %>
          <.element_form editing={@editing} form_errors={@form_errors} />
        <% @selected != nil -> %>
          <div class="rounded-xl border border-slate-800 bg-slate-900/40 px-6 py-5 mb-4">
            <div class="flex items-start justify-between gap-4">
              <div class="min-w-0">
                <h2 class="text-lg font-semibold text-slate-100">{@selected["name"]}</h2>
                <%= if @selected["description"] && @selected["description"] != "" do %>
                  <p class="text-slate-400 text-sm mt-1">{@selected["description"]}</p>
                <% else %>
                  <p class="text-slate-600 text-sm mt-1 italic">No description.</p>
                <% end %>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <button
                  id={"detail-edit-#{@selected["id"]}"}
                  type="button"
                  phx-click="edit"
                  phx-value-id={@selected["id"]}
                  class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-slate-300 hover:text-white border border-slate-700 hover:border-slate-500 rounded-lg transition-colors"
                >
                  <span class="hero-pencil-square size-4" /> Edit
                </button>
                <%= if @confirm_delete == @selected["id"] do %>
                  <span class="text-xs text-red-400">Delete?</span>
                  <button
                    id={"detail-confirm-del-#{@selected["id"]}"}
                    type="button"
                    phx-click="delete"
                    phx-value-id={@selected["id"]}
                    class="px-3 py-1.5 text-xs font-medium text-red-400 hover:text-red-300 border border-red-900 hover:border-red-700 rounded-lg transition-colors"
                  >
                    Yes, delete
                  </button>
                  <button
                    id={"detail-cancel-del-#{@selected["id"]}"}
                    type="button"
                    phx-click="cancel_delete"
                    class="px-3 py-1.5 text-xs text-slate-400 hover:text-slate-200 border border-slate-700 rounded-lg transition-colors"
                  >
                    Cancel
                  </button>
                <% else %>
                  <button
                    id={"detail-delete-#{@selected["id"]}"}
                    type="button"
                    phx-click="confirm_delete"
                    phx-value-id={@selected["id"]}
                    class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-slate-500 hover:text-red-400 border border-slate-700 hover:border-red-900 rounded-lg transition-colors"
                  >
                    <span class="hero-trash size-4" /> Delete
                  </button>
                <% end %>
              </div>
            </div>
          </div>

          <div class="rounded-xl border border-slate-800 bg-slate-900/40 px-6 py-5">
            <.requirements_panel
              element={@selected}
              instructions={@instructions}
              editing_instruction={@editing_instruction}
              instruction_errors={@instruction_errors}
              confirm_delete_instruction={@confirm_delete_instruction}
            />
          </div>
        <% true -> %>
          <div
            id="detail-empty"
            class="flex items-center justify-center py-24 text-slate-600 text-sm"
          >
            Select an element to view details.
          </div>
      <% end %>
    </div>
    """
  end
end
