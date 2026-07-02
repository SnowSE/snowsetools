defmodule SnowSeToolsWeb.Discord.DiscordChannelSyncModal do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeToolsWeb.Snow.SnowJwtCopy

  defstruct key: nil,
            channel: nil,
            assignment: nil,
            sync_token: "",
            syncing_roster?: false,
            open?: false,
            error: nil

  @state_assign :discord_channel_sync_modal_states

  def assign_component(socket, key, channel: channel) do
    state =
      fetch_state(socket.assigns, key) || %__MODULE__{key: key, channel: channel}

    state = %{state | channel: channel}

    socket
    |> put_state(key, state)
    |> maybe_attach_hooks()
  end

  def fetch_state(assigns, key) do
    assigns
    |> Map.get(@state_assign, %{})
    |> Map.get(key)
  end

  attr :state, __MODULE__, required: true
  attr :channel, :map, required: true
  attr :assignment, :any, default: nil

  def render(assigns) do
    ~H"""
    <div :if={@assignment}>
      <button
        type="button"
        phx-click="discord-channel-sync-modal:open"
        phx-value-key={@state.key}
        class="inline-flex items-center gap-2 rounded-md border border-slate-700 bg-slate-900/60 px-3 py-2 text-sm font-medium text-slate-200 transition hover:border-slate-500 hover:bg-slate-800"
      >
        <.icon name="hero-arrow-path" class="size-4" /> Sync roster
      </button>
    </div>

    <%= if @state.open? do %>
      <.modal
        id={"discord-channel-sync-modal-#{@state.key}"}
        on_close="discord-channel-sync-modal:close"
      >
        <div class="space-y-4">
          <div class="flex items-start justify-between gap-3">
            <div>
              <h3 class="text-lg font-semibold text-slate-100">Sync roster</h3>
              <p class="text-sm text-slate-400">{channel_name(@state.channel)}</p>
            </div>
            <button
              type="button"
              class="rounded-md border border-slate-700 px-2 py-1 text-xs text-slate-300"
              phx-click="discord-channel-sync-modal:close"
              phx-value-key={@state.key}
            >
              Close
            </button>
          </div>

          <div
            :if={@state.error}
            class="rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-200"
          >
            {@state.error}
          </div>

          <.form
            for={sync_form(@state)}
            id={"discord-channel-sync-form-#{@state.key}"}
            phx-change="discord-channel-sync-modal:sync_token"
            phx-submit="discord-channel-sync-modal:sync"
            phx-value-key={@state.key}
            class="space-y-4"
          >
            <.live_component
              module={SnowJwtCopy}
              id={"discord-channel-sync-jwt-#{@state.key}"}
              label="JWT token"
              name="snow_sync[jwt_token]"
              placeholder="Paste JWT from my.snow.edu"
              value={@state.sync_token}
              show_helper={true}
            />

            <div class="flex items-center justify-end gap-2">
              <button
                type="button"
                phx-click="discord-channel-sync-modal:close"
                phx-value-key={@state.key}
                class="rounded-md border border-slate-700 px-3 py-2 text-sm text-slate-300 transition hover:bg-slate-900"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={@state.syncing_roster?}
                class="inline-flex items-center gap-2 rounded-md border border-emerald-500/30 bg-emerald-500/15 px-3 py-2 text-sm font-semibold text-emerald-100 transition hover:bg-emerald-500/25 disabled:cursor-not-allowed disabled:opacity-60"
              >
                <.icon
                  name="hero-arrow-path"
                  class={if(@state.syncing_roster?, do: "size-4 animate-spin", else: "size-4")}
                />
                <%= if @state.syncing_roster? do %>
                  Syncing...
                <% else %>
                  Sync roster
                <% end %>
              </button>
            </div>
          </.form>
        </div>
      </.modal>
    <% end %>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_channel_sync_modal_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-channel-sync-modal:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("discord-channel-sync-modal:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_channel_sync_modal_hooks_attached?], true)
    end
  end

  defp hooked_event("discord-channel-sync-modal:open", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)
    {:halt, put_state(socket, key, %{state | open?: true, error: nil})}
  end

  defp hooked_event("discord-channel-sync-modal:close", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)

    {:halt,
     put_state(socket, key, %{
       state
       | open?: false,
         sync_token: "",
         error: nil
     })}
  end

  defp hooked_event("discord-channel-sync-modal:sync_token", %{"key" => key} = params, socket) do
    state = fetch_socket_state!(socket, key)
    value = sync_token_param(params)
    {:halt, put_state(socket, key, %{state | sync_token: value})}
  end

  defp hooked_event("discord-channel-sync-modal:sync", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)

    if is_map(state.assignment) and String.trim(state.sync_token) != "" do
      DiscordDomainManager.sync_course_roster(
        pid: self(),
        key: key,
        term_code: state.assignment["term_code"],
        crn: state.assignment["crn"],
        jwt_token: String.trim(state.sync_token)
      )

      {:halt, put_state(socket, key, %{state | syncing_roster?: true, error: nil})}
    else
      {:halt, put_state(socket, key, %{state | error: "Enter a JWT token before syncing."})}
    end
  end

  defp hooked_event("discord-channel-sync-modal:" <> rest, params, socket) do
    Logger.debug(
      "Unhandled discord-channel-sync-modal event discord-channel-sync-modal:#{rest} params=#{inspect(params)}"
    )

    {:halt, socket}
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  # -- info hooks --

  defp hooked_info({:discord, {:course_roster_synced, key, {:ok, _result}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        {:cont,
         put_state(socket, key, %{
           state
           | syncing_roster?: false,
             open?: false,
             sync_token: "",
             error: nil
         })}
    end
  end

  defp hooked_info({:discord, {:course_roster_synced, key, {:error, reason}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord course roster sync failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{state | syncing_roster?: false, error: "Roster sync failed."})}
    end
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  # -- helpers --

  defp fetch_socket_state!(socket, key) do
    fetch_state(socket.assigns, key) ||
      raise ArgumentError, "missing sync modal state for key #{inspect(key)}"
  end

  def put_state(socket, key, state) do
    states = Map.get(socket.assigns, @state_assign, %{})
    assign(socket, @state_assign, Map.put(states, key, state))
  end

  defp channel_name(channel), do: Map.get(channel || %{}, "name", "unnamed")

  defp sync_form(state) do
    to_form(%{"jwt_token" => state.sync_token || ""}, as: :snow_sync)
  end

  defp sync_token_param(%{"snow_sync" => %{"jwt_token" => value}}), do: value
  defp sync_token_param(%{"sync_token" => value}), do: value
  defp sync_token_param(%{"value" => value}), do: value
  defp sync_token_param(_params), do: ""
end
