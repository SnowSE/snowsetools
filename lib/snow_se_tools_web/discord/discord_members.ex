defmodule SnowSeToolsWeb.Discord.DiscordMembers do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeToolsWeb.Discord.DiscordFormatting

  defstruct key: nil,
            members: [],
            mapped_discord_user_ids: MapSet.new(),
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
    assigns =
      assign(
        assigns,
        :mapped_discord_user_ids,
        Map.get(assigns.state, :mapped_discord_user_ids, MapSet.new())
      )

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
        <div class="flex items-center gap-2">
          <p class="min-w-0 truncate text-sm font-medium text-slate-100">{member["name"]}</p>
          <span
            :if={MapSet.member?(@mapped_discord_user_ids, member["id"])}
            class="shrink-0 rounded-full bg-emerald-500/20 px-2 py-0.5 text-xs font-medium text-emerald-200"
          >
            mapped
          </span>
        </div>
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
    if LiveView.connected?(socket) do
      DiscordDomainManager.request_members(pid: self(), key: key)
      DiscordDomainManager.request_student_discord_mappings(pid: self(), key: key)
    end

    socket
  end

  defp hooked_info({:discord, {:members_loaded, key, {:ok, members}}}, socket) do
    case Map.fetch(socket.assigns, key) do
      {:ok, %__MODULE__{}} ->
        {:cont,
         assign(socket, key, %{
           socket.assigns[key]
           | members: members,
             loading?: false,
             error: nil
         })}

      _ ->
        {:cont, socket}
    end
  end

  defp hooked_info({:discord, {:members_loaded, key, {:error, reason}}}, socket) do
    case Map.fetch(socket.assigns, key) do
      {:ok, %__MODULE__{}} ->
        Logger.error("Discord members failed reason=#{inspect(reason)}")

        {:cont,
         assign(socket, key, %{
           socket.assigns[key]
           | loading?: false,
             error: "Could not load Discord members."
         })}

      _ ->
        {:cont, socket}
    end
  end

  defp hooked_info({:discord, {:student_discord_mappings_loaded, key, {:ok, mappings}}}, socket) do
    case Map.fetch(socket.assigns, key) do
      {:ok, %__MODULE__{}} ->
        mapped_ids =
          mappings
          |> Enum.map(& &1["discord_user_id"])
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()

        {:cont, assign(socket, key, %{socket.assigns[key] | mapped_discord_user_ids: mapped_ids})}

      _ ->
        {:cont, socket}
    end
  end

  defp hooked_info(
         {:discord, {:student_discord_mappings_loaded, _key, {:error, reason}}},
         socket
       ) do
    Logger.error("Discord student mappings load failed reason=#{inspect(reason)}")
    {:cont, socket}
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} -> DiscordDomainManager.request_members(pid: self(), key: key)
      _assign -> :ok
    end)

    {:cont, socket}
  end

  defp hooked_info({:discord, {:student_discord_mapping_saved, _key, {:ok, _}}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} ->
        DiscordDomainManager.request_student_discord_mappings(pid: self(), key: key)

      _assign ->
        :ok
    end)

    {:cont, socket}
  end

  defp hooked_info({:discord, {:student_discord_mapping_saved, _key, {:error, reason}}}, socket) do
    Logger.error("Discord student mapping save failed reason=#{inspect(reason)}")
    {:cont, socket}
  end

  defp hooked_info({:discord, {:student_discord_mapping_deleted, _key, {:ok, _}}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} ->
        DiscordDomainManager.request_student_discord_mappings(pid: self(), key: key)

      _assign ->
        :ok
    end)

    {:cont, socket}
  end

  defp hooked_info({:discord, {:student_discord_mapping_deleted, _key, {:error, reason}}}, socket) do
    Logger.error("Discord student mapping delete failed reason=#{inspect(reason)}")
    {:cont, socket}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}
end
