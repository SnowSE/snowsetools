defmodule SnowSeToolsWeb.Discord.DiscordInvites do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeToolsWeb.Discord.DiscordFormatting

  defstruct key: nil,
            invites: [],
            loading?: true,
            error: nil

  def assign_component(socket, key) do
    socket
    |> assign_new(key, fn -> %__MODULE__{key: key} end)
    |> maybe_attach_hooks()
    |> request_invites(key: key)
  end

  attr :state, __MODULE__, required: true

  def render(assigns) do
    assigns = assign(assigns, :invites, active_invites(assigns.state.invites))

    ~H"""
    <div id="discord-invites" class="flex flex-col gap-2">
      <div
        :if={@state.error}
        class="rounded-md border border-rose-500/30 bg-rose-500/10 p-3 text-sm text-rose-200"
      >
        {@state.error}
      </div>
      <div class="hidden rounded-md border border-slate-800 bg-slate-950/50 p-6 text-sm text-slate-400 only:block">
        No Discord invites have been synced yet.
      </div>
      <article
        :for={invite <- @invites}
        id={"discord-invite-#{invite["id"]}"}
        class="rounded-md border border-slate-800 bg-slate-950/40 p-3"
      >
        <div class="flex flex-wrap items-center gap-2">
          <span class="font-mono text-sm text-indigo-200">{DiscordFormatting.invite_url(invite)}</span>
          <span class="rounded-full bg-slate-800 px-2 py-0.5 text-xs text-slate-400">
            #{DiscordFormatting.invite_channel_name(invite)}
          </span>
        </div>
      </article>
    </div>
    """
  end

  attr :state, __MODULE__, required: true

  def side_panel(assigns) do
    assigns = assign(assigns, :invites, active_invites(assigns.state.invites))

    ~H"""
    <section id="discord-invite-panel" class="rounded-md border border-slate-800 bg-slate-950/50 p-4">
      <h2 class="text-sm font-semibold text-slate-100">Server Invites</h2>
      <p :if={@state.error} class="mt-2 text-sm text-rose-200">{@state.error}</p>
      <div class="mt-3 flex flex-col gap-2">
        <p :if={@invites == []} class="text-sm text-slate-500">No active invites are cached.</p>
        <div
          :for={invite <- Enum.take(@invites, 4)}
          class="rounded-md border border-slate-800 bg-slate-900/50 px-3 py-2"
        >
          <p class="truncate font-mono text-xs text-indigo-200">
            {DiscordFormatting.invite_url(invite)}
          </p>
          <p class="mt-1 text-xs text-slate-500">#{DiscordFormatting.invite_channel_name(invite)}</p>
        </div>
      </div>
    </section>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_invites_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-invites:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_invites_hooks_attached?], true)
    end
  end

  defp request_invites(socket, key: key) do
    if LiveView.connected?(socket),
      do: DiscordDomainManager.request_invites(pid: self(), key: key)

    socket
  end

  defp hooked_info({:discord, {:invites_loaded, key, {:ok, invites}}}, socket) do
    {:cont,
     assign(socket, key, %{socket.assigns[key] | invites: invites, loading?: false, error: nil})}
  end

  defp hooked_info({:discord, {:invites_loaded, key, {:error, reason}}}, socket) do
    Logger.error("Discord invites failed reason=#{inspect(reason)}")

    {:cont,
     assign(socket, key, %{
       socket.assigns[key]
       | loading?: false,
         error: "Could not load Discord invites."
     })}
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} -> DiscordDomainManager.request_invites(pid: self(), key: key)
      _assign -> :ok
    end)

    {:cont, socket}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp active_invites(invites), do: Enum.sort_by(invites, & &1["name"])
end
