defmodule SimpleSyllabusReporterWeb.AppHeader do
  use SimpleSyllabusReporterWeb, :html

  attr :current_user, :map, default: nil
  attr :current_path, :string, default: nil
  slot :center

  def header(assigns) do
    ~H"""
    <header class="shrink-0 flex justify-between px-3 h-10 border-b border-slate-800 bg-slate-900/80 backdrop-blur-sm">
      <div class="flex items-center">
        <.link
          navigate={~p"/"}
          class="text-sm font-semibold text-slate-200 hover:text-white transition-colors"
        >
          Simple Syllabus Reporter
        </.link>
      </div>

      {render_slot(@center)}

      <nav class="flex items-center gap-2 justify-end">
        <%= if @current_user do %>
          <.link
            navigate={~p"/syllabi"}
            class={nav_link_class(@current_path, ~p"/syllabi")}
          >
            Syllabi
          </.link>
          <.link
            navigate={~p"/reports/required-elements"}
            class={nav_link_class(@current_path, ~p"/reports/required-elements")}
          >
            Required Elements
          </.link>
          <.link
            navigate={~p"/ai/completions"}
            class={nav_link_class(@current_path, ~p"/ai/completions")}
          >
            AI History
          </.link>
          <form action={~p"/cache/clear"} method="post" class="flex items-center">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <button
              type="submit"
              class="rounded-lg px-3 py-1.5 text-sm text-slate-400 hover:bg-slate-800 hover:text-amber-300 transition-all"
              title="Clear all cached data"
            >
              <.icon name="hero-arrow-path" class="size-4" />
            </button>
          </form>
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
    active = is_binary(current_path) and String.starts_with?(current_path, path)

    [
      " px-3 py-1.5 transition-all",
      if(active,
        do: "text-purple-300 border-purple-500 border-b-2",
        else: "text-slate-400 hover:bg-slate-800 hover:text-white"
      )
    ]
  end
end
