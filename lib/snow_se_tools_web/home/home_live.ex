defmodule SnowSeToolsWeb.Home.HomeLive do
  use SnowSeToolsWeb, :live_view

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Home")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="flex flex-col items-center justify-center py-24 text-center px-4">
        <div class="max-w-lg space-y-4">
          <p class="text-sm uppercase tracking-[0.3em] text-slate-500">Welcome</p>
          <h1 class="text-3xl font-bold text-slate-100">
            Welcome back<%= if @current_user do %>
              , {@current_user.email}
            <% end %>.
          </h1>
          <p class="text-sm text-slate-400">
            Use the Syllabi section to search, review, and inspect school overviews.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
