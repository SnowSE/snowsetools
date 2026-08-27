defmodule SnowSeToolsWeb.Home.HomeLive do
  use SnowSeToolsWeb, :live_view

  alias SnowSeTools.Data.Access

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Home")
     |> assign(:areas, Access.accessible_areas(socket.assigns.current_user))
     |> assign(:admin?, Access.admin?(socket.assigns.current_user))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="mx-auto max-w-4xl px-4 py-16">
        <div class="space-y-3 text-center">
          <p class="text-sm uppercase tracking-[0.3em] text-slate-500">Welcome</p>
          <h1 class="text-3xl font-bold text-slate-100">Welcome back, {@current_user.email}.</h1>
          <p class="text-sm text-slate-400">These are the tools your account has access to.</p>
        </div>

        <div class="mt-10 grid gap-4 sm:grid-cols-2">
          <.link
            :for={area <- @areas}
            navigate={area_path(area.area)}
            class="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 transition hover:border-indigo-500/60 hover:bg-slate-900"
          >
            <h2 class="text-lg font-semibold text-slate-100">{area.label}</h2>
            <p class="mt-2 text-sm leading-6 text-slate-400">{area.description}</p>
          </.link>
          <.link
            :if={@admin?}
            navigate={~p"/admin"}
            class="rounded-2xl border border-emerald-500/30 bg-emerald-500/5 p-5 transition hover:border-emerald-400/60"
          >
            <h2 class="text-lg font-semibold text-emerald-200">Admin</h2>
            <p class="mt-2 text-sm leading-6 text-slate-400">
              Approve new accounts and manage who can use each tool.
            </p>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp area_path(:syllabi), do: ~p"/syllabi"
  defp area_path(:scheduling), do: ~p"/scheduling"
  defp area_path(:discord), do: ~p"/discord"
end
