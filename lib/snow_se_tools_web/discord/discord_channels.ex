defmodule SnowSeToolsWeb.Discord.DiscordChannels do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager

  defstruct key: nil,
            channels: [],
            loading?: true,
            error: nil

  def assign_component(socket, key) do
    socket
    |> assign_new(key, fn -> %__MODULE__{key: key} end)
    |> maybe_attach_hooks()
    |> request_channels(key: key)
  end

  attr :state, __MODULE__, required: true

  def render(assigns) do
    assigns = assign(assigns, :grouped_channels, grouped_channels(assigns.state.channels))

    ~H"""
    <div id="discord-channel-groups" class="flex flex-col gap-4">
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
        :for={group <- @grouped_channels}
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
          <article
            :for={channel <- group.children}
            id={"discord-channel-#{channel.id}"}
            class="rounded-md border border-slate-800/80 bg-slate-900/45 px-3 py-2 transition-colors hover:border-slate-700"
          >
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-sm font-medium text-slate-100">#{channel.name}</span>
              <span class="rounded-full bg-slate-800 px-2 py-0.5 text-xs text-slate-400">
                {channel_type_name(channel.type)}
              </span>
              <span
                :if={channel.private?}
                class="inline-flex items-center gap-1 rounded-full bg-amber-500/10 px-2 py-0.5 text-xs text-amber-200"
              >
                <.icon name="hero-lock-closed" class="size-3" /> private
              </span>
              <span
                :if={!channel.private?}
                class="inline-flex items-center gap-1 rounded-full bg-emerald-500/10 px-2 py-0.5 text-xs text-emerald-200"
              >
                <.icon name="hero-globe-alt" class="size-3" /> public
              </span>
            </div>
          </article>
        </div>
      </section>
    </div>
    """
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

  defp request_channels(socket, key: key) do
    if LiveView.connected?(socket),
      do: DiscordDomainManager.request_channels(pid: self(), key: key)

    socket
  end

  defp hooked_info({:discord, {:channels_loaded, key, {:ok, channels}}}, socket) do
    {:cont,
     assign(socket, key, %{socket.assigns[key] | channels: channels, loading?: false, error: nil})}
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

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{}} -> DiscordDomainManager.request_channels(pid: self(), key: key)
      _assign -> :ok
    end)

    {:cont, socket}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp grouped_channels(channels) do
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

  defp channel_private?(data) do
    data
    |> Map.get("permission_overwrites", [])
    |> Enum.any?(&(Map.get(&1, "type") == 0))
  end

  defp channel_type_name(0), do: "text"
  defp channel_type_name(2), do: "voice"
  defp channel_type_name(4), do: "category"
  defp channel_type_name(5), do: "announcement"
  defp channel_type_name(13), do: "stage"
  defp channel_type_name(15), do: "forum"
  defp channel_type_name(_type), do: "channel"
end
