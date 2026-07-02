defmodule SnowSeToolsWeb.Discord.DiscordRoles do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeToolsWeb.Discord.DiscordFormatting

  defstruct key: nil,
            roles: [],
            loading?: true,
            error: nil

  def assign_component(socket, key) do
    socket
    |> assign_new(key, fn -> %__MODULE__{key: key} end)
    |> maybe_attach_hooks()
    |> request_roles(key: key)
  end

  attr :state, __MODULE__, required: true

  def render(assigns) do
    assigns = assign(assigns, :visible_roles, visible_roles(assigns.state.roles))

    ~H"""
    <div id="discord-roles" class="flex flex-wrap gap-2">
      <div
        :if={@state.error}
        class="rounded-md border border-rose-500/30 bg-rose-500/10 p-3 text-sm text-rose-200"
      >
        {@state.error}
      </div>
      <div class="hidden rounded-md border border-slate-800 bg-slate-950/50 p-6 text-sm text-slate-400 only:block">
        No Discord roles have been synced yet.
      </div>
      <span
        :for={role <- @visible_roles}
        id={"discord-role-#{role["id"]}"}
        class="inline-flex items-center gap-2 rounded-md border border-slate-800 bg-slate-950/50 px-3 py-2 text-sm text-slate-200"
      >
        <span
          class="size-2 rounded-full"
          style={"background-color: #{DiscordFormatting.role_color(role)}"}
        />
        {role["name"]}
      </span>
    </div>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_roles_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-roles:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_roles_hooks_attached?], true)
    end
  end

  defp request_roles(socket, key: key) do
    if LiveView.connected?(socket), do: DiscordDomainManager.request_roles(pid: self(), key: key)
    socket
  end

  defp hooked_info({:discord, {:roles_loaded, key, {:ok, roles}}}, socket) do
    {:cont,
     assign(socket, key, %{socket.assigns[key] | roles: roles, loading?: false, error: nil})}
  end

  defp hooked_info({:discord, {:roles_loaded, key, {:error, reason}}}, socket) do
    Logger.error("Discord roles failed reason=#{inspect(reason)}")

    {:cont,
     assign(socket, key, %{
       socket.assigns[key]
       | loading?: false,
         error: "Could not load Discord roles."
     })}
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} -> DiscordDomainManager.request_roles(pid: self(), key: key)
      _assign -> :ok
    end)

    {:cont, socket}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp visible_roles(roles) do
    roles
    |> Enum.reject(&(&1["name"] == "@everyone"))
    |> Enum.sort_by(fn role -> -Map.get(role["data"], "position", 0) end)
  end
end
