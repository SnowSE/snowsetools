defmodule SimpleSyllabusReporterWeb.Syllabus.SearchQuickNavigation do
  use SimpleSyllabusReporterWeb, :html

  attr :departments, :list, default: []
  attr :current_user, :map, required: true
  attr :active_query, :string, default: ""

  def quick_navigation(assigns) do
    assigns = assign(assigns, :divisions, Enum.filter(assigns.departments, &(&1["level"] == 2)))

    ~H"""
    <div class="flex flex-wrap gap-2 pb-2">
      <button
        id="quick-nav-my-syllabi"
        phx-click="quick_nav"
        phx-value-type="my_syllabi"
        class={[
          "px-3 py-1 rounded-full text-xs font-medium border transition-colors",
          if(@active_query == @current_user.email,
            do: "bg-indigo-600 border-indigo-500 text-white",
            else:
              "bg-slate-800 border-slate-700 text-slate-300 hover:border-indigo-500 hover:text-indigo-300"
          )
        ]}
      >
        My Syllabi
      </button>
      <%= for division <- @divisions do %>
        <button
          id={"quick-nav-#{division["entity_id"]}"}
          phx-click="quick_nav"
          phx-value-type="division"
          phx-value-name={division["name"]}
          phx-value-org-id={division["entity_id"]}
          class={[
            "px-3 py-1 rounded-full text-xs font-medium border transition-colors",
            if(@active_query == division["name"],
              do: "bg-indigo-600 border-indigo-500 text-white",
              else:
                "bg-slate-800 border-slate-700 text-slate-300 hover:border-indigo-500 hover:text-indigo-300"
            )
          ]}
        >
          {division["name"]}
        </button>
      <% end %>
    </div>
    """
  end
end
