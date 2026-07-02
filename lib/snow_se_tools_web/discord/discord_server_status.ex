defmodule SnowSeToolsWeb.Discord.DiscordServerStatus do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeToolsWeb.Discord.DiscordFormatting

  defstruct key: nil,
            guild: nil,
            bot_user: nil,
            loading?: true,
            error: nil

  def assign_component(socket, key) do
    socket
    |> assign_new(key, fn -> %__MODULE__{key: key} end)
    |> maybe_attach_hooks()
    |> request_server_status(key: key)
  end

  attr :state, __MODULE__, required: true

  def render(assigns) do
    ~H"""
    <section id="discord-server-status" class="rounded-md border border-slate-800 bg-slate-950/50 p-4">
      <h2 class="text-sm font-semibold text-slate-100">Server</h2>
      <p :if={@state.error} class="mt-2 text-sm text-rose-200">{@state.error}</p>
      <dl class="mt-3 space-y-3 text-sm">
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500">Guild</dt>
          <dd class="mt-1 truncate text-slate-200">{DiscordFormatting.item_name(@state.guild)}</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500">Bot user</dt>
          <dd class="mt-1 truncate text-slate-200">{DiscordFormatting.item_name(@state.bot_user)}</dd>
        </div>
      </dl>
    </section>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_server_status_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-server-status:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_server_status_hooks_attached?], true)
    end
  end

  defp request_server_status(socket, key: key) do
    if LiveView.connected?(socket) do
      DiscordDomainManager.request_server_status(pid: self(), key: key)
    end

    socket
  end

  defp hooked_info({:discord, {:server_status_loaded, key, {:ok, status}}}, socket) do
    {:cont,
     assign(socket, key, %{
       socket.assigns[key]
       | guild: status.guild,
         bot_user: status.bot_user,
         loading?: false,
         error: nil
     })}
  end

  defp hooked_info({:discord, {:server_status_loaded, key, {:error, reason}}}, socket) do
    Logger.error("Discord server status failed reason=#{inspect(reason)}")

    {:cont,
     assign(socket, key, %{
       socket.assigns[key]
       | loading?: false,
         error: "Could not load Discord server status."
     })}
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} -> DiscordDomainManager.request_server_status(pid: self(), key: key)
      _assign -> :ok
    end)

    {:cont, socket}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}
end
