defmodule SimpleSyllabusReporterWeb.Reports.ElementsList do
  use SimpleSyllabusReporterWeb, :html

  attr :elements, :list, required: true
  attr :expanded_id, :any, required: true

  def elements_list(assigns) do
    ~H"""
    <div class="w-64 shrink-0 overflow-y-auto h-full space-y-2 pr-1">
      <div
        :if={@elements == []}
        id="elements-empty"
        class="text-slate-500 text-sm text-center py-12"
      >
        No elements yet.
      </div>
      <%= for element <- @elements do %>
        <button
          id={"card-#{element["id"]}"}
          type="button"
          phx-click="toggle_requirements"
          phx-value-id={element["id"]}
          class={[
            "w-full text-left px-4 py-3 rounded-xl border transition-all cursor-pointer ",
            if(@expanded_id == element["id"],
              do: "bg-indigo-600/15 border-indigo-500/50 ring-1 ring-indigo-500/20 shadow-sm",
              else: "bg-slate-900/60 border-slate-700/60 hover:border-slate-500 hover:bg-slate-900"
            )
          ]}
        >
          <div class={[
            "text-sm font-medium leading-snug",
            if(@expanded_id == element["id"], do: "text-indigo-200", else: "text-slate-100")
          ]}>
            {element["name"]}
          </div>
          <div
            :if={element["description"] && element["description"] != ""}
            class="text-slate-500 text-xs mt-0.5 line-clamp-2"
          >
            {element["description"]}
          </div>
        </button>
      <% end %>
    </div>
    """
  end
end
