defmodule SnowSeToolsWeb.Discord.DiscordLive do
  use SnowSeToolsWeb, :live_view

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Discord")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <main id="discord-page" class="mx-auto flex w-full max-w-6xl flex-col gap-6 px-4 py-8">
        <section class="flex flex-col gap-2">
          <p class="text-sm font-medium uppercase tracking-[0.22em] text-indigo-300">Discord</p>
          <h1 class="text-3xl font-semibold text-slate-100">Discord</h1>
          <p class="max-w-2xl text-sm leading-6 text-slate-400">
            Discord tools and workflows will live here.
          </p>
        </section>
      </main>
    </Layouts.app>
    """
  end
end
