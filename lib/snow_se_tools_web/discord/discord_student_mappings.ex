defmodule SnowSeToolsWeb.Discord.DiscordStudentMappings do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager

  defstruct key: nil,
            mappings: [],
            loading?: true,
            error: nil

  def assign_component(socket, key) do
    socket
    |> assign_new(key, fn -> %__MODULE__{key: key} end)
    |> maybe_attach_hooks()
    |> request_mappings(key: key)
  end

  attr :state, __MODULE__, required: true

  def render(assigns) do
    ~H"""
    <div id="discord-student-mappings" class="hidden">
      <div :if={@state.error}>{@state.error}</div>
    </div>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_student_mappings_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-student-mappings:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_student_mappings_hooks_attached?], true)
    end
  end

  defp request_mappings(socket, key: key) do
    if LiveView.connected?(socket) do
      DiscordDomainManager.request_student_discord_mappings(pid: self(), key: key)
    end

    socket
  end

  defp hooked_info({:discord, {:student_discord_mappings_loaded, key, {:ok, mappings}}}, socket) do
    {:cont,
     assign(socket, key, %{socket.assigns[key] | mappings: mappings, loading?: false, error: nil})}
  end

  defp hooked_info({:discord, {:student_discord_mappings_loaded, key, {:error, reason}}}, socket) do
    Logger.error("Discord student mappings failed reason=#{inspect(reason)}")

    {:cont,
     assign(socket, key, %{
       socket.assigns[key]
       | loading?: false,
         error: "Could not load Discord student mappings."
     })}
  end

  defp hooked_info({:discord, {:student_discord_mapping_saved, _key, _result}}, socket) do
    refresh_mappings(socket)
  end

  defp hooked_info({:discord, {:student_discord_mapping_deleted, _key, _result}}, socket) do
    refresh_mappings(socket)
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    refresh_mappings(socket)
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp refresh_mappings(socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} ->
        DiscordDomainManager.request_student_discord_mappings(pid: self(), key: key)

      _assign ->
        :ok
    end)

    {:cont, socket}
  end
end
