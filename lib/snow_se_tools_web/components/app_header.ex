defmodule SnowSeToolsWeb.AppHeader do
  use SnowSeToolsWeb, :html

  alias SnowSeTools.Data.AccessControl

  attr :current_user, :map, default: nil
  attr :current_path, :string, default: nil
  slot :center

  def header(assigns) do
    ~H"""
    <header class="shrink-0 flex justify-between px-3 h-10 border-b border-slate-800 bg-slate-900/80 backdrop-blur-sm">
      <div class="flex items-center">
        <.link
          navigate={if @current_user, do: ~p"/home", else: ~p"/"}
          class="text-sm font-semibold text-slate-200 hover:text-white transition-colors"
        >
          Snow SE Tools
        </.link>
      </div>

      {render_slot(@center)}

      <nav class="flex items-center gap-2 justify-end">
        <%= if @current_user do %>
          <.link
            navigate={~p"/home"}
            class={nav_link_class(@current_path, ~p"/home")}
          >
            Home
          </.link>
          <.link
            navigate={~p"/syllabi"}
            class={nav_link_class(@current_path, ~p"/syllabi")}
          >
            Syllabi
          </.link>
          <%= if admin_user?(@current_user) do %>
            <.link
              navigate={~p"/admin"}
              class={nav_link_class(@current_path, ~p"/admin")}
            >
              Admin
            </.link>
          <% end %>

          <span class="flex items-center gap-2 px-3 py-1.5 text-sm text-slate-300">
            <.icon name="hero-user-circle" class="size-4" />
            {@current_user.email}
          </span>
          <.link
            href={~p"/auth/logout"}
            class="rounded-lg px-3 py-1.5 text-sm text-slate-400 hover:bg-slate-800 hover:text-white transition-all"
          >
            Logout
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
      " px-3 py-1.5 transition-all",
      if(active,
        do: "text-purple-300 border-purple-500 border-b-2",
        else: "text-slate-400 hover:bg-slate-800 hover:text-white"
      )
    ]
  end

  defp admin_user?(%{id: user_id}) when is_binary(user_id) do
    AccessControl.user_has_group?(user_id: user_id, group_name: "admin")
  end

  defp admin_user?(%{"id" => user_id}) when is_binary(user_id) do
    AccessControl.user_has_group?(user_id: user_id, group_name: "admin")
  end

  defp admin_user?(_), do: false
end
