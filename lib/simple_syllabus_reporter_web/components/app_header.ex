defmodule SimpleSyllabusReporterWeb.AppHeader do
  use SimpleSyllabusReporterWeb, :html

  attr :current_user, :map, default: nil

  def header(assigns) do
    ~H"""
    <header class="shrink-0 flex items-center justify-between px-3 h-10 border-b border-slate-800 bg-slate-900/80 backdrop-blur-sm">
      <.link
        navigate={~p"/"}
        class="text-sm font-semibold text-slate-200 hover:text-white transition-colors"
      >
        Simple Syllabus Reporter
      </.link>

      <nav class="flex items-center gap-2">
        <%= if @current_user do %>
          <.link
            navigate={~p"/syllabi"}
            class="rounded-lg px-3 py-1.5 text-sm text-slate-400 hover:bg-slate-800 hover:text-white transition-all"
          >
            Syllabi
          </.link>
          <.link
            navigate={~p"/reports/required-elements"}
            class="rounded-lg px-3 py-1.5 text-sm text-slate-400 hover:bg-slate-800 hover:text-white transition-all"
          >
            Required Elements
          </.link>
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
end
