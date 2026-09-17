defmodule SnowSeToolsWeb.AppHeader do
  use SnowSeToolsWeb, :html

  alias SnowSeTools.Data.Access

  attr :current_user, :map, default: nil
  attr :current_path, :string, default: nil
  slot :center

  def header(assigns) do
    ~H"""
    <header class="shrink-0 flex items-center justify-between gap-2 px-3 h-10 border-b border-slate-800 bg-slate-900/80 backdrop-blur-sm">
      <div class="flex shrink-0 items-center">
        <.link
          navigate={if @current_user, do: ~p"/home", else: ~p"/"}
          class="text-sm font-semibold text-slate-200 hover:text-white transition-colors"
        >
          <span class="hidden sm:inline">Snow SE Tools</span>
          <span class="sm:hidden">SE Tools</span>
        </.link>
      </div>

      <div class="hidden min-w-0 md:flex md:items-center">
        {render_slot(@center)}
      </div>

      <nav class="flex min-w-0 flex-1 items-center gap-1 justify-end overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden sm:gap-2">
        <%= if @current_user do %>
          <.link
            navigate={~p"/home"}
            class={nav_link_class(@current_path, ~p"/home")}
          >
            Home
          </.link>
          <.link
            :if={Access.can?(@current_user, :syllabi)}
            navigate={~p"/syllabi"}
            class={nav_link_class(@current_path, ~p"/syllabi")}
          >
            Syllabi
          </.link>
          <.link
            :if={Access.can?(@current_user, :scheduling)}
            navigate={~p"/scheduling"}
            class={nav_link_class(@current_path, ~p"/scheduling")}
          >
            Scheduling
          </.link>
          <.link
            :if={Access.can?(@current_user, :discord)}
            navigate={~p"/discord"}
            class={nav_link_class(@current_path, ~p"/discord")}
          >
            Discord
          </.link>
          <.link
            :if={Access.admin?(@current_user)}
            navigate={~p"/admin"}
            class={nav_link_class(@current_path, ~p"/admin")}
          >
            Admin
          </.link>

          <span
            class="hidden shrink-0 items-center gap-2 px-3 py-1.5 text-sm text-slate-300 lg:flex"
            title={@current_user.email}
          >
            <.icon name="hero-user-circle" class="size-4" />
            <span class="max-w-[16rem] truncate">{@current_user.email}</span>
          </span>
          <.link
            href={~p"/auth/logout"}
            class="shrink-0 rounded-lg px-2 py-1.5 text-sm text-slate-400 transition-all hover:bg-slate-800 hover:text-white sm:px-3"
            title={@current_user.email}
          >
            <span class="hidden sm:inline">Logout</span>
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-4 sm:hidden" />
          </.link>
        <% else %>
          <.link
            href={~p"/auth/login"}
            class="rounded-lg px-3 py-1.5 text-sm text-slate-200 hover:bg-slate-800 hover:text-white transition-all"
          >
            Login
          </.link>
        <% end %>
      </nav>
    </header>
    """
  end

  defp nav_link_class(current_path, path) do
    active =
      is_binary(current_path) and
        (current_path == path or String.starts_with?(current_path, path <> "/"))

    [
      "shrink-0 whitespace-nowrap px-2 py-1.5 text-sm transition-all sm:px-3",
      if(active,
        do: "text-purple-300 border-purple-500 border-b-2",
        else: "text-slate-400 hover:bg-slate-800 hover:text-white"
      )
    ]
  end
end
