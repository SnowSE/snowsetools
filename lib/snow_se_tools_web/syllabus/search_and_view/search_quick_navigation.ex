defmodule SnowSeToolsWeb.Syllabus.SearchQuickNavigation do
  import Phoenix.LiveView
  import Phoenix.Component

  alias SnowSeTools.Syllabi.SyllabusDomainManager

  defstruct [:key, :departments, :divisions, :active_query, :current_user]

  def assign_component(socket, key, opts \\ []) do
    state = %__MODULE__{
      key: key,
      departments: [],
      divisions: [],
      active_query: opts[:active_query] || "",
      current_user: opts[:current_user]
    }

    socket
    |> assign(key, state)
    |> maybe_attach_hooks()
    |> start_departments_fetch(key)
  end

  def push_update(socket, key, opts) do
    active_query = opts[:active_query] || ""
    current_user = opts[:current_user]

    Phoenix.Component.update(socket, key, fn state ->
      %{state | active_query: active_query, current_user: current_user}
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2 pb-2">
      <button
        id="quick-nav-my-syllabi"
        phx-click="quick_nav"
        phx-value-type="my_syllabi"
        phx-value-sqn_key={@state.key}
        class={[
          "px-3 py-1 rounded-full text-xs font-medium border transition-colors",
          if(@state.active_query == @state.current_user.email,
            do: "bg-indigo-600 border-indigo-500 text-white",
            else:
              "bg-slate-800 border-slate-700 text-slate-300 hover:border-indigo-500 hover:text-indigo-300"
          )
        ]}
      >
        My Syllabi
      </button>
      <%= for division <- @state.divisions do %>
        <button
          id={"quick-nav-#{division["entity_id"]}"}
          phx-click="quick_nav"
          phx-value-type="division"
          phx-value-name={division["name"]}
          phx-value-sqn_key={@state.key}
          class={[
            "px-3 py-1 rounded-full text-xs font-medium border transition-colors",
            if(@state.active_query == division["name"],
              do: "bg-indigo-600 border-indigo-500 text-slate-50",
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

  def hooked_event(
        "quick_nav",
        %{"type" => "division", "name" => name, "sqn_key" => key},
        socket
      ) do
    key = String.to_existing_atom(key)

    socket =
      update(socket, key, fn state ->
        %{state | active_query: name}
      end)

    send(self(), {:quick_nav, name})
    {:halt, socket}
  end

  def hooked_event(
        "quick_nav",
        %{"type" => "my_syllabi", "sqn_key" => key},
        socket
      ) do
    key = String.to_existing_atom(key)
    state = socket.assigns[key]

    socket =
      update(socket, key, fn s ->
        %{s | active_query: state.current_user.email}
      end)

    send(self(), {:quick_nav, state.current_user.email})
    {:halt, socket}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  def hooked_async({:fetch_departments, key}, {:ok, {:ok, departments}}, socket) do
    divisions = Enum.filter(departments, &(&1["level"] == 2))

    socket =
      update(socket, key, fn state ->
        %{state | departments: departments, divisions: divisions}
      end)

    {:halt, socket}
  end

  def hooked_async({:fetch_departments, _key}, _result, socket), do: {:halt, socket}

  defp maybe_attach_hooks(socket) do
    if first_instance?(socket) do
      socket
      |> attach_hook("sqn:event", :handle_event, &hooked_event/3)
      |> attach_hook("sqn:async", :handle_async, &hooked_async/3)
    else
      socket
    end
  end

  defp first_instance?(socket) do
    Enum.count(socket.assigns, fn {_, v} -> match?(%__MODULE__{}, v) end) == 1
  end

  defp start_departments_fetch(socket, key) do
    start_async(socket, {:fetch_departments, key}, fn ->
      SyllabusDomainManager.get_departments()
    end)
  end
end
