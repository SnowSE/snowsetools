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
            error: nil,
            editing_member_id: nil,
            edit_nickname_value: "",
            rename_loading?: false

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
        <div class="flex items-start gap-2">
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-medium text-slate-100">{member["name"]}</p>
            <div class="mt-0.5 flex items-center gap-1.5">
              <p class="truncate text-xs text-slate-500">
                {DiscordFormatting.member_username(member)}
              </p>
              <span
                :if={MapSet.member?(@mapped_discord_user_ids, member["id"])}
                class="shrink-0 rounded-full bg-emerald-500/20 px-1.5 py-0.5 text-[10px] font-medium text-emerald-200"
              >
                mapped
              </span>
            </div>
          </div>
          <%= if @state.editing_member_id != member["id"] do %>
            <button
              type="button"
              id={"discord-member-rename-#{member["id"]}"}
              phx-click="discord-members:start_edit"
              phx-value-member-id={member["id"]}
              class="shrink-0 rounded-lg border border-slate-700 p-1.5 text-slate-400 transition hover:border-slate-600 hover:text-slate-200"
            >
              <.icon name="hero-pencil" class="size-3.5" />
            </button>
           <% end %>
</div>

          <%= if @state.editing_member_id == member["id"] do %>
            <form
              id={"discord-member-rename-form-#{member["id"]}"}
              phx-submit="discord-members:save_nickname"
              phx-change="discord-members:validate_nickname"
              class="w-full pt-2"
            >
              <input type="hidden" name="member_id" value={member["id"]} />
              <div class="flex flex-col gap-1.5 w-full">
                <div class="flex items-center gap-2">
                  <label
                    for={"nickname-input-#{member["id"]}"}
                    class="text-[10px] font-medium text-slate-500"
                  >
                    Nickname
                  </label>
                  <span class="text-[10px] text-slate-600">{String.length(@state.edit_nickname_value)}/32</span>
                </div>
                <input
                  id={"nickname-input-#{member["id"]}"}
                  type="text"
                  name="nickname"
                  value={@state.edit_nickname_value}
                  maxlength="32"
                  placeholder="Server nickname"
                  autocomplete="off"
                  class={[
                    " rounded-md border border-slate-700 bg-slate-950 px-2 py-1 text-xs text-slate-100 placeholder-slate-600 outline-none transition",
                    "focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500/30",
                    @state.rename_loading? && "opacity-60"
                  ]}
                />
                <div class="flex items-center justify-end gap-1">
                  <button
                    type="button"
                    id={"discord-member-cancel-rename-#{member["id"]}"}
                    phx-click="discord-members:cancel_edit"
                    disabled={@state.rename_loading?}
                    class={[
                      "rounded-md border border-slate-700 px-2 py-1 text-[10px] font-medium text-slate-300 transition hover:bg-slate-800",
                      @state.rename_loading? && "cursor-not-allowed opacity-60"
                    ]}
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    id={"discord-member-save-rename-#{member["id"]}"}
                    disabled={@state.rename_loading?}
                    class={[
                      "rounded-md bg-indigo-600 px-2 py-1 text-[10px] font-medium text-white transition hover:bg-indigo-500",
                      @state.rename_loading? && "cursor-not-allowed opacity-60"
                    ]}
                  >
                    <%= if @state.rename_loading? do %>
                      Saving...
                    <% else %>
                      Save
                    <% end %>
                  </button>
                </div>
              </div>
            </form>
          <% end %>

      </article>
    </div>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_members_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-members:event", :handle_event, &hooked_event/3)
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

  defp hooked_event("discord-members:start_edit", %{"member-id" => member_id}, socket) do
    case Map.fetch(socket.assigns, :discord_members) do
      {:ok, %__MODULE__{members: members} = state} ->
        existing_nickname =
          members
          |> Enum.find(fn m -> m["id"] == member_id end)
          |> then(fn member ->
            member
            |> Map.get("data", %{})
            |> Map.get("nick", "")
            |> Kernel.||("")
          end)

        {:halt,
         assign(socket, :discord_members, %{
           state
           | editing_member_id: member_id,
             edit_nickname_value: existing_nickname,
             rename_loading?: false,
             error: nil
         })}

      _ ->
        {:halt, socket}
    end
  end

  defp hooked_event("discord-members:cancel_edit", _params, socket) do
    case Map.fetch(socket.assigns, :discord_members) do
      {:ok, %__MODULE__{} = state} ->
        {:halt,
         assign(socket, :discord_members, %{
           state
           | editing_member_id: nil,
             edit_nickname_value: "",
             error: nil
         })}

      _ ->
        {:halt, socket}
    end
  end

  defp hooked_event("discord-members:validate_nickname", params, socket) do
    member_id = Map.get(params, "member_id")
    nickname = String.slice(Map.get(params, "nickname", "") || "", 0, 32)

    case Map.fetch(socket.assigns, :discord_members) do
      {:ok, %__MODULE__{} = state} ->
        {:halt,
         assign(socket, :discord_members, %{
           state
           | editing_member_id: member_id,
             edit_nickname_value: nickname,
             error: nil
         })}

      _ ->
        {:halt, socket}
    end
  end

  defp hooked_event("discord-members:save_nickname", params, socket) do
    member_id = Map.get(params, "member_id")
    nickname = String.trim(Map.get(params, "nickname", "") || "")

    if nickname == "" do
      {:halt, put_in(socket.assigns.discord_members.error, "Nickname cannot be empty.")}
    else
      truncated = String.slice(nickname, 0, 32)

      DiscordDomainManager.rename_member(
        pid: self(),
        key: :discord_members,
        member_id: member_id,
        nickname: truncated
      )

      {:halt,
       assign(socket, :discord_members, %{
         socket.assigns.discord_members
         | rename_loading?: true,
           error: nil
       })}
    end
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  defp hooked_info({:discord, {:members_loaded, key, {:ok, members}}}, socket) do
    case Map.fetch(socket.assigns, key) do
      {:ok, %__MODULE__{} = state} ->
        {:cont, assign(socket, key, %{state | members: members, loading?: false, error: nil})}

      _ ->
        {:cont, socket}
    end
  end

  defp hooked_info({:discord, {:members_loaded, key, {:error, reason}}}, socket) do
    case Map.fetch(socket.assigns, key) do
      {:ok, %__MODULE__{} = state} ->
        Logger.error("Discord members failed reason=#{inspect(reason)}")

        {:cont,
         assign(socket, key, %{state | loading?: false, error: "Could not load Discord members."})}

      _ ->
        {:cont, socket}
    end
  end

  defp hooked_info({:discord, {:student_discord_mappings_loaded, key, {:ok, mappings}}}, socket) do
    case Map.fetch(socket.assigns, key) do
      {:ok, %__MODULE__{} = state} ->
        mapped_ids =
          mappings
          |> Enum.map(& &1["discord_user_id"])
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()

        {:cont, assign(socket, key, %{state | mapped_discord_user_ids: mapped_ids})}

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

  defp hooked_info({:discord, {:set_nickname_updated, :discord_members, {:ok, _}}}, socket) do
    {:cont,
     assign(socket, :discord_members, %{
       socket.assigns.discord_members
       | editing_member_id: nil,
         edit_nickname_value: "",
         rename_loading?: false,
         error: nil
     })}
  end

  defp hooked_info(
         {:discord, {:set_nickname_updated, :discord_members, {:error, reason}}},
         socket
       ) do
    Logger.error("Discord nickname update failed reason=#{inspect(reason)}")

    {:cont,
     assign(socket, :discord_members, %{
       socket.assigns.discord_members
       | rename_loading?: false,
         error: "Could not update nickname."
     })}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}
end
