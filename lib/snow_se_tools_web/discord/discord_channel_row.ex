defmodule SnowSeToolsWeb.Discord.DiscordChannelRow do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeTools.Snow.SnowCourseCacheDomainManager
  alias SnowSeToolsWeb.Discord.DiscordStudentMapping
  import SnowSeToolsWeb.Components.Expandable

  defstruct key: nil,
            channel: nil,
            assignment: nil,
            course: nil,
            course_options: [],
            course_query: "",
            selected_course: nil,
            loading_assignment?: true,
            loading_course?: true,
            loading_course_options?: false,
            assigning?: false,
            syncing_roster?: false,
            show_assign_modal?: false,
            show_sync_modal?: false,
            sync_token: "",
            error: nil

  @state_assign :discord_channel_row_states

  def assign_component(socket, key, channel: channel) do
    state = fetch_state(socket.assigns, key) || %__MODULE__{key: key, channel: channel}
    state = %{state | channel: channel}

    socket
    |> put_state(key, state)
    |> maybe_attach_hooks()
    |> DiscordStudentMapping.assign_component(student_mapping_key(key), assignment: nil)
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

    assigns =
      assign(
        assigns,
        :course_suggestions,
        course_suggestions(assigns.state.course_options, assigns.state.course_query)
      )

    ~H"""
    <.expandable id={"discord-channel-row-#{@state.key}"}>
      <:title_row>
        <div class="flex min-w-0 flex-wrap items-center gap-2">
          <span class="truncate text-sm font-semibold text-slate-100">
            #{channel_name(@state.channel)}
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
            <button
              :if={is_nil(@state.assignment)}
              type="button"
              phx-click="discord-channel-row:open_assign_modal"
              phx-value-key={@state.key}
              class="inline-flex items-center gap-2 rounded-md border border-indigo-500/30 bg-indigo-500/10 px-3 py-2 text-sm font-medium text-indigo-100 transition hover:bg-indigo-500/20"
            >
              <.icon name="hero-plus" class="size-4" /> Assign to course
            </button>

            <button
              :if={@state.assignment}
              type="button"
              phx-click="discord-channel-row:open_sync_modal"
              phx-value-key={@state.key}
              class="inline-flex items-center gap-2 rounded-md border border-slate-700 bg-slate-900/60 px-3 py-2 text-sm font-medium text-slate-200 transition hover:border-slate-500 hover:bg-slate-800"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Sync roster
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
              :if={@student_mapping_state}
              state={@student_mapping_state}
              mappings={@mappings}
              members={@members}
              roles={@roles}
              student_row_states={@student_row_states}
            />
          </div>
        </div>

        <%= if @state.show_assign_modal? do %>
          <.modal
            id={"discord-channel-assign-modal-#{@state.key}"}
            on_close="discord-channel-row:close_assign_modal"
          >
            <div class="space-y-4">
              <div class="flex items-start justify-between gap-3">
                <div>
                  <h3 class="text-lg font-semibold text-slate-100">Assign course</h3>
                  <p class="text-sm text-slate-400">{channel_name(@state.channel)}</p>
                </div>
                <button
                  type="button"
                  class="rounded-md border border-slate-700 px-2 py-1 text-xs text-slate-300"
                  phx-click="discord-channel-row:close_assign_modal"
                  phx-value-key={@state.key}
                >
                  Close
                </button>
              </div>

              <div :if={@state.loading_course_options?} class="text-sm text-slate-500">
                Loading course search...
              </div>

              <div :if={!@state.loading_course_options?}>
                <label class="mb-2 block text-sm font-medium text-slate-300">Search courses</label>
                <input
                  type="text"
                  name="course_query"
                  value={@state.course_query}
                  phx-input="discord-channel-row:course_query"
                  phx-value-key={@state.key}
                  placeholder="MATH 1010"
                  class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
                />

                <div class="mt-3 max-h-64 overflow-y-auto space-y-2">
                  <%= if @course_suggestions == [] do %>
                    <div class="rounded-md border border-slate-800 bg-slate-950/35 p-3 text-sm text-slate-500">
                      No matching courses found.
                    </div>
                  <% else %>
                    <%= for course <- @course_suggestions do %>
                      <button
                        type="button"
                        phx-click="discord-channel-row:select_course"
                        phx-value-key={@state.key}
                        phx-value-crn={course["crn"]}
                        class={[
                          "flex w-full flex-col gap-1 rounded-md border px-3 py-2 text-left transition",
                          @state.selected_course && @state.selected_course["crn"] == course["crn"] &&
                            "border-indigo-500/40 bg-indigo-500/10",
                          !(@state.selected_course && @state.selected_course["crn"] == course["crn"]) &&
                            "border-slate-800 bg-slate-950/45 hover:border-slate-700 hover:bg-slate-900/60"
                        ]}
                      >
                        <span class="text-sm font-medium text-slate-100">
                          {course_prefix(course)}
                        </span>
                        <span class="text-xs text-slate-500">
                          {course["course_name"]}
                        </span>
                      </button>
                    <% end %>
                  <% end %>
                </div>
              </div>

              <div class="flex items-center justify-end gap-2">
                <button
                  type="button"
                  phx-click="discord-channel-row:close_assign_modal"
                  phx-value-key={@state.key}
                  class="rounded-md border border-slate-700 px-3 py-2 text-sm text-slate-300 transition hover:bg-slate-900"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  phx-click="discord-channel-row:save_assignment"
                  phx-value-key={@state.key}
                  disabled={is_nil(@state.selected_course) || @state.assigning?}
                  class="inline-flex items-center gap-2 rounded-md border border-indigo-500/30 bg-indigo-500/15 px-3 py-2 text-sm font-semibold text-indigo-100 transition hover:bg-indigo-500/25 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  <.icon name="hero-check" class="size-4" />
                  <%= if @state.assigning? do %>
                    Assigning...
                  <% else %>
                    Assign course
                  <% end %>
                </button>
              </div>
            </div>
          </.modal>
        <% end %>

        <%= if @state.show_sync_modal? do %>
          <.modal
            id={"discord-channel-sync-modal-#{@state.key}"}
            on_close="discord-channel-row:close_sync_modal"
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
                  phx-click="discord-channel-row:close_sync_modal"
                  phx-value-key={@state.key}
                >
                  Close
                </button>
              </div>

              <label class="block space-y-2">
                <span class="text-sm font-medium text-slate-300">JWT token</span>
                <input
                  type="password"
                  name="sync_token"
                  value={@state.sync_token}
                  phx-input="discord-channel-row:sync_token"
                  phx-value-key={@state.key}
                  class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
                />
              </label>

              <div class="flex items-center justify-end gap-2">
                <button
                  type="button"
                  phx-click="discord-channel-row:close_sync_modal"
                  phx-value-key={@state.key}
                  class="rounded-md border border-slate-700 px-3 py-2 text-sm text-slate-300 transition hover:bg-slate-900"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  phx-click="discord-channel-row:sync_roster"
                  phx-value-key={@state.key}
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
            </div>
          </.modal>
        <% end %>
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

  defp hooked_event("discord-channel-row:open_assign_modal", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)
    socket = put_state(socket, key, %{state | show_assign_modal?: true, error: nil})
    socket = maybe_request_course_options(socket, key)
    {:halt, socket}
  end

  defp hooked_event("discord-channel-row:close_assign_modal", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)

    {:halt,
     put_state(socket, key, %{
       state
       | show_assign_modal?: false,
         course_query: "",
         selected_course: nil,
         error: nil
     })}
  end

  defp hooked_event("discord-channel-row:course_query", %{"key" => key} = params, socket) do
    state = fetch_socket_state!(socket, key)
    value = Map.get(params, "course_query") || Map.get(params, "value", "")
    {:halt, put_state(socket, key, %{state | course_query: value, selected_course: nil})}
  end

  defp hooked_event("discord-channel-row:select_course", %{"key" => key, "crn" => crn}, socket) do
    state = fetch_socket_state!(socket, key)
    selected_course = Enum.find(state.course_options, &(&1["crn"] == crn))
    {:halt, put_state(socket, key, %{state | selected_course: selected_course, error: nil})}
  end

  defp hooked_event("discord-channel-row:save_assignment", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)

    with %{selected_course: selected_course, channel: channel} <- state,
         true <- is_map(selected_course),
         role_id when is_binary(role_id) <- default_role_id(socket.assigns.roles) do
      DiscordDomainManager.save_course_channel_assignment(
        pid: self(),
        key: key,
        crn: selected_course["crn"],
        term_code: selected_course["term_code"],
        discord_channel_id: channel["id"],
        discord_role_id: role_id
      )

      {:halt, put_state(socket, key, %{state | assigning?: true, error: nil})}
    else
      _ ->
        {:halt, put_state(socket, key, %{state | error: "Select a course before saving."})}
    end
  end

  defp hooked_event("discord-channel-row:open_sync_modal", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)
    {:halt, put_state(socket, key, %{state | show_sync_modal?: true, error: nil})}
  end

  defp hooked_event("discord-channel-row:close_sync_modal", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)

    {:halt,
     put_state(socket, key, %{state | show_sync_modal?: false, sync_token: "", error: nil})}
  end

  defp hooked_event("discord-channel-row:sync_token", %{"key" => key} = params, socket) do
    state = fetch_socket_state!(socket, key)
    value = Map.get(params, "sync_token") || Map.get(params, "value", "")
    {:halt, put_state(socket, key, %{state | sync_token: value})}
  end

  defp hooked_event("discord-channel-row:sync_roster", %{"key" => key}, socket) do
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

  defp hooked_event("discord-channel-row:" <> rest, params, socket) do
    Logger.debug(
      "Unhandled discord-channel-row event discord-channel-row:#{rest} params=#{inspect(params)}"
    )

    {:halt, socket}
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

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
         socket
         |> put_state(key, %{
           state
           | assigning?: false,
             show_assign_modal?: false,
             course_query: "",
             selected_course: nil
         })
         |> maybe_request_assignment(key: key, channel: state.channel)}
    end
  end

  defp hooked_info({:discord, {:course_channel_assignment_saved, key, {:error, reason}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord course assignment save failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{state | assigning?: false, error: "Could not save assignment."})}
    end
  end

  defp hooked_info({:discord, {:course_roster_synced, key, {:ok, _result}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        {:cont,
         socket
         |> put_state(key, %{
           state
           | syncing_roster?: false,
             show_sync_modal?: false,
             sync_token: ""
         })
         |> ensure_student_mapping_component(key, state.assignment)}
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

  defp hooked_info({:snow_course_cache, {:term_courses_loaded, key, {:ok, payload}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        courses = Map.get(payload, :courses, [])

        {:cont,
         put_state(socket, key, %{
           state
           | course_options: courses,
             loading_course_options?: false,
             error: nil
         })}
    end
  end

  defp hooked_info({:snow_course_cache, {:term_courses_loaded, key, {:error, reason}}}, socket) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord term courses load failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{
           state
           | loading_course_options?: false,
             error: "Could not load course search."
         })}
    end
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

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

  defp maybe_request_course_options(socket, key) do
    state = fetch_socket_state!(socket, key)

    term_code =
      case state.assignment do
        %{} = assignment -> assignment["term_code"]
        _ -> infer_term_code(state.channel)
      end

    if LiveView.connected?(socket) and is_binary(term_code) and term_code != "" do
      SnowCourseCacheDomainManager.request_term_courses(
        pid: self(),
        key: key,
        term_code: term_code
      )

      put_state(socket, key, %{state | loading_course_options?: true})
    else
      put_state(socket, key, %{state | error: "Could not infer a term for this channel."})
    end
  end

  defp ensure_student_mapping_component(socket, key, assignment) do
    DiscordStudentMapping.assign_component(socket, student_mapping_key(key),
      assignment: assignment
    )
  end

  defp fetch_socket_state!(socket, key) do
    fetch_state(socket.assigns, key) ||
      raise ArgumentError, "missing discord channel row state for key #{inspect(key)}"
  end

  defp put_state(socket, key, state) do
    states = Map.get(socket.assigns, @state_assign, %{})
    assign(socket, @state_assign, Map.put(states, key, state))
  end

  defp student_mapping_key(key), do: "discord-student-mapping:#{key}"

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

  defp default_role_id(roles) do
    roles
    |> Enum.reject(&(&1["name"] == "@everyone"))
    |> Enum.sort_by(fn role -> Map.get(role["data"], "position", 0) end, :desc)
    |> List.first()
    |> case do
      nil -> nil
      role -> role["id"]
    end
  end

  defp infer_term_code(channel) do
    parts = String.split(channel_name(channel), "-", trim: true)

    Enum.find_value(Enum.with_index(parts), fn {part, index} ->
      case Integer.parse(part) do
        {year, ""} when year >= 2000 and year <= 2100 ->
          semester_code =
            case Enum.at(parts, index + 1) do
              "spring" -> "10"
              "summer" -> "30"
              "fall" -> "40"
              _ -> nil
            end

          if semester_code, do: "#{year}#{semester_code}", else: nil

        _ ->
          nil
      end
    end)
  end

  defp course_suggestions(courses, query) do
    query = normalize(query)

    courses
    |> Enum.filter(fn course ->
      search_fields = [
        Map.get(course, "crn", ""),
        Map.get(course, "subject_code", ""),
        Map.get(course, "course_number", ""),
        Map.get(course, "section_number", ""),
        Map.get(course, "course_name", ""),
        Map.get(course, "primary_instructor_name", "")
      ]

      query == "" or Enum.any?(search_fields, &String.contains?(normalize(&1), query))
    end)
    |> Enum.sort_by(fn course ->
      {
        Map.get(course, "subject_code", ""),
        Map.get(course, "course_number", ""),
        Map.get(course, "section_number", ""),
        Map.get(course, "crn", "")
      }
    end)
  end

  defp normalize(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\s+/, "")
  end

  defp normalize(_value), do: ""
end
