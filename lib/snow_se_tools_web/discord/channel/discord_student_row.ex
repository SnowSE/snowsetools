defmodule SnowSeToolsWeb.Discord.DiscordStudentRow do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeToolsWeb.Discord.DiscordFormatting

  defstruct key: nil,
            search_text: "",
            showing_assign_panel?: false,
            confirming_unassign?: false,
            assigning_role?: false,
            error: nil

  @state_assign :discord_student_row_states

  def assign_component(socket, key) do
    socket
    |> put_state_if_missing(key)
    |> maybe_attach_hooks()
  end

  def fetch_state(assigns, key) do
    assigns
    |> Map.get(@state_assign, %{})
    |> Map.get(key)
  end

  attr :state, __MODULE__, required: true
  attr :student, :map, required: true
  attr :mapping, :any, default: nil
  attr :is_mapped, :boolean, required: true
  attr :required_role_id, :any, default: nil
  attr :members, :list, default: []
  attr :roles, :list, default: []
  attr :mapped_discord_user_ids, :map, required: true

  def render(assigns) do
    assigns = assign(assigns, :discord_member, discord_member(assigns.members, assigns.mapping))

    assigns =
      assign(assigns, :required_role, required_role(assigns.roles, assigns.required_role_id))

    assigns = assign(assigns, :visible_members, visible_members(assigns))

    ~H"""
    <div
      id={"discord-student-row-#{@student["badger_id"] || @student["first_name"]}-#{@state.key}"}
      class="rounded-md border border-slate-800 bg-slate-950/45 p-3"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="min-w-0">
          <p class="truncate text-sm font-medium text-slate-100">
            {@student["first_name"]} {@student["last_name"]}
          </p>
          <p class="truncate text-xs text-slate-500">
            {@student["email"] || @student["badger_id"] || "student"}
          </p>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <button
            :if={!@is_mapped}
            type="button"
            phx-click="discord-student-row:toggle_assign_panel"
            phx-value-key={@state.key}
            phx-value-first-name={@student["first_name"] || ""}
            class="rounded-md border border-indigo-500/30 bg-indigo-500/10 px-3 py-1.5 text-xs font-medium text-indigo-100 transition hover:bg-indigo-500/20"
          >
            {if @state.showing_assign_panel?, do: "Hide Search Panel", else: "Match to Discord User"}
          </button>

          <button
            :if={@is_mapped && @state.confirming_unassign?}
            type="button"
            phx-click="discord-student-row:confirm_unassign"
            phx-value-key={@state.key}
            phx-value-badger-id={@student["badger_id"]}
            class="rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-1.5 text-xs font-medium text-rose-100 transition hover:bg-rose-500/20"
          >
            Yes, unassign
          </button>

          <button
            :if={@is_mapped && !@state.confirming_unassign?}
            type="button"
            phx-click="discord-student-row:request_unassign"
            phx-value-key={@state.key}
            phx-value-badger-id={@student["badger_id"]}
            class="rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-1.5 text-xs font-medium text-rose-100 transition hover:bg-rose-500/20"
          >
            Unassign
          </button>

          <button
            :if={
              @is_mapped && @discord_member && @required_role &&
                !has_required_role?(@discord_member, @required_role)
            }
            type="button"
            phx-click="discord-student-row:add_role"
            phx-value-key={@state.key}
            phx-value-member-id={@discord_member["id"]}
            phx-value-role-id={@required_role["id"]}
            disabled={@state.assigning_role?}
            class="rounded-md border border-emerald-500/30 bg-emerald-500/10 px-3 py-1.5 text-xs font-medium text-emerald-100 transition hover:bg-emerald-500/20 disabled:cursor-not-allowed disabled:opacity-60"
          >
            <%= if @state.assigning_role? do %>
              Adding role...
            <% else %>
              Add {@required_role["name"]}
            <% end %>
          </button>
        </div>
      </div>

      <div
        :if={@state.error}
        class="mt-2 rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-200"
      >
        {@state.error}
      </div>

      <div
        :if={@is_mapped && @discord_member}
        class="mt-2 rounded-md border border-slate-800 bg-slate-900/50 p-3"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-slate-100">
              {@discord_member["name"]}
            </p>
            <p class="truncate text-xs text-slate-500">
              {DiscordFormatting.member_username(@discord_member)}
            </p>
          </div>
          <div class="text-xs uppercase tracking-wide text-slate-500">discord user</div>
        </div>

        <div class="mt-2 flex flex-wrap items-center gap-2">
          <%= if has_required_role?(@discord_member, @required_role) do %>
            <span class="rounded-full bg-emerald-500/15 px-2.5 py-1 text-xs font-medium text-emerald-200">
              ✓ Has {role_label(@required_role)}
            </span>
          <% else %>
            <span class="rounded-full bg-amber-500/15 px-2.5 py-1 text-xs font-medium text-amber-200">
              ⚠ Missing role
            </span>
          <% end %>

          <%= for role <- member_roles(@discord_member, @roles) do %>
            <span class="rounded-full border border-slate-700 bg-slate-900/60 px-2.5 py-1 text-xs text-slate-300">
              {role["name"]}
            </span>
          <% end %>
        </div>
      </div>

      <div :if={@is_mapped && !@discord_member} class="mt-2 text-sm text-rose-200">
        Discord user not found
      </div>

      <div
        :if={@state.showing_assign_panel?}
        id={"discord-student-row-assign-panel-#{@state.key}"}
        class="mt-3 rounded-md border border-slate-800 bg-slate-900/50 p-3"
      >
        <label class="mb-2 block text-sm font-medium text-slate-300">Assign to Discord User</label>
        <form
          id={"discord-student-row-search-form-#{@state.key}"}
          phx-change="discord-student-row:search"
          phx-value-key={@state.key}
        >
          <input
            id={"discord-student-row-search-input-#{@state.key}"}
            type="text"
            name="search_text"
            value={@state.search_text}
            placeholder="Search by name or id..."
            class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
          />
        </form>
        <div class="mt-3 max-h-64 overflow-y-auto">
          <%= if @visible_members == [] do %>
            <div class="py-3 text-center text-sm text-slate-500">No unassigned users found.</div>
          <% else %>
            <%= for member <- @visible_members do %>
              <button
                id={"discord-student-row-member-option-#{@state.key}-#{member["id"]}"}
                type="button"
                phx-click="discord-student-row:assign"
                phx-value-key={@state.key}
                phx-value-badger-id={@student["badger_id"]}
                phx-value-discord-user-id={member["id"]}
                class="flex w-full flex-col gap-1 rounded-md px-2 py-2 text-left transition hover:bg-slate-800/60"
              >
                <span class="truncate text-sm text-slate-100">{member["name"]}</span>
                <span class="truncate text-xs text-slate-500">
                  {DiscordFormatting.member_username(member)}
                </span>
              </button>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_student_row_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-student-row:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("discord-student-row:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_student_row_hooks_attached?], true)
    end
  end

  defp hooked_event(
         "discord-student-row:toggle_assign_panel",
         %{"key" => key, "first-name" => first_name},
         socket
       ) do
    state = fetch_socket_state!(socket, key)

    {:halt,
     put_state(socket, key, %{
       state
       | showing_assign_panel?: !state.showing_assign_panel?,
         search_text: if(state.showing_assign_panel?, do: state.search_text, else: first_name),
         error: nil
     })}
  end

  defp hooked_event(
         "discord-student-row:search",
         %{"key" => key} = params,
         socket
       ) do
    state = fetch_socket_state!(socket, key)
    value = Map.get(params, "search_text") || Map.get(params, "value", "")

    {:halt, put_state(socket, key, %{state | search_text: value})}
  end

  defp hooked_event(
         "discord-student-row:assign",
         %{
           "key" => key,
           "badger-id" => badger_id,
           "discord-user-id" => discord_user_id
         },
         socket
       ) do
    DiscordDomainManager.save_student_discord_mapping(
      pid: self(),
      key: key,
      badger_id: badger_id,
      discord_user_id: discord_user_id
    )

    state = fetch_socket_state!(socket, key)

    {:halt,
     put_state(socket, key, %{state | showing_assign_panel?: false, search_text: "", error: nil})}
  end

  defp hooked_event(
         "discord-student-row:request_unassign",
         %{"key" => key},
         socket
       ) do
    state = fetch_socket_state!(socket, key)
    {:halt, put_state(socket, key, %{state | confirming_unassign?: true, error: nil})}
  end

  defp hooked_event(
         "discord-student-row:confirm_unassign",
         %{"key" => key, "badger-id" => badger_id},
         socket
       ) do
    DiscordDomainManager.delete_student_discord_mapping(
      pid: self(),
      key: key,
      badger_id: badger_id
    )

    state = fetch_socket_state!(socket, key)
    {:halt, put_state(socket, key, %{state | confirming_unassign?: false, error: nil})}
  end

  defp hooked_event(
         "discord-student-row:add_role",
         %{"key" => key, "member-id" => member_id, "role-id" => role_id},
         socket
       ) do
    DiscordDomainManager.add_role_to_member(
      pid: self(),
      key: key,
      member_id: member_id,
      role_id: role_id
    )

    state = fetch_socket_state!(socket, key)
    {:halt, put_state(socket, key, %{state | assigning_role?: true, error: nil})}
  end

  defp hooked_event("discord-student-row:" <> rest, params, socket) do
    Logger.debug(
      "Unhandled discord-student-row event discord-student-row:#{rest} params=#{inspect(params)}"
    )

    {:halt, socket}
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  defp hooked_info({:discord, {:student_discord_mapping_saved, key, {:ok, _result}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        {:cont, put_state(socket, key, %{state | showing_assign_panel?: false, error: nil})}
    end
  end

  defp hooked_info({:discord, {:student_discord_mapping_saved, key, {:error, reason}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord student mapping save failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{
           state
           | error: "Could not save Discord mapping.",
             showing_assign_panel?: false
         })}
    end
  end

  defp hooked_info({:discord, {:student_discord_mapping_deleted, key, {:ok, _badger_id}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        {:cont, put_state(socket, key, %{state | confirming_unassign?: false, error: nil})}
    end
  end

  defp hooked_info({:discord, {:student_discord_mapping_deleted, key, {:error, reason}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord student mapping delete failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{
           state
           | confirming_unassign?: false,
             error: "Could not remove mapping."
         })}
    end
  end

  defp hooked_info({:discord, {:member_role_added, key, {:ok, _result}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        {:cont, put_state(socket, key, %{state | assigning_role?: false, error: nil})}
    end
  end

  defp hooked_info({:discord, {:member_role_added, key, {:error, reason}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord role assignment failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{
           state
           | assigning_role?: false,
             error: "Could not add required role."
         })}
    end
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp discord_member(_members, nil), do: nil

  defp discord_member(members, mapping) do
    Enum.find(members, fn member -> member["id"] == mapping["discord_user_id"] end)
  end

  defp required_role(_roles, nil), do: nil
  defp required_role(roles, role_id), do: Enum.find(roles, fn role -> role["id"] == role_id end)

  defp visible_members(assigns) do
    members = assigns.members || []
    mapped_ids = assigns.mapped_discord_user_ids
    search = normalize(assigns.state.search_text)

    members
    |> Enum.reject(fn member -> MapSet.member?(mapped_ids, member["id"]) end)
    |> Enum.filter(fn member ->
      search == "" or
        String.contains?(normalize(member["name"] || ""), search) or
        String.contains?(normalize(DiscordFormatting.member_username(member)), search) or
        String.contains?(normalize(member["id"] || ""), search)
    end)
    |> Enum.sort_by(fn member -> String.downcase(member["name"] || "") end)
  end

  defp member_roles(member, roles) do
    member_role_ids =
      member
      |> Map.get("data", %{})
      |> Map.get("roles", [])
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    roles
    |> Enum.reject(&(&1["name"] == "@everyone"))
    |> Enum.filter(fn role -> MapSet.member?(member_role_ids, role["id"]) end)
    |> Enum.sort_by(fn role -> Map.get(role["data"], "position", 0) end)
  end

  defp has_required_role?(_member, nil), do: true

  defp has_required_role?(member, required_role) do
    member_role_ids =
      member
      |> Map.get("data", %{})
      |> Map.get("roles", [])
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    required_role_id = required_role["id"]
    required_role["name"] == "@everyone" or MapSet.member?(member_role_ids, required_role_id)
  end

  defp role_label(nil), do: "role"
  defp role_label(role), do: role["name"] || "role"

  defp normalize(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\s+/, "")
  end

  defp normalize(_value), do: ""

  defp fetch_socket_state!(socket, key) do
    fetch_state(socket.assigns, key) ||
      raise ArgumentError, "missing discord student row state for key #{inspect(key)}"
  end

  defp put_state_if_missing(socket, key) do
    case fetch_state(socket.assigns, key) do
      nil -> put_state(socket, key, %__MODULE__{key: key})
      _state -> socket
    end
  end

  defp put_state(socket, key, state) do
    states = Map.get(socket.assigns, @state_assign, %{})
    assign(socket, @state_assign, Map.put(states, key, state))
  end
end
