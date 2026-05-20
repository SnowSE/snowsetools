defmodule SimpleSyllabusReporterWeb.Syllabus.SearchQuickNavigation do
  use SimpleSyllabusReporterWeb, :live_component

  alias SimpleSyllabusReporter.Syllabi.SyllabusManager

  def mount(socket) do
    socket =
      if connected?(socket) do
        start_async(socket, :fetch_departments, fn -> SyllabusManager.get_departments() end)
      else
        socket
      end

    {:ok,
     socket
     |> assign(:departments, [])
     |> assign(:divisions, [])}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(:current_user, assigns.current_user)
     |> assign(:active_query, assigns.active_query)}
  end

  def handle_async(:fetch_departments, {:ok, {:ok, departments}}, socket) do
    divisions = Enum.filter(departments, &(&1["level"] == 2))
    {:noreply, socket |> assign(:departments, departments) |> assign(:divisions, divisions)}
  end

  def handle_async(:fetch_departments, _result, socket), do: {:noreply, socket}

  def handle_event("quick_nav", %{"type" => "division", "name" => name}, socket) do
    send(self(), {:quick_nav, name})
    {:noreply, socket}
  end

  def handle_event("quick_nav", %{"type" => "my_syllabi"}, socket) do
    send(self(), {:quick_nav, socket.assigns.current_user.email})
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2 pb-2">
      <button
        id="quick-nav-my-syllabi"
        phx-click="quick_nav"
        phx-value-type="my_syllabi"
        phx-target={@myself}
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
          phx-target={@myself}
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
