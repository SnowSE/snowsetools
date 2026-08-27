defmodule SnowSeToolsWeb.Auth.PendingLive do
  @moduledoc """
  Landing page for users who have logged in but have not been added to any
  access group yet.
  """
  use SnowSeToolsWeb, :live_view

  alias SnowSeTools.Data.Access

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_session}

  def mount(_params, _session, socket) do
    if Access.approved?(socket.assigns.current_user) do
      {:ok, redirect(socket, to: ~p"/home")}
    else
      {:ok, assign(socket, :page_title, "Awaiting approval")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="flex flex-col items-center justify-center py-24 px-4 text-center">
        <div class="max-w-lg space-y-5 rounded-2xl border border-slate-800 bg-slate-900/70 p-8 shadow-xl shadow-slate-950/20">
          <span class="inline-flex items-center gap-2 rounded-full bg-amber-500/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-amber-300">
            <.icon name="hero-clock" class="size-4" /> Awaiting approval
          </span>
          <h1 class="text-2xl font-semibold text-slate-100">Your account needs to be approved</h1>
          <p class="text-sm leading-6 text-slate-300">
            You are signed in as <span class="font-medium text-slate-100">{@current_user.email}</span>,
            but this account has not been given access to any tools yet.
          </p>
          <p class="text-sm leading-6 text-slate-300">
            Please contact <span class="font-medium text-slate-100">Jonathan Allen</span>
            to have your account approved. Once you have been added to a group, reload this page.
          </p>
          <div class="flex justify-center gap-3 pt-2">
            <.link
              navigate={~p"/pending"}
              class="rounded-xl bg-indigo-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-400"
            >
              Check again
            </.link>
            <.link
              href={~p"/auth/logout"}
              class="rounded-xl border border-slate-700 px-4 py-2.5 text-sm font-semibold text-slate-300 transition hover:bg-slate-800"
            >
              Log out
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
