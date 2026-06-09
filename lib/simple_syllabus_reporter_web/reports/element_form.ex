defmodule SimpleSyllabusReporterWeb.Reports.ElementForm do
  use SimpleSyllabusReporterWeb, :html

  attr :editing, :any, required: true
  attr :form_errors, :map, required: true

  def element_form(assigns) do
    element = if assigns.editing == :new, do: %{}, else: assigns.editing

    assigns =
      assigns
      |> assign(:element, element)
      |> assign(
        :title,
        if(assigns.editing == :new, do: "New Required Element", else: "Edit Element")
      )

    ~H"""
    <div
      id="element-form-panel"
      class="mb-6 rounded-xl border border-slate-700 bg-slate-900/60 p-5"
    >
      <h2 class="text-sm font-semibold text-slate-200 mb-4">{@title}</h2>

      <form id="element-form" phx-submit="save">
        <div class="grid grid-cols-1 gap-4">
          <%!-- Name --%>
          <div>
            <label for="element_name" class="block text-xs text-slate-400 mb-1">
              Name <span class="text-red-400">*</span>
            </label>
            <input
              id="element_name"
              type="text"
              name="element[name]"
              value={@element["name"] || ""}
              placeholder="e.g. Course Student Learning Outcomes"
              class={[
                "w-full bg-slate-800 border text-slate-100 placeholder-slate-500 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 transition",
                if(@form_errors["name"], do: "border-red-500", else: "border-slate-700")
              ]}
            />
            <p :if={@form_errors["name"]} class="mt-1 text-xs text-red-400">
              {@form_errors["name"]}
            </p>
          </div>

          <%!-- Description --%>
          <div>
            <label for="element_description" class="block text-xs text-slate-400 mb-1">
              Description
            </label>
            <textarea
              id="element_description"
              name="element[description]"
              rows="2"
              placeholder="What this element should contain…"
              class="w-full bg-slate-800 border border-slate-700 text-slate-100 placeholder-slate-500 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 transition resize-none"
            >{@element["description"] || ""}</textarea>
          </div>
        </div>

        <div class="flex items-center gap-3 mt-5">
          <button
            type="submit"
            id="element-save-btn"
            class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-slate-50 text-sm font-medium rounded-lg transition-colors"
          >
            Save
          </button>
          <button
            type="button"
            id="element-cancel-btn"
            phx-click="cancel"
            class="px-4 py-2 text-slate-400 hover:text-slate-100 text-sm transition-colors"
          >
            Cancel
          </button>
        </div>
      </form>
    </div>
    """
  end
end
