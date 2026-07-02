defmodule SnowSeToolsWeb.Discord.DiscordMembers do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeToolsWeb.Discord.DiscordFormatting

  defstruct key: nil,
            members: [],
            loading?: true,
            error: nil

  def assign_component(socket, key) do
    socket
    |> assign_new(key, fn -> %__MODULE__{key: key} end)
    |> maybe_attach_hooks()
    |> request_members(key: key)
  end

  attr :state, __MODULE__, required: true

  def render(assigns) do
    ~H"""
    <div id="discord-members" class="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
      <div
        :if={@state.error}
        class="rounded-md border border-rose-500/30 bg-rose-500/10 p-3 text-sm text-rose-200"
      >
        {@state.error}
      </div>
      <div class="hidden rounded-md border border-slate-800 bg-slate-950/50 p-6 text-sm text-slate-400 only:block">
        No Discord members have been synced yet.
      </div>
      <article
        :for={member <- @state.members}
        id={"discord-member-#{member["id"]}"}
        class="rounded-md border border-slate-800 bg-slate-950/40 p-3"
      >
        <p class="truncate text-sm font-medium text-slate-100">{member["name"]}</p>
        <p class="mt-1 truncate text-xs text-slate-500">
          {DiscordFormatting.member_username(member)}
        </p>
      </article>
    </div>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_members_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-members:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_members_hooks_attached?], true)
    end
  end

  defp request_members(socket, key: key) do
    if LiveView.connected?(socket),
      do: DiscordDomainManager.request_members(pid: self(), key: key)

    socket
  end

  defp hooked_info({:discord, {:members_loaded, key, {:ok, members}}}, socket) do
    {:cont,
     assign(socket, key, %{socket.assigns[key] | members: members, loading?: false, error: nil})}
  end

  defp hooked_info({:discord, {:members_loaded, key, {:error, reason}}}, socket) do
    Logger.error("Discord members failed reason=#{inspect(reason)}")

    {:cont,
     assign(socket, key, %{
       socket.assigns[key]
       | loading?: false,
         error: "Could not load Discord members."
     })}
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} -> DiscordDomainManager.request_members(pid: self(), key: key)
      _assign -> :ok
    end)

    {:cont, socket}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}
end
