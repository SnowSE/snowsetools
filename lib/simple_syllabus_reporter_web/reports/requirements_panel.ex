defmodule SimpleSyllabusReporterWeb.Reports.RequirementsPanel do
  use SimpleSyllabusReporterWeb, :html

  attr :element, :map, required: true
  attr :instructions, :list, required: true
  attr :editing_instruction, :any, required: true
  attr :instruction_errors, :map, required: true
  attr :confirm_delete_instruction, :any, required: true

  def requirements_panel(assigns) do
    ~H"""
    <div id={"instructions-panel-#{@element["id"]}"}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-xs font-semibold text-violet-300 uppercase tracking-wider">
          AI Prompt Instructions
        </h3>
        <button
          :if={@editing_instruction == nil}
          id={"new-instruction-#{@element["id"]}"}
          type="button"
          phx-click="new_req"
          class="inline-flex items-center gap-1 text-xs text-violet-400 hover:text-violet-200 transition-colors"
        >
          <span class="hero-plus size-3.5" /> Add instruction
        </button>
      </div>

      <%= if @editing_instruction do %>
        <form id={"instruction-form-#{@element["id"]}"} phx-submit="save_req" class="mb-4">
          <div class="space-y-2">
            <textarea
              id={"instruction-content-#{@element["id"]}"}
              name="req[content]"
              rows="20"
              placeholder="e.g. A statement like 'No prerequisites required' counts as fulfilling this element."
              autofocus
              class={[
                "w-full bg-slate-800 border text-slate-100 placeholder-slate-500 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-violet-500 transition resize-none",
                if(@instruction_errors["content"], do: "border-red-500", else: "border-slate-700")
              ]}
            >{if @editing_instruction == :new, do: "", else: @editing_instruction["content"]}</textarea>
            <p :if={@instruction_errors["content"]} class="text-xs text-red-400">
              {@instruction_errors["content"]}
            </p>
          </div>
          <div class="flex gap-2 mt-2">
            <button
              type="submit"
              id={"instruction-save-btn-#{@element["id"]}"}
              class="px-3 py-1.5 bg-violet-600 hover:bg-violet-500 text-white text-xs font-medium rounded-lg transition-colors"
            >
              Save
            </button>
            <button
              type="button"
              id={"instruction-cancel-btn-#{@element["id"]}"}
              phx-click="cancel_req"
              class="px-3 py-1.5 text-slate-400 hover:text-slate-100 text-xs transition-colors"
            >
              Cancel
            </button>
          </div>
        </form>
      <% end %>

      <%!-- Instructions list --%>
      <%= if @instructions == [] and @editing_instruction == nil do %>
        <p class="text-xs text-slate-600 italic">
          No instructions yet. The AI will use only the element description when generating reports.
        </p>
      <% else %>
        <div class="space-y-2">
          <%= for instruction <- @instructions do %>
            <div
              id={"instruction-#{instruction["id"]}"}
              class="group flex items-start gap-3 bg-slate-900/60 border border-slate-700/60 rounded-lg px-3 py-2.5"
            >
              <p class="flex-1 text-xs text-slate-300 whitespace-pre-wrap">
                {instruction["content"]}
              </p>
              <div class="shrink-0 flex items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  id={"edit-instruction-#{instruction["id"]}"}
                  type="button"
                  phx-click="edit_req"
                  phx-value-id={instruction["id"]}
                  class="text-slate-500 hover:text-slate-200 transition-colors"
                  title="Edit"
                >
                  <span class="hero-pencil-square size-3.5" />
                </button>
                <%= if @confirm_delete_instruction == instruction["id"] do %>
                  <span class="text-xs text-red-400">Delete?</span>
                  <button
                    id={"confirm-del-instruction-#{instruction["id"]}"}
                    type="button"
                    phx-click="delete_req"
                    phx-value-id={instruction["id"]}
                    class="text-red-400 hover:text-red-300 text-xs font-medium transition-colors"
                  >
                    Yes
                  </button>
                  <button
                    id={"cancel-del-instruction-#{instruction["id"]}"}
                    type="button"
                    phx-click="cancel_delete_req"
                    class="text-slate-500 hover:text-slate-200 text-xs transition-colors"
                  >
                    No
                  </button>
                <% else %>
                  <button
                    id={"del-instruction-#{instruction["id"]}"}
                    type="button"
                    phx-click="confirm_delete_req"
                    phx-value-id={instruction["id"]}
                    class="text-slate-600 hover:text-red-400 transition-colors"
                    title="Delete"
                  >
                    <span class="hero-trash size-3.5" />
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
