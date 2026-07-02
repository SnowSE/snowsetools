defmodule SnowSeToolsWeb.Discord.DiscordChannelAssignModal do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeTools.Snow.SnowCourseCacheDomainManager

  defstruct key: nil,
            channel: nil,
            course_options: [],
            course_query: "",
            selected_course: nil,
            loading_course_options?: false,
            assigning?: false,
            open?: false,
            error: nil

  @state_assign :discord_channel_assign_modal_states

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
  attr :roles, :list, default: []

  def render(assigns) do
    ~H"""
    <div :if={!@assignment}>
      <button
        type="button"
        phx-click="discord-channel-assign-modal:open"
        phx-value-key={@state.key}
        class="inline-flex items-center gap-2 rounded-md border border-indigo-500/30 bg-indigo-500/10 px-3 py-2 text-sm font-medium text-indigo-100 transition hover:bg-indigo-500/20"
      >
        <.icon name="hero-plus" class="size-4" /> Assign to course
      </button>
    </div>
    """
  end

  attr :state, __MODULE__, required: true

  def modal_overlay(assigns) do
    assigns =
      assign(assigns, :course_suggestions, filter_courses(assigns.state, assigns))

    ~H"""
    <.modal
      id={"discord-channel-assign-modal-#{@state.key}"}
      on_close="discord-channel-assign-modal:close"
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
            phx-click="discord-channel-assign-modal:close"
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

        <div :if={@state.loading_course_options?} class="text-sm text-slate-500">
          Loading course search...
        </div>

        <div :if={!@state.loading_course_options?}>
          <label class="mb-2 block text-sm font-medium text-slate-300">Search courses</label>
          <input
            type="text"
            name="course_query"
            value={@state.course_query}
            phx-input="discord-channel-assign-modal:course_query"
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
                  phx-click="discord-channel-assign-modal:select_course"
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
            phx-click="discord-channel-assign-modal:close"
            phx-value-key={@state.key}
            class="rounded-md border border-slate-700 px-3 py-2 text-sm text-slate-300 transition hover:bg-slate-900"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click="discord-channel-assign-modal:save"
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
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_channel_assign_modal_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook(
        "discord-channel-assign-modal:event",
        :handle_event,
        &hooked_event/3
      )
      |> LiveView.attach_hook("discord-channel-assign-modal:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_channel_assign_modal_hooks_attached?], true)
    end
  end

  defp hooked_event("discord-channel-assign-modal:open", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)
    socket = put_state(socket, key, %{state | open?: true, error: nil})
    {:halt, maybe_request_course_options(socket, key)}
  end

  defp hooked_event("discord-channel-assign-modal:close", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)

    {:halt,
     put_state(socket, key, %{
       state
       | open?: false,
         course_query: "",
         selected_course: nil,
         error: nil
     })}
  end

  defp hooked_event("discord-channel-assign-modal:course_query", %{"key" => key} = params, socket) do
    state = fetch_socket_state!(socket, key)
    value = Map.get(params, "course_query") || Map.get(params, "value", "")
    {:halt, put_state(socket, key, %{state | course_query: value, selected_course: nil})}
  end

  defp hooked_event(
         "discord-channel-assign-modal:select_course",
         %{"key" => key, "crn" => crn},
         socket
       ) do
    state = fetch_socket_state!(socket, key)
    selected_course = Enum.find(state.course_options, &(&1["crn"] == crn))
    {:halt, put_state(socket, key, %{state | selected_course: selected_course, error: nil})}
  end

  defp hooked_event("discord-channel-assign-modal:save", %{"key" => key}, socket) do
    state = fetch_socket_state!(socket, key)

    with %{selected_course: selected_course, channel: channel} <- state,
         true <- is_map(selected_course),
         role_id when is_binary(role_id) <- find_default_role_id(socket.assigns[:roles] || []) do
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

  defp hooked_event("discord-channel-assign-modal:" <> rest, params, socket) do
    Logger.debug(
      "Unhandled discord-channel-assign-modal event discord-channel-assign-modal:#{rest} params=#{inspect(params)}"
    )

    {:halt, socket}
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  # -- info hooks --

  defp hooked_info(
         {:discord, {:course_channel_assignment_saved, key, {:ok, _result}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        {:cont,
         put_state(socket, key, %{
           state
           | assigning?: false,
             open?: false,
             course_query: "",
             selected_course: nil,
             error: nil
         })}
    end
  end

  defp hooked_info(
         {:discord, {:course_channel_assignment_saved, key, {:error, reason}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord course assignment save failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{state | assigning?: false, error: "Could not save assignment."})}
    end
  end

  defp hooked_info(
         {:discord, {:course_channel_assignment_loaded, key, {:ok, _assignment}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        {:cont, put_state(socket, key, %{state | error: nil})}
    end
  end

  defp hooked_info(
         {:discord, {:course_channel_assignment_loaded, _key, {:error, reason}}},
         socket
       ) do
    Logger.warning("Discord assignment load failed in modal: #{inspect(reason)}")
    {:cont, socket}
  end

  defp hooked_info(
         {:snow_course_cache, {:term_courses_loaded, key, {:ok, payload}}},
         socket
       ) do
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

  defp hooked_info(
         {:snow_course_cache, {:term_courses_loaded, key, {:error, reason}}},
         socket
       ) do
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

  # -- helpers --

  defp maybe_request_course_options(socket, key) do
    state = fetch_socket_state!(socket, key)
    term_code = infer_term_code(state.channel)

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

  defp filter_courses(state, _assigns) do
    state.course_options
    |> Enum.filter(fn course ->
      query = normalize(state.course_query)

      query == "" or
        Enum.any?(
          [
            Map.get(course, "crn", ""),
            Map.get(course, "subject_code", ""),
            Map.get(course, "course_number", ""),
            Map.get(course, "section_number", ""),
            Map.get(course, "course_name", ""),
            Map.get(course, "primary_instructor_name", "")
          ],
          &String.contains?(normalize(&1), query)
        )
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

  defp find_default_role_id(roles) do
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

  defp fetch_socket_state!(socket, key) do
    fetch_state(socket.assigns, key) ||
      raise ArgumentError, "missing assign modal state for key #{inspect(key)}"
  end

  defp put_state(socket, key, state) do
    states = Map.get(socket.assigns, @state_assign, %{})
    assign(socket, @state_assign, Map.put(states, key, state))
  end

  defp channel_name(channel), do: Map.get(channel || %{}, "name", "unnamed")

  defp course_prefix(course) do
    [
      Map.get(course, "subject_code", ""),
      Map.get(course, "course_number", ""),
      Map.get(course, "section_number", "")
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp normalize(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\s+/, "")
  end

  defp normalize(_value), do: ""
end
