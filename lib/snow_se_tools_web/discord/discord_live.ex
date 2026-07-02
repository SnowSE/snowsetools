defmodule SnowSeToolsWeb.Discord.DiscordLive do
  use SnowSeToolsWeb, :live_view
  require Logger

  alias SnowSeTools.Discord.DiscordPubSub

  alias SnowSeToolsWeb.Discord.{
    DiscordChannels,
    DiscordInvites,
    DiscordMembers,
    DiscordRoles,
    DiscordServerStatus,
    DiscordStudentMappings,
    DiscordSync
  }

  on_mount {SnowSeToolsWeb.UserAuth, :ensure_authenticated}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      DiscordPubSub.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, "Discord")
     |> assign(:active_view, :channels)
     |> DiscordSync.assign_component(:discord_sync)
     |> DiscordServerStatus.assign_component(:discord_server_status)
     |> DiscordChannels.assign_component(:discord_channels)
     |> DiscordStudentMappings.assign_component(:discord_student_mappings)
     |> DiscordMembers.assign_component(:discord_members)
     |> DiscordRoles.assign_component(:discord_roles)
     |> DiscordInvites.assign_component(:discord_invites)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <main
        id="discord-page"
        class="mx-auto flex h-full min-h-0 w-full max-w-[1800px] flex-col gap-5 p-4"
      >
        <section class="shrink-0 ">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div class="min-w-0">
              <h1 class="mt-1 text-2xl font-semibold text-slate-100">Discord Overview</h1>
            </div>

            <DiscordSync.sync_button state={@discord_sync} />
          </div>
        </section>

        <section class=" flex-1 gap-4 flex flex-row min-h-0">
          <div class="flex min-h-0 flex-1 flex-col pr-1">
            <div id="discord-view-tabs" class="mb-3 flex flex-wrap gap-2">
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
                phx-click="discord:switch_view"
                phx-value-view={view}
                class={[
                  "rounded-md border px-3 py-1.5 text-sm font-medium transition-colors",
                  @active_view == view &&
                    "border-indigo-400/60 bg-indigo-500/15 text-indigo-100",
                  @active_view != view &&
                    "border-slate-800 bg-slate-950/40 text-slate-400 hover:border-slate-700 hover:text-slate-200"
                ]}
              >
                {label}
              </button>
            </div>

            <div class="min-h-0 flex-1 overflow-y-auto">
              <%= case @active_view do %>
                <% :channels -> %>
                  <DiscordChannels.render
                    state={@discord_channels}
                    members={@discord_members}
                    roles={@discord_roles}
                    student_mappings={@discord_student_mappings}
                    channel_row_states={Map.get(assigns, :discord_channel_row_states, %{})}
                    student_mapping_states={Map.get(assigns, :discord_student_mapping_states, %{})}
                    student_row_states={Map.get(assigns, :discord_student_row_states, %{})}
                  />
                <% :members -> %>
                  <DiscordMembers.render state={@discord_members} />
                <% :roles -> %>
                  <DiscordRoles.render state={@discord_roles} />
                <% :invites -> %>
                  <DiscordInvites.render state={@discord_invites} />
              <% end %>
            </div>
          </div>

          <aside class={[
            "flex min-h-0 flex-col gap-4 overflow-y-auto border-t border-slate-800 pt-4"
          ]}>
            <DiscordServerStatus.render state={@discord_server_status} />
            <DiscordInvites.side_panel state={@discord_invites} />
          </aside>
        </section>
      </main>
    </Layouts.app>
    """
  end

  def handle_event("discord:switch_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, :active_view, view_from_param(view))}
  end

  def handle_info({:discord, _message}, socket), do: {:noreply, socket}

  def handle_info({:snow_course_cache, _message}, socket), do: {:noreply, socket}

  def handle_info(message, socket) do
    Logger.warning("Unhandled DiscordLive message: #{inspect(message)}")
    {:noreply, socket}
  end

  defp view_from_param("members"), do: :members
  defp view_from_param("roles"), do: :roles
  defp view_from_param("invites"), do: :invites
  defp view_from_param(_view), do: :channels
end
