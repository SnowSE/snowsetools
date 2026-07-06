defmodule SnowSeToolsWeb.Discord.DiscordChannels do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager

  alias SnowSeToolsWeb.Discord.{
    DiscordAddMyCourses,
    DiscordChannelAssignModal,
    DiscordChannelRow,
    DiscordChannelSyncModal,
    DiscordStudentMapping
  }

  defstruct key: nil,
            channels: [],
            groups: [],
            mappings: [],
            loading?: true,
            error: nil

  def assign_component(socket, key) do
    socket
    |> assign_new(key, fn -> %__MODULE__{key: key} end)
    |> maybe_attach_hooks()
    |> request_data(key: key)
  end

  attr :state, __MODULE__, required: true
  attr :members, :any, required: true
  attr :roles, :any, required: true
  attr :channel_row_states, :map, default: %{}
  attr :student_mapping_states, :map, default: %{}
  attr :student_row_states, :map, default: %{}
  attr :add_my_courses_state, :any, required: true
  attr :assign_modal_state, :any, required: true
  attr :sync_modal_states, :map, default: %{}
  attr :courses_by_term, :map, default: %{}

  def render(assigns) do
    ~H"""
    <div id="discord-channel-groups" class="flex flex-col gap-4">
      <div class="flex items-center justify-between gap-3">
        <div class="min-w-0">
          <h2 class="text-base font-semibold text-slate-100">Course channels</h2>
        </div>
        <DiscordAddMyCourses.render
          state={@add_my_courses_state}
          courses_by_term={@courses_by_term}
          channels={@state.channels}
          roles={@roles.roles}
        />
      </div>

      <div
        :if={@state.error}
        class="rounded-md border border-rose-500/30 bg-rose-500/10 p-3 text-sm text-rose-200"
      >
        {@state.error}
      </div>

      <div class="hidden rounded-md border border-slate-800 bg-slate-950/50 p-6 text-sm text-slate-400 only:block">
        No Discord channels have been synced yet.
      </div>

      <section
        :for={group <- @state.groups}
        id={"discord-channel-group-#{group.id}"}
        class="rounded-md border border-slate-800 bg-slate-950/40 p-4"
      >
        <div class="mb-3 flex flex-wrap items-center gap-2">
          <span class={[
            "size-2 rounded-full",
            group.private? && "bg-amber-400",
            !group.private? && "bg-emerald-400"
          ]} />
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-300">{group.name}</h2>
          <span class="rounded-full border border-slate-800 px-2 py-0.5 text-xs text-slate-500">
            {length(group.children)} channels
          </span>
          <span
            :if={group.private?}
            class="rounded-full bg-amber-500/10 px-2 py-0.5 text-xs text-amber-200"
          >
            private
          </span>
        </div>

        <div class="flex flex-col gap-2">
          <%= for channel <- group.children do %>
            <DiscordChannelRow.render
              state={resolve_channel_row_state(assigns, channel)}
              mappings={@state.mappings}
              members={@members.members}
              roles={@roles.roles}
              student_mapping_states={@student_mapping_states}
              student_row_states={@student_row_states}
              student_mapping_state={resolve_student_mapping_state(assigns, channel)}
              sync_modal_state={resolve_sync_modal_state(assigns, channel)}
            />
          <% end %>
        </div>
      </section>

      <DiscordChannelAssignModal.render
        state={@assign_modal_state}
        roles={@roles.roles}
        courses_by_term={@courses_by_term}
      />
    </div>
    """
  end

  defp resolve_channel_row_state(assigns, channel) do
    row_key = channel_row_key(channel)
    channel_row_states = Map.get(assigns, :channel_row_states, %{})

    DiscordChannelRow.fetch_state(
      %{:discord_channel_row_states => channel_row_states},
      row_key
    ) ||
      %DiscordChannelRow{key: row_key, channel: normalize_channel(channel)}
  end

  defp resolve_student_mapping_state(assigns, channel) do
    row_key = channel_row_key(channel)
    mapping_key = "discord-student-mapping:#{row_key}"
    student_mapping_states = Map.get(assigns, :student_mapping_states, %{})

    DiscordStudentMapping.fetch_state(
      %{:discord_student_mapping_states => student_mapping_states},
      mapping_key
    ) ||
      %DiscordStudentMapping{key: mapping_key, assignment: nil}
  end

  defp resolve_sync_modal_state(assigns, channel) do
    row_key = channel_row_key(channel)
    channel_data = normalize_channel(channel)
    sync_modal_states = Map.get(assigns, :sync_modal_states, %{})

    DiscordChannelSyncModal.fetch_state(
      %{:discord_channel_sync_modal_states => sync_modal_states},
      row_key
    ) ||
      %DiscordChannelSyncModal{key: row_key, channel: channel_data}
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_channels_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-channels:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_channels_hooks_attached?], true)
    end
  end

  defp request_data(socket, key: key) do
    if LiveView.connected?(socket) do
      DiscordDomainManager.request_channels(pid: self(), key: key)
      DiscordDomainManager.request_student_discord_mappings(pid: self(), key: key)
    end

    socket
  end

  defp hooked_info({:discord, {:channels_loaded, key, {:ok, channels}}}, socket) do
    groups = build_groups(channels)

    socket =
      socket
      |> assign(key, %{
        socket.assigns[key]
        | channels: channels,
          groups: groups,
          loading?: false,
          error: nil
      })
      |> ensure_channel_rows(channels)

    {:cont, socket}
  end

  defp hooked_info({:discord, {:channels_loaded, key, {:error, reason}}}, socket) do
    Logger.error("Discord channels failed reason=#{inspect(reason)}")

    {:cont,
     assign(socket, key, %{
       socket.assigns[key]
       | loading?: false,
         error: "Could not load Discord channels."
     })}
  end

  defp hooked_info({:discord, {:student_discord_mappings_loaded, key, {:ok, mappings}}}, socket) do
    {:cont, assign(socket, key, %{socket.assigns[key] | mappings: mappings, error: nil})}
  end

  defp hooked_info({:discord, {:student_discord_mappings_loaded, key, {:error, reason}}}, socket) do
    Logger.error("Discord student mappings failed reason=#{inspect(reason)}")

    {:cont,
     assign(socket, key, %{
       socket.assigns[key]
       | error: "Could not load Discord student mappings."
     })}
  end

  defp hooked_info({:discord, {:student_discord_mapping_saved, _key, _result}}, socket) do
    refresh_student_mappings(socket)
  end

  defp hooked_info({:discord, {:student_discord_mapping_deleted, _key, _result}}, socket) do
    refresh_student_mappings(socket)
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} ->
        DiscordDomainManager.request_channels(pid: self(), key: key)

      _assign ->
        :ok
    end)

    refresh_student_mappings(socket)
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp refresh_student_mappings(socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} ->
        DiscordDomainManager.request_student_discord_mappings(pid: self(), key: key)

      _assign ->
        :ok
    end)

    {:cont, socket}
  end

  defp build_groups(channels) do
    channel_models =
      channels
      |> Enum.map(&channel_model/1)
      |> Enum.sort_by(&{&1.position, &1.name})

    category_by_id =
      channel_models
      |> Enum.filter(&(&1.type == 4))
      |> Map.new(&{&1.id, &1})

    grouped_children =
      channel_models
      |> Enum.reject(&(&1.type == 4))
      |> Enum.group_by(&(&1.parent_id || ""))

    categories =
      category_by_id
      |> Map.values()
      |> Enum.sort_by(&{&1.position, &1.name})
      |> Enum.map(fn category ->
        %{
          id: category.id,
          name: category.name,
          private?: channel_private?(category.data),
          children: Map.get(grouped_children, category.id, [])
        }
      end)

    uncategorized = Map.get(grouped_children, "")

    if uncategorized in [nil, []] do
      categories
    else
      categories ++
        [%{id: "uncategorized", name: "Uncategorized", private?: false, children: uncategorized}]
    end
  end

  defp channel_model(item) do
    data = Map.get(item, "data", %{})

    %{
      id: Map.get(item, "id"),
      name: Map.get(item, "name", "unnamed"),
      type: Map.get(data, "type"),
      parent_id: Map.get(data, "parent_id"),
      position: Map.get(data, "position", 999_999),
      private?: channel_private?(data),
      data: data
    }
  end

  defp ensure_channel_rows(socket, channels) do
    Enum.reduce(channels, socket, fn channel, acc ->
      DiscordChannelRow.assign_component(acc, channel_row_key(channel), channel: channel)
    end)
  end

  defp channel_row_key(channel) do
    channel_id = Map.get(channel, "id") || Map.get(channel, :id)
    "discord-channel-row:#{channel_id}"
  end

  defp channel_private?(data) do
    data
    |> Map.get("permission_overwrites", [])
    |> Enum.any?(&(Map.get(&1, "type") == 0))
  end

  defp normalize_channel(channel) do
    case channel do
      %{"id" => _id} = raw_channel -> raw_channel
      %{id: id, name: name, data: data} -> %{"id" => id, "name" => name, "data" => data}
      _other -> %{}
    end
  end
end
