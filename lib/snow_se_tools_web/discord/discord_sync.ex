defmodule SnowSeToolsWeb.Discord.DiscordSync do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager

  defstruct key: nil,
            syncing?: false,
            error: nil

  def assign_component(socket, key) do
    socket
    |> assign_new(key, fn -> %__MODULE__{key: key} end)
    |> maybe_attach_hooks()
  end

  attr :state, __MODULE__, required: true

  def sync_button(assigns) do
    ~H"""
    <div id="discord-sync" class="flex flex-wrap items-center gap-2">
      <span
        :if={@state.error}
        id="discord-sync-error"
        class="rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-200"
      >
        {@state.error}
      </span>
      <button
        id="discord-sync-button"
        type="button"
        phx-click="discord-sync:sync"
        phx-value-key={@state.key}
        disabled={@state.syncing?}
        class={[
          "inline-flex h-10 items-center gap-2 rounded-md border px-4 text-sm font-medium transition-colors",
          @state.syncing? && "cursor-not-allowed border-slate-700 bg-slate-800/70 text-slate-400",
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
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_sync_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-sync:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("discord-sync:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_sync_hooks_attached?], true)
    end
  end

  defp hooked_event("discord-sync:sync", %{"key" => key}, socket) do
    widget_key = String.to_existing_atom(key)

    case Process.whereis(DiscordDomainManager) do
      nil ->
        Logger.error("Discord sync requested but DiscordDomainManager is not running")

        {:halt,
         socket
         |> assign(widget_key, %{
           socket.assigns[widget_key]
           | syncing?: false,
             error: "Discord service is not running."
         })
         |> LiveView.put_flash(:error, "Discord service is not running.")}

      _pid ->
        DiscordDomainManager.sync_all(pid: self())

        {:halt,
         assign(socket, widget_key, %{
           socket.assigns[widget_key]
           | syncing?: true,
             error: nil
         })}
    end
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  defp hooked_info({:discord, {:sync_finished, {:ok, _summary}}}, socket) do
    {:cont,
     socket
     |> update_sync_states(syncing?: false, error: nil)
     |> LiveView.put_flash(:info, "Discord data synced.")}
  end

  defp hooked_info({:discord, {:sync_finished, {:error, reasons}}}, socket) do
    Logger.error("Discord sync failed reasons=#{inspect(reasons)}")

    {:cont,
     socket
     |> update_sync_states(syncing?: false, error: Enum.join(reasons, "; "))
     |> LiveView.put_flash(:error, "Discord sync failed.")}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp update_sync_states(socket, syncing?: syncing?, error: error) do
    Enum.reduce(socket.assigns, socket, fn
      {key, %__MODULE__{} = state}, acc ->
        assign(acc, key, %{state | syncing?: syncing?, error: error})

      _assign, acc ->
        acc
    end)
  end
end
