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
            error: nil

  @state_assign :discord_channel_row_states

  def assign_component(socket, key, channel: channel) do
    state = fetch_state(socket.assigns, key) || %__MODULE__{key: key, channel: channel}
    state = %{state | channel: channel}

    socket
    |> put_state(key, state)
    |> maybe_attach_hooks()
    |> DiscordStudentMapping.assign_component(student_mapping_key(key), assignment: nil)
    |> DiscordChannelAssignModal.assign_component(key, channel: channel)
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
  attr :student_mapping_states, :map, default: %{}
  attr :student_row_states, :map, default: %{}
  attr :assign_modal_states, :map, default: %{}
  attr :sync_modal_states, :map, default: %{}

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :assignment_label,
        assignment_label(assigns.state.assignment, assigns.state.course)
      )

    assigns =
      assign(
        assigns,
        :student_mapping_state,
        DiscordStudentMapping.fetch_state(
          %{:discord_student_mapping_states => assigns.student_mapping_states},
          student_mapping_key(assigns.state.key)
        ) ||
          %DiscordStudentMapping{
            key: student_mapping_key(assigns.state.key),
            assignment: assigns.state.assignment
          }
      )

    assign_modal_state =
      DiscordChannelAssignModal.fetch_state(
        assigns.assign_modal_states,
        assigns.state.key
      ) || %DiscordChannelAssignModal{key: assigns.state.key, channel: assigns.state.channel}

    sync_modal_state =
      DiscordChannelSyncModal.fetch_state(
        assigns.sync_modal_states,
        assigns.state.key
      ) || %DiscordChannelSyncModal{key: assigns.state.key, channel: assigns.state.channel}

    assigns = assign(assigns, :assign_modal_state, assign_modal_state)
    assigns = assign(assigns, :sync_modal_state, sync_modal_state)

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
            :if={@assignment_label}
            class="rounded-full border border-indigo-500/20 bg-indigo-500/10 px-2 py-0.5 text-xs text-indigo-100"
          >
            {@assignment_label}
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
            <DiscordChannelAssignModal.render
              state={@assign_modal_state}
              channel={@state.channel}
              assignment={@state.assignment}
              roles={@roles}
            />

            <DiscordChannelSyncModal.render
              state={@sync_modal_state}
              channel={@state.channel}
              assignment={@state.assignment}
            />
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
              :if={@student_mapping_state}
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

    <DiscordChannelAssignModal.modal_overlay
      :if={@assign_modal_state.open?}
      state={@assign_modal_state}
    />

    <DiscordChannelSyncModal.modal_overlay
      :if={@sync_modal_state.open?}
      state={@sync_modal_state}
    />
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_channel_row_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-channel-row:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_channel_row_hooks_attached?], true)
    end
  end

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

        {:cont, socket}
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
         put_state(socket, key, %{state | course: course, loading_course?: false, error: nil})}
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

  defp assignment_label(nil, _course), do: nil

  defp assignment_label(assignment, course) do
    course_name = Map.get(course || %{}, "course_name") || assignment["crn"]
    "#{assignment["term_code"]} #{assignment["crn"]} #{course_name}"
  end
end
