defmodule SnowSeToolsWeb.Discord.DiscordChannelRow do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeTools.Snow.SnowCourseCacheDomainManager

  alias SnowSeToolsWeb.Discord.{
    DiscordChannelAssignModal,
    DiscordChannelSyncModal,
    DiscordStudentMapping
  }

  import SnowSeToolsWeb.Components.Expandable

  defstruct key: nil,
            channel: nil,
            assignment: nil,
            course: nil,
            loading_assignment?: true,
            loading_course?: true,
            removing_assignment?: false,
            error: nil,
            assignment_label: nil

  @state_assign :discord_channel_row_states

  def assign_component(socket, key, channel: channel) do
    state = fetch_state(socket.assigns, key) || %__MODULE__{key: key, channel: channel}
    state = %{state | channel: channel}

    socket
    |> put_state(key, state)
    |> maybe_attach_hooks()
    |> DiscordStudentMapping.assign_component(student_mapping_key(key), assignment: nil)
    |> DiscordChannelSyncModal.assign_component(key, channel: channel)
    |> maybe_request_assignment(key: key, channel: channel)
  end

  def fetch_state(assigns, key) do
    assigns
    |> Map.get(@state_assign, %{})
    |> Map.get(key)
  end

  attr :state, __MODULE__, required: true
  attr :mappings, :list, default: []
  attr :members, :list, default: []
  attr :roles, :list, default: []
  attr :student_mapping_state, :any, required: true
  attr :student_mapping_states, :map, default: %{}
  attr :student_row_states, :map, default: %{}
  attr :sync_modal_state, :any, required: true

  def render(assigns) do
    ~H"""
    <.expandable id={"discord-channel-row-#{@state.key}"}>
      <:title_row>
        <div class="flex min-w-0 flex-wrap items-center gap-2">
          <span class="truncate text-sm font-semibold text-slate-100">
            {channel_name(@state.channel)}
          </span>
          <span class="rounded-full border border-slate-800 bg-slate-950/70 px-2 py-0.5 text-xs text-slate-400">
            {channel_type(@state.channel)}
          </span>
          <span
            :if={private_channel?(@state.channel)}
            class="rounded-full bg-amber-500/10 px-2 py-0.5 text-xs text-amber-200"
          >
            private
          </span>
          <span
            :if={!private_channel?(@state.channel)}
            class="rounded-full bg-emerald-500/10 px-2 py-0.5 text-xs text-emerald-200"
          >
            public
          </span>
          <span
            :if={@state.assignment_label}
            class="rounded-full border border-indigo-500/20 bg-indigo-500/10 px-2 py-0.5 text-xs text-indigo-100"
          >
            {@state.assignment_label}
          </span>
          <span
            :if={@state.loading_assignment?}
            class="rounded-full border border-slate-800 bg-slate-950/70 px-2 py-0.5 text-xs text-slate-500"
          >
            loading
          </span>
        </div>
      </:title_row>

      <:body>
        <div
          :if={@state.error}
          class="mb-3 rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-200"
        >
          {@state.error}
        </div>

        <div class="space-y-4">
          <div class="flex flex-wrap items-center gap-2">
            <DiscordChannelAssignModal.render_button
              channel={@state.channel}
              assignment={@state.assignment}
            />

            <DiscordChannelSyncModal.render
              state={@sync_modal_state}
              channel={@state.channel}
              assignment={@state.assignment}
            />

            <button
              :if={@state.assignment}
              id={"discord-channel-remove-assignment-#{@state.key}"}
              type="button"
              phx-click="discord-channel-row:remove_assignment"
              phx-value-key={@state.key}
              disabled={@state.removing_assignment?}
              class="inline-flex items-center gap-2 rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm font-medium text-rose-100 transition hover:bg-rose-500/20 disabled:cursor-not-allowed disabled:opacity-60"
            >
              <.icon name="hero-x-mark" class="size-4" />
              <%= if @state.removing_assignment? do %>
                Removing...
              <% else %>
                Remove course assignment
              <% end %>
            </button>
          </div>

          <div :if={@state.assignment} class="rounded-md border border-slate-800 bg-slate-950/35 p-3">
            <div class="mb-2 flex flex-wrap items-center gap-2">
              <span class="text-sm font-medium text-slate-200">
                {course_name(@state.course) || @state.assignment["crn"]}
              </span>
              <span class="text-xs text-slate-500">
                {course_prefix(@state.course)} {@state.assignment["crn"]}
              </span>
            </div>

            <div class="mb-3 flex flex-wrap items-center gap-2 text-xs text-slate-500">
              <span>Term {@state.assignment["term_code"]}</span>
              <span>Role {@state.assignment["discord_role_id"]}</span>
              <span :if={@state.course}>Roster {Map.get(@state.course, "roster_count", 0)}</span>
            </div>

            <DiscordStudentMapping.render
              state={@student_mapping_state}
              mappings={@mappings}
              members={@members}
              roles={@roles}
              student_row_states={@student_row_states}
            />
          </div>
        </div>
      </:body>
    </.expandable>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_channel_row_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-channel-row:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("discord-channel-row:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_channel_row_hooks_attached?], true)
    end
  end

  defp hooked_event("discord-channel-row:remove_assignment", %{"key" => key}, socket) do
    case fetch_state(socket.assigns, key) do
      %{assignment: %{"crn" => crn}} = state ->
        DiscordDomainManager.delete_course_channel_assignment(pid: self(), key: key, crn: crn)

        {:halt,
         put_state(socket, key, %{
           state
           | removing_assignment?: true,
             error: nil
         })}

      nil ->
        Logger.error("Discord course assignment remove failed missing row state key=#{key}")
        {:halt, socket}

      state ->
        Logger.error(
          "Discord course assignment remove failed missing assignment key=#{key} state=#{inspect(state)}"
        )

        {:halt,
         put_state(socket, key, %{
           state
           | error: "Could not remove assignment."
         })}
    end
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  defp maybe_request_assignment(socket, key: key, channel: channel) do
    if LiveView.connected?(socket) do
      DiscordDomainManager.request_course_channel_assignment(
        pid: self(),
        key: key,
        channel_id: channel["id"]
      )
    end

    socket
  end

  # -- info hooks (assignment/course loading only) --

  defp hooked_info(
         {:discord, {:course_channel_assignment_loaded, key, {:ok, assignment}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        state = %{state | assignment: assignment, loading_assignment?: false, error: nil}
        socket = put_state(socket, key, state)

        socket =
          if is_map(assignment) do
            socket
            |> maybe_request_course(key, assignment)
            |> ensure_student_mapping_component(key, assignment)
            |> ensure_sync_modal_has_assignment(key, assignment)
          else
            ensure_student_mapping_component(socket, key, nil)
          end

        {:cont, compute_assignment_label(socket)}
    end
  end

  defp hooked_info({:discord, {:course_channel_assignment_loaded, key, {:error, reason}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord channel assignment load failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{
           state
           | loading_assignment?: false,
             error: "Could not load assignment."
         })}
    end
  end

  defp hooked_info({:discord, {:course_channel_assignment_saved, key, {:ok, _result}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        {:cont,
         put_state(socket, key, %{state | loading_assignment?: true})
         |> maybe_request_assignment(key: key, channel: state.channel)}
    end
  end

  defp hooked_info({:discord, {:course_channel_assignment_saved, key, {:error, reason}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord course assignment save failed reason=#{inspect(reason)}")

        {:cont, put_state(socket, key, %{state | error: "Could not save assignment."})}
    end
  end

  defp hooked_info({:discord, {:course_channel_assignment_deleted, key, {:ok, _crn}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        socket =
          socket
          |> put_state(key, %{
            state
            | assignment: nil,
              course: nil,
              loading_assignment?: false,
              loading_course?: false,
              removing_assignment?: false,
              error: nil,
              assignment_label: nil
          })
          |> ensure_student_mapping_component(key, nil)
          |> clear_sync_modal_assignment(key)

        {:cont, compute_assignment_label(socket)}
    end
  end

  defp hooked_info(
         {:discord, {:course_channel_assignment_deleted, key, {:error, reason}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord course assignment delete failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{
           state
           | removing_assignment?: false,
             error: "Could not remove assignment."
         })}
    end
  end

  defp hooked_info({:discord, {:course_roster_synced, key, _result}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        {:cont, ensure_student_mapping_component(socket, key, state.assignment)}
    end
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{channel: channel}} when is_map(channel) ->
        DiscordDomainManager.request_course_channel_assignment(
          pid: self(),
          key: key,
          channel_id: channel["id"]
        )

      _assign ->
        :ok
    end)

    {:cont, socket}
  end

  defp hooked_info({:snow_course_cache, {:course_loaded, key, {:ok, payload}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        course = Map.get(payload, :course)

        {:cont,
         put_state(socket, key, %{state | course: course, loading_course?: false, error: nil})
         |> compute_assignment_label()}
    end
  end

  defp hooked_info({:snow_course_cache, {:course_loaded, key, {:error, reason}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord course load failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{
           state
           | loading_course?: false,
             error: "Could not load course details."
         })}
    end
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  # -- helpers --

  defp maybe_request_course(socket, key, assignment) do
    if LiveView.connected?(socket) do
      SnowCourseCacheDomainManager.request_course(
        pid: self(),
        key: key,
        term_code: assignment["term_code"],
        crn: assignment["crn"]
      )
    end

    socket
  end

  defp ensure_student_mapping_component(socket, key, assignment) do
    DiscordStudentMapping.assign_component(socket, student_mapping_key(key),
      assignment: assignment
    )
  end

  defp ensure_sync_modal_has_assignment(socket, key, assignment) do
    sync_state =
      DiscordChannelSyncModal.fetch_state(socket.assigns, key) ||
        %DiscordChannelSyncModal{key: key}

    DiscordChannelSyncModal.put_state(socket, key, %{sync_state | assignment: assignment})
  end

  defp clear_sync_modal_assignment(socket, key) do
    sync_state =
      DiscordChannelSyncModal.fetch_state(socket.assigns, key) ||
        %DiscordChannelSyncModal{key: key}

    DiscordChannelSyncModal.put_state(socket, key, %{
      sync_state
      | assignment: nil,
        open?: false,
        error: nil
    })
  end

  defp compute_assignment_label(socket) do
    states = Map.get(socket.assigns, @state_assign, %{})

    updated_states =
      Enum.map(states, fn {k, state} -> {k, %{state | assignment_label: compute_label(state)}} end)
      |> Map.new()

    assign(socket, @state_assign, updated_states)
  end

  defp compute_label(%{assignment: nil}), do: nil

  defp compute_label(%{assignment: assignment, course: course}) do
    course_name = Map.get(course || %{}, "course_name") || assignment["crn"]
    "#{assignment["term_code"]} #{assignment["crn"]} #{course_name}"
  end

  defp student_mapping_key(key), do: "discord-student-mapping:#{key}"

  defp put_state(socket, key, state) do
    states = Map.get(socket.assigns, @state_assign, %{})
    assign(socket, @state_assign, Map.put(states, key, state))
  end

  # -- display helpers --

  defp course_name(nil), do: nil
  defp course_name(course), do: Map.get(course, "course_name")

  defp course_prefix(nil), do: ""

  defp course_prefix(course) do
    [
      Map.get(course, "subject_code", ""),
      Map.get(course, "course_number", ""),
      Map.get(course, "section_number", "")
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp channel_name(channel), do: Map.get(channel || %{}, "name", "unnamed")

  defp channel_type(channel) do
    case Map.get(channel || %{}, "data", %{}) |> Map.get("type") do
      0 -> "text"
      2 -> "voice"
      4 -> "category"
      5 -> "announcement"
      13 -> "stage"
      15 -> "forum"
      _ -> "channel"
    end
  end

  defp private_channel?(channel) do
    channel
    |> Map.get("data", %{})
    |> Map.get("permission_overwrites", [])
    |> Enum.any?(&(Map.get(&1, "type") == 0))
  end
end
