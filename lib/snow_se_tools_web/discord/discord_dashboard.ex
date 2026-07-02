defmodule SnowSeToolsWeb.Discord.DiscordDashboard do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.{DiscordDomainManager, DiscordPubSub}

  defstruct [
    :dashboard,
    :loading?,
    :syncing?,
    :error,
    :active_view
  ]

  @key :discord_dashboard

  def assign_component(socket) do
    socket
    |> assign_new(@key, fn ->
      %__MODULE__{
        dashboard: empty_dashboard(),
        loading?: true,
        syncing?: false,
        error: nil,
        active_view: :channels
      }
    end)
    |> maybe_attach_hooks()
    |> maybe_request_dashboard()
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:summary_cards, summary_cards(assigns.state.dashboard))
      |> assign(:guild, first_item(assigns.state.dashboard.guilds))
      |> assign(:bot_user, first_item(assigns.state.dashboard.bot_users))
      |> assign(:grouped_channels, grouped_channels(assigns.state.dashboard.channels))
      |> assign(:roles_to_show, visible_roles(assigns.state.dashboard.roles))
      |> assign(:invites_to_show, active_invites(assigns.state.dashboard.invites))

    ~H"""
    <main
      id="discord-page"
      class="mx-auto flex h-full min-h-0 w-full max-w-[1800px] flex-col gap-5 p-4"
    >
      <section class="shrink-0 border-b border-slate-800/80 pb-4">
        <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div class="min-w-0">
            <p class="text-xs font-semibold uppercase tracking-[0.22em] text-indigo-300">Discord</p>
            <h1 class="mt-1 text-2xl font-semibold text-slate-100">Discord Overview</h1>
            <p class="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
              {@guild_name} server data, channels, roles, invites, and member cache.
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <span
              :if={@state.error}
              id="discord-dashboard-error"
              class="rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-200"
            >
              {@state.error}
            </span>
            <button
              id="discord-sync-button"
              type="button"
              phx-click="discord-dashboard:sync"
              disabled={@state.syncing?}
              class={[
                "inline-flex h-10 items-center gap-2 rounded-md border px-4 text-sm font-medium transition-colors",
                @state.syncing? &&
                  "cursor-not-allowed border-slate-700 bg-slate-800/70 text-slate-400",
                !@state.syncing? &&
                  "cursor-pointer border-indigo-400/50 bg-indigo-500/15 text-indigo-100 hover:bg-indigo-500/25"
              ]}
            >
              <.icon
                name="hero-arrow-path"
                class={if(@state.syncing?, do: "size-4 animate-spin", else: "size-4")}
              />
              <span>{if @state.syncing?, do: "Syncing", else: "Sync Discord Data"}</span>
            </button>
          </div>
        </div>

        <div class="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
          <div
            :for={card <- @summary_cards}
            id={"discord-summary-#{card.key}"}
            class="rounded-md border border-slate-800 bg-slate-950/50 p-3"
          >
            <div class="flex items-center justify-between gap-3">
              <p class="text-xs font-medium uppercase tracking-wide text-slate-500">{card.label}</p>
              <span class="text-xs text-slate-500">{card.synced_at}</span>
            </div>
            <p class="mt-2 text-2xl font-semibold text-slate-100">{card.count}</p>
          </div>
        </div>
      </section>

      <section class="grid min-h-0 flex-1 gap-4 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <div class="min-h-0 overflow-y-auto pr-1">
          <div class="mb-3 flex flex-wrap gap-2">
            <button
              :for={
                {view, label} <- [
                  {:channels, "Channels"},
                  {:members, "Members"},
                  {:roles, "Roles"},
                  {:invites, "Invites"}
                ]
              }
              id={"discord-view-#{view}"}
              type="button"
              phx-click="discord-dashboard:switch_view"
              phx-value-view={view}
              class={[
                "rounded-md border px-3 py-1.5 text-sm font-medium transition-colors",
                @state.active_view == view &&
                  "border-indigo-400/60 bg-indigo-500/15 text-indigo-100",
                @state.active_view != view &&
                  "border-slate-800 bg-slate-950/40 text-slate-400 hover:border-slate-700 hover:text-slate-200"
              ]}
            >
              {label}
            </button>
          </div>

          <%= case @state.active_view do %>
            <% :channels -> %>
              <.channels_view grouped_channels={@grouped_channels} roles={@state.dashboard.roles} />
            <% :members -> %>
              <.members_view members={@state.dashboard.members} />
            <% :roles -> %>
              <.roles_view roles={@roles_to_show} />
            <% :invites -> %>
              <.invites_view invites={@invites_to_show} />
          <% end %>
        </div>

        <aside class="flex min-h-0 flex-col gap-4 overflow-y-auto border-t border-slate-800 pt-4 xl:border-l xl:border-t-0 xl:pl-4 xl:pt-0">
          <.server_panel guild={@guild} bot_user={@bot_user} />
          <.invite_panel invites={@invites_to_show} />
          <.bot_roles_panel roles={@roles_to_show} bot_user={@bot_user} />
        </aside>
      </section>
    </main>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_dashboard_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-dashboard:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("discord-dashboard:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_dashboard_hooks_attached?], true)
    end
  end

  defp maybe_request_dashboard(socket) do
    if LiveView.connected?(socket) and
         !Map.get(socket.private, :discord_dashboard_requested?) do
      DiscordPubSub.subscribe()
      request_dashboard()
      put_in(socket, [Access.key(:private), :discord_dashboard_requested?], true)
    else
      socket
    end
  end

  defp hooked_event("discord-dashboard:sync", _params, socket) do
    case Process.whereis(DiscordDomainManager) do
      nil ->
        Logger.error("Discord dashboard sync requested but DiscordDomainManager is not running")

        {:halt,
         socket
         |> assign(@key, %{
           socket.assigns[@key]
           | syncing?: false,
             loading?: false,
             error: "Discord service is not running."
         })
         |> LiveView.put_flash(:error, "Discord service is not running.")}

      _pid ->
        DiscordDomainManager.sync_all(pid: self())

        {:halt,
         assign(socket, @key, %{
           socket.assigns[@key]
           | syncing?: true,
             error: nil
         })}
    end
  end

  defp hooked_event("discord-dashboard:switch_view", %{"view" => view}, socket) do
    {:halt,
     assign(socket, @key, %{
       socket.assigns[@key]
       | active_view: view_from_param(view)
     })}
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  defp hooked_info({:discord, {:dashboard_loaded, dashboard}}, socket) do
    {:halt,
     assign(socket, @key, %{
       socket.assigns[@key]
       | dashboard: normalize_dashboard(dashboard),
         loading?: false,
         error: nil
     })}
  end

  defp hooked_info({:discord, {:sync_finished, {:ok, _summary}}}, socket) do
    {:halt,
     socket
     |> assign(@key, %{socket.assigns[@key] | syncing?: false, error: nil})
     |> LiveView.put_flash(:info, "Discord data synced.")}
  end

  defp hooked_info({:discord, {:sync_finished, {:error, reasons}}}, socket) do
    Logger.error("Discord dashboard sync failed reasons=#{inspect(reasons)}")

    {:halt,
     socket
     |> assign(@key, %{
       socket.assigns[@key]
       | syncing?: false,
         loading?: false,
         error: Enum.join(reasons, "; ")
     })
     |> LiveView.put_flash(:error, "Discord sync failed.")}
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    request_dashboard()
    {:halt, socket}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp request_dashboard do
    case Process.whereis(DiscordDomainManager) do
      nil ->
        Logger.error(
          "Discord dashboard could not load because DiscordDomainManager is not running"
        )

      _pid ->
        DiscordDomainManager.request_dashboard(pid: self())
    end
  end

  attr :grouped_channels, :list, required: true
  attr :roles, :list, required: true

  defp channels_view(assigns) do
    ~H"""
    <div id="discord-channel-groups" class="flex flex-col gap-4">
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

  attr :members, :list, required: true

  defp members_view(assigns) do
    ~H"""
    <div id="discord-members" class="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
      <div class="hidden rounded-md border border-slate-800 bg-slate-950/50 p-6 text-sm text-slate-400 only:block">
        No Discord members have been synced yet.
      </div>
      <article
        :for={member <- @members}
        id={"discord-member-#{member["id"]}"}
        class="rounded-md border border-slate-800 bg-slate-950/40 p-3"
      >
        <p class="truncate text-sm font-medium text-slate-100">{member["name"]}</p>
        <p class="mt-1 truncate text-xs text-slate-500">{member_username(member)}</p>
      </article>
    </div>
    """
  end

  attr :roles, :list, required: true

  defp roles_view(assigns) do
    ~H"""
    <div id="discord-roles" class="flex flex-wrap gap-2">
      <div class="hidden rounded-md border border-slate-800 bg-slate-950/50 p-6 text-sm text-slate-400 only:block">
        No Discord roles have been synced yet.
      </div>
      <span
        :for={role <- @roles}
        id={"discord-role-#{role["id"]}"}
        class="inline-flex items-center gap-2 rounded-md border border-slate-800 bg-slate-950/50 px-3 py-2 text-sm text-slate-200"
      >
        <span class="size-2 rounded-full" style={"background-color: #{role_color(role)}"} />
        {role["name"]}
      </span>
    </div>
    """
  end

  attr :invites, :list, required: true

  defp invites_view(assigns) do
    ~H"""
    <div id="discord-invites" class="flex flex-col gap-2">
      <div class="hidden rounded-md border border-slate-800 bg-slate-950/50 p-6 text-sm text-slate-400 only:block">
        No Discord invites have been synced yet.
      </div>
      <article
        :for={invite <- @invites}
        id={"discord-invite-#{invite["id"]}"}
        class="rounded-md border border-slate-800 bg-slate-950/40 p-3"
      >
        <div class="flex flex-wrap items-center gap-2">
          <span class="font-mono text-sm text-indigo-200">{invite_url(invite)}</span>
          <span class="rounded-full bg-slate-800 px-2 py-0.5 text-xs text-slate-400">
            #{invite_channel_name(invite)}
          </span>
        </div>
      </article>
    </div>
    """
  end

  attr :guild, :map, default: nil
  attr :bot_user, :map, default: nil

  defp server_panel(assigns) do
    ~H"""
    <section id="discord-server-panel" class="rounded-md border border-slate-800 bg-slate-950/50 p-4">
      <h2 class="text-sm font-semibold text-slate-100">Server</h2>
      <dl class="mt-3 space-y-3 text-sm">
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500">Guild</dt>
          <dd class="mt-1 truncate text-slate-200">{item_name(@guild)}</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-slate-500">Bot user</dt>
          <dd class="mt-1 truncate text-slate-200">{item_name(@bot_user)}</dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :invites, :list, required: true

  defp invite_panel(assigns) do
    ~H"""
    <section id="discord-invite-panel" class="rounded-md border border-slate-800 bg-slate-950/50 p-4">
      <h2 class="text-sm font-semibold text-slate-100">Server Invites</h2>
      <div class="mt-3 flex flex-col gap-2">
        <p :if={@invites == []} class="text-sm text-slate-500">No active invites are cached.</p>
        <div
          :for={invite <- Enum.take(@invites, 4)}
          class="rounded-md border border-slate-800 bg-slate-900/50 px-3 py-2"
        >
          <p class="truncate font-mono text-xs text-indigo-200">{invite_url(invite)}</p>
          <p class="mt-1 text-xs text-slate-500">#{invite_channel_name(invite)}</p>
        </div>
      </div>
    </section>
    """
  end

  attr :roles, :list, required: true
  attr :bot_user, :map, default: nil

  defp bot_roles_panel(assigns) do
    assigns = assign(assigns, :bot_role_ids, bot_role_ids(assigns.bot_user))

    ~H"""
    <section
      id="discord-bot-roles-panel"
      class="rounded-md border border-slate-800 bg-slate-950/50 p-4"
    >
      <h2 class="text-sm font-semibold text-slate-100">Bot Role Visibility</h2>
      <p class="mt-2 text-sm leading-6 text-slate-500">
        Cached roles are shown here. Role mutation is not implemented in the Elixir service yet.
      </p>
      <div class="mt-3 flex flex-wrap gap-2">
        <span
          :for={role <- Enum.take(@roles, 10)}
          class={[
            "rounded-md border px-2 py-1 text-xs",
            role["id"] in @bot_role_ids && "border-emerald-500/30 bg-emerald-500/10 text-emerald-200",
            role["id"] not in @bot_role_ids && "border-slate-800 bg-slate-900/50 text-slate-400"
          ]}
        >
          {role["name"]}
        </span>
      </div>
    </section>
    """
  end

  defp empty_dashboard do
    %{
      summary: [],
      guilds: [],
      bot_users: [],
      members: [],
      channels: [],
      roles: [],
      invites: []
    }
  end

  defp normalize_dashboard(dashboard) when is_map(dashboard) do
    Map.merge(empty_dashboard(), dashboard)
  end

  defp summary_cards(dashboard) do
    summary_by_resource = Map.new(dashboard.summary, &{&1["resource"], &1})

    [
      {"guilds", "Guilds"},
      {"bot_users", "Bots"},
      {"members", "Members"},
      {"channels", "Channels"},
      {"roles", "Roles"},
      {"invites", "Invites"}
    ]
    |> Enum.map(fn {resource, label} ->
      row = Map.get(summary_by_resource, resource, %{})

      %{
        key: resource,
        label: label,
        count: Map.get(row, "record_count", 0),
        synced_at: format_synced_at(Map.get(row, "last_synced_at"))
      }
    end)
  end

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

    uncategorized = Map.get(grouped_children, "", [])

    if uncategorized == [] do
      categories
    else
      categories ++
        [
          %{
            id: "uncategorized",
            name: "Uncategorized",
            private?: false,
            children: uncategorized
          }
        ]
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

  defp active_invites(invites), do: Enum.sort_by(invites, & &1["name"])

  defp visible_roles(roles) do
    roles
    |> Enum.reject(&(&1["name"] == "@everyone"))
    |> Enum.sort_by(fn role -> -Map.get(role["data"], "position", 0) end)
  end

  defp first_item([item | _items]), do: item
  defp first_item([]), do: nil

  defp item_name(nil), do: "Not synced"
  defp item_name(item), do: item["name"] || item["id"] || "Not synced"

  defp member_username(member) do
    member
    |> Map.get("data", %{})
    |> Map.get("user", %{})
    |> Map.get("username", member["id"])
  end

  defp invite_url(invite) do
    data = Map.get(invite, "data", %{})
    Map.get(data, "url") || "https://discord.gg/#{invite["id"]}"
  end

  defp invite_channel_name(invite) do
    invite
    |> Map.get("data", %{})
    |> Map.get("channel", %{})
    |> Map.get("name", "unknown")
  end

  defp role_color(role) do
    color =
      role
      |> Map.get("data", %{})
      |> Map.get("color", 0)

    "#" <> String.pad_leading(Integer.to_string(color, 16), 6, "0")
  end

  defp bot_role_ids(nil), do: []

  defp bot_role_ids(bot_user) do
    bot_user
    |> Map.get("data", %{})
    |> Map.get("roles", [])
  end

  defp channel_type_name(0), do: "text"
  defp channel_type_name(2), do: "voice"
  defp channel_type_name(4), do: "category"
  defp channel_type_name(5), do: "announcement"
  defp channel_type_name(13), do: "stage"
  defp channel_type_name(15), do: "forum"
  defp channel_type_name(_type), do: "channel"

  defp format_synced_at(nil), do: "never"
  defp format_synced_at(""), do: "never"

  defp format_synced_at(synced_at) when is_binary(synced_at) do
    synced_at
    |> String.replace("T", " ")
    |> String.replace(~r/\.\d+.*/, "")
  end

  defp view_from_param("members"), do: :members
  defp view_from_param("roles"), do: :roles
  defp view_from_param("invites"), do: :invites
  defp view_from_param(_view), do: :channels
end
