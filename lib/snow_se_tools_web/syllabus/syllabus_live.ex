defmodule SnowSeToolsWeb.Syllabus.SyllabusLive do
  use SnowSeToolsWeb, :live_view
  require Logger

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "Syllabus Search")
      |> assign(:session_id, session["current_user_id"])
      |> assign(:mode, :search)
      |> assign(:search_live_pid, nil)
      |> assign(:search_params, %{})
      |> assign(:modes,
        search: "Search Syllabi",
        required_elements: "Required Elements",
        ai_history: "AI History",
        settings: "Settings"
      )

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    query = params["q"] || ""

    if search_live = socket.assigns.search_live_pid do
      send(search_live, {:navigate_params, params})
    end

    {:noreply, socket |> assign(:query, query) |> assign(:search_params, params)}
  end

  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    {:noreply, assign(socket, :mode, mode_atom)}
  end

  def handle_info({:search_navigate, query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/syllabi?q=#{query}")}
  end

  def handle_info({:syllabus_search_live_ready, pid}, socket) when is_pid(pid) do
    send(pid, {:navigate_params, socket.assigns.search_params})
    {:noreply, assign(socket, :search_live_pid, pid)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="flex flex-col h-full min-h-0">
        <div class="border-b border-slate-700/60 shrink-0">
          <div class="max-w-[2000px] mx-auto w-full flex items-center gap-1 px-4">
            <%= for {mode_key, label} <- @modes do %>
              <button
                id={"tab-#{mode_key}"}
                type="button"
                phx-click="switch_mode"
                phx-value-mode={mode_key}
                class={[
                  "px-4 py-2.5 text-sm font-medium border-b-2 transition-colors cursor-pointer",
                  @mode == mode_key &&
                    "text-indigo-300 border-indigo-400",
                  @mode != mode_key &&
                    "text-slate-400 border-transparent hover:text-slate-200 hover:border-slate-500"
                ]}
              >
                {label}
              </button>
            <% end %>
          </div>
        </div>

        <div class="flex-1 min-h-0">
          <%= case @mode do %>
            <% :search -> %>
              {live_render(@socket, SnowSeToolsWeb.Syllabus.SyllabusSearchLive,
                id: "syllabus-search",
                session: %{
                  "current_user_id" => @session_id,
                  "parent_pid" => self() |> :erlang.pid_to_list() |> to_string()
                }
              )}
            <% :required_elements -> %>
              {live_render(@socket, SnowSeToolsWeb.Reports.RequiredElementsLive,
                id: "required-elements",
                session: %{"current_user_id" => @session_id}
              )}
            <% :ai_history -> %>
              {live_render(@socket, SnowSeToolsWeb.AI.CompletionsHistoryLive,
                id: "ai-history",
                session: %{"current_user_id" => @session_id}
              )}
            <% :settings -> %>
              {live_render(@socket, SnowSeToolsWeb.Config.SimpleSyllabusConfig,
                id: "settings",
                session: %{"current_user_id" => @session_id}
              )}
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
