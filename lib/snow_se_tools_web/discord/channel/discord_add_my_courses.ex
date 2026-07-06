defmodule SnowSeToolsWeb.Discord.DiscordAddMyCourses do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeToolsWeb.Discord.DiscordGraduationHelpers

  defstruct key: nil,
            open?: false,
            selected_course: nil,
            creating?: false,
            error: nil,
            form: %{}

  @state_assign :discord_add_my_courses

  def assign_component(socket, key) do
    state = fetch_state(socket.assigns) || %__MODULE__{key: key}

    socket
    |> put_state(state)
    |> maybe_attach_hooks()
  end

  def fetch_state(assigns), do: Map.get(assigns, @state_assign)

  attr :state, __MODULE__, required: true
  attr :courses_by_term, :map, default: %{}
  attr :channels, :list, default: []
  attr :roles, :list, default: []

  def render(assigns) do
    assigns =
      assigns
      |> assign(:sorted_terms, sorted_terms(assigns.courses_by_term))
      |> assign(:channel_groups, channel_groups(assigns.channels))
      |> assign(:filtered_courses, filtered_courses(assigns.state, assigns.courses_by_term))

    ~H"""
    <div id="discord-add-my-courses">
      <button
        id="discord-add-my-courses-open"
        type="button"
        phx-click="discord-add-my-courses:open"
        class="inline-flex items-center gap-2 rounded-md border border-emerald-500/30 bg-emerald-500/10 px-3 py-2 text-sm font-semibold text-emerald-100 transition hover:bg-emerald-500/20"
      >
        <.icon name="hero-plus" class="size-4" /> Add my courses
      </button>

      <%= if @state.open? do %>
        <.modal id="discord-add-my-courses-modal" on_close="discord-add-my-courses:close">
          <div class="space-y-4">
            <div class="flex items-start justify-between gap-3">
              <div>
                <h3 class="text-lg font-semibold text-slate-100">Add my courses</h3>
                <p class="text-sm text-slate-400">
                  Pick a cached Snow course and place its Discord channel in a channel group.
                </p>
              </div>
              <button
                type="button"
                class="rounded-md border border-slate-700 px-2 py-1 text-xs text-slate-300"
                phx-click="discord-add-my-courses:close"
              >
                Close
              </button>
            </div>

            <div
              :if={@state.error}
              id="discord-add-my-courses-error"
              class="rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-200"
            >
              {@state.error}
            </div>

            <form id="discord-add-my-courses-form" phx-change="discord-add-my-courses:form:change">
              <div>
                <label class="mb-2 block text-sm font-medium text-slate-300">Term</label>
                <select
                  id="discord-add-my-courses-term"
                  name="add_my_courses[selected_term]"
                  class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20"
                >
                  <option value="">Select a term...</option>
                  <option
                    :for={term <- @sorted_terms}
                    value={term.code}
                    selected={Map.get(@state.form, "selected_term") == term.code}
                  >
                    {term.display}
                  </option>
                </select>
              </div>

              <div class="mt-3">
                <label class="mb-2 block text-sm font-medium text-slate-300">Search courses</label>
                <input
                  id="discord-add-my-courses-query"
                  type="text"
                  name="add_my_courses[course_query]"
                  value={Map.get(@state.form, "course_query", "")}
                  placeholder="ENGR 1010, professor, CRN"
                  phx-debounce="200"
                  class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20"
                />
              </div>

              <div class="max-h-72 space-y-2 overflow-y-auto">
                <%= cond do %>
                  <% Map.get(@state.form, "selected_term") in [nil, ""] -> %>
                    <div class="rounded-md border border-slate-800 bg-slate-950/35 p-3 text-sm text-slate-500">
                      Select a term to search cached courses.
                    </div>
                  <% @filtered_courses == [] -> %>
                    <div class="rounded-md border border-slate-800 bg-slate-950/35 p-3 text-sm text-slate-500">
                      No matching courses found.
                    </div>
                  <% true -> %>
                    <%= for course <- @filtered_courses do %>
                      <button
                        id={"discord-add-my-courses-option-#{course["crn"]}"}
                        type="button"
                        phx-click="discord-add-my-courses:select_course"
                        phx-value-crn={course["crn"]}
                        class={[
                          "flex w-full flex-col gap-1 rounded-md border px-3 py-2 text-left transition",
                          selected_course?(state: @state, course: course) &&
                            "border-emerald-500/40 bg-emerald-500/10",
                          !selected_course?(state: @state, course: course) &&
                            "border-slate-800 bg-slate-950/45 hover:border-slate-700 hover:bg-slate-900/60"
                        ]}
                      >
                        <span class="text-sm font-medium text-slate-100">{course_prefix(course)}</span>
                        <span class="text-xs text-slate-500">{course_name(course)}</span>
                        <span class="text-xs text-slate-600">{primary_instructor(course)}</span>
                      </button>
                    <% end %>
                <% end %>
              </div>

              <div
                :if={@state.selected_course}
                id={"discord-add-my-courses-selection-#{@state.selected_course["crn"]}"}
                class="mt-3 flex flex-col gap-3"
              >
                <div>
                  <label class="mb-2 block text-sm font-medium text-slate-300">Channel group</label>
                  <select
                    id="discord-add-my-courses-channel-group"
                    name="add_my_courses[group_id]"
                    class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20"
                  >
                    <option value="">Select a group...</option>
                    <option
                      :for={group <- @channel_groups}
                      value={group.id}
                      selected={Map.get(@state.form, "group_id") == group.id}
                    >
                      {group.name}
                    </option>
                  </select>
                </div>

                <div>
                  <label class="mb-2 block text-sm font-medium text-slate-300">Channel name</label>
                  <input
                    id="discord-add-my-courses-channel-name"
                    type="text"
                    name="add_my_courses[channel_name]"
                    value={Map.get(@state.form, "channel_name", "")}
                    class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 font-mono text-sm text-slate-100 outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20"
                  />
                </div>
              </div>
            </form>
            <div class="flex items-center justify-end gap-2">
              <button
                type="button"
                phx-click="discord-add-my-courses:close"
                class="rounded-md border border-slate-700 px-3 py-2 text-sm text-slate-300 transition hover:bg-slate-900"
              >
                Cancel
              </button>
              <button
                id="discord-add-my-courses-create"
                type="button"
                phx-click="discord-add-my-courses:create"
                disabled={@state.creating? || is_nil(@state.selected_course)}
                class="inline-flex items-center gap-2 rounded-md border border-emerald-500/30 bg-emerald-500/15 px-3 py-2 text-sm font-semibold text-emerald-100 transition hover:bg-emerald-500/25 disabled:cursor-not-allowed disabled:opacity-60"
              >
                <.icon name="hero-plus" class="size-4" />
                <%= if @state.creating? do %>
                  Creating...
                <% else %>
                  Create channel
                <% end %>
              </button>
            </div>
          </div>
        </.modal>
      <% end %>
    </div>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_add_my_courses_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-add-my-courses:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("discord-add-my-courses:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_add_my_courses_hooks_attached?], true)
    end
  end

  defp hooked_event("discord-add-my-courses:open", _params, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{key: :discord_add_my_courses}

    {:halt,
     put_state(socket, %{
       state
       | open?: true,
         selected_course: nil,
         creating?: false,
         error: nil,
         form: initial_form(socket.assigns)
     })}
  end

  defp hooked_event("discord-add-my-courses:close", _params, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}
    {:halt, put_state(socket, closed_state(state))}
  end

  defp hooked_event("discord-add-my-courses:form:change", params, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}
    form_params = Map.get(params, "add_my_courses", %{})

    selected_term =
      form_params
      |> Map.get("selected_term", Map.get(state.form, "selected_term"))
      |> preserve_value_for_target(params, state, "course_query")
      |> blank_to_nil()

    group_id =
      form_params
      |> Map.get("group_id", Map.get(state.form, "group_id"))
      |> blank_to_nil()

    course_query = Map.get(form_params, "course_query", Map.get(state.form, "course_query", ""))
    channel_name = Map.get(form_params, "channel_name", Map.get(state.form, "channel_name", ""))

    term_changed? = selected_term != Map.get(state.form, "selected_term")

    selected_course =
      if term_changed? do
        nil
      else
        state.selected_course
      end

    form =
      %{
        "selected_term" => selected_term,
        "group_id" => if(term_changed?, do: nil, else: group_id),
        "role_id" => if(term_changed?, do: nil, else: Map.get(state.form, "role_id")),
        "course_query" => course_query,
        "channel_name" => if(term_changed?, do: "", else: channel_name)
      }
      |> maybe_set_inferred_role(socket.assigns)

    {:halt, put_state(socket, %{state | form: form, selected_course: selected_course})}
  end

  defp hooked_event("discord-add-my-courses:select_course", %{"crn" => crn}, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}
    selected_term = Map.get(state.form, "selected_term")
    courses = Map.get(Map.get(socket.assigns, :courses_by_term, %{}), selected_term, [])
    selected_course = Enum.find(courses, &(&1["crn"] == crn))

    form =
      state.form
      |> Map.put("group_id", nil)
      |> Map.put("role_id", nil)
      |> Map.put("channel_name", default_channel_name(selected_course, selected_term))
      |> maybe_apply_course_defaults(
        selected_course: selected_course,
        term_code: selected_term,
        assigns: socket.assigns
      )

    {:halt,
     put_state(socket, %{state | selected_course: selected_course, form: form, error: nil})}
  end

  defp hooked_event("discord-add-my-courses:create", _params, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    with {:ok, course} <- selected_course(state),
         {:ok, selected_term} <- required_form_value(state, "selected_term", "Select a term."),
         {:ok, group_id} <- required_form_value(state, "group_id", "Select a channel group."),
         {:ok, role_id} <- required_group_role(state, socket.assigns),
         {:ok, channel_name} <-
           required_form_value(state, "channel_name", "Enter a channel name.") do
      DiscordDomainManager.create_course_channel(
        pid: self(),
        key: state.key,
        crn: course["crn"],
        term_code: selected_term,
        channel_name: normalize_channel_name(channel_name),
        parent_id: group_id,
        discord_role_id: role_id
      )

      {:halt, put_state(socket, %{state | creating?: true, error: nil})}
    else
      {:error, message} when is_binary(message) ->
        {:halt, put_state(socket, %{state | error: message})}
    end
  end

  defp hooked_event("discord-add-my-courses:" <> rest, params, socket) do
    Logger.debug("Unhandled event discord-add-my-courses:#{rest} params=#{inspect(params)}")
    {:halt, socket}
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  defp hooked_info({:discord, {:course_channel_created, key, {:ok, _payload}}}, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    if key == state.key do
      {:cont, put_state(socket, closed_state(state))}
    else
      {:cont, socket}
    end
  end

  defp hooked_info({:discord, {:course_channel_created, key, {:error, reason}}}, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    if key == state.key do
      Logger.error("Discord add my courses create failed reason=#{inspect(reason)}")

      {:cont,
       put_state(socket, %{state | creating?: false, error: "Could not create course channel."})}
    else
      {:cont, socket}
    end
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp put_state(socket, state), do: assign(socket, @state_assign, state)

  defp closed_state(state) do
    %{state | open?: false, selected_course: nil, creating?: false, error: nil, form: %{}}
  end

  defp initial_form(assigns) do
    courses_by_term = Map.get(assigns, :courses_by_term, %{})

    selected_term =
      closest_term_code(term_codes: Map.keys(courses_by_term), date: Date.utc_today())

    %{
      "selected_term" => selected_term,
      "group_id" => nil,
      "role_id" => nil,
      "course_query" => "",
      "channel_name" => ""
    }
  end

  defp maybe_set_inferred_role(form, assigns) do
    role_id =
      assigns
      |> discord_channels()
      |> Enum.find(&(Map.get(&1, "id") == Map.get(form, "group_id")))
      |> role_id_from_channel_group(discord_roles(assigns))

    Map.put(form, "role_id", role_id)
  end

  defp maybe_apply_course_defaults(form,
         selected_course: selected_course,
         term_code: term_code,
         assigns: assigns
       ) do
    case recommended_channel_group_id(
           selected_course: selected_course,
           term_code: term_code,
           channel_groups: channel_groups(discord_channels(assigns))
         ) do
      {:ok, channel_group_id} ->
        form
        |> Map.put("group_id", channel_group_id)

      {:error, :course_not_configured} ->
        Logger.error(
          "Discord add my courses: course not configured for #{inspect(selected_course)}"
        )

        form
        |> maybe_put_default_group_id(assigns)

      {:error, :invalid_term_code} ->
        Logger.error(
          "Discord add my courses: invalid term code #{inspect(term_code)} for #{inspect(selected_course)}"
        )

        form
        |> maybe_put_default_group_id(assigns)

      {:error, :channel_group_not_found} ->
        Logger.error(
          "Discord add my courses: channel group not found for #{inspect(selected_course)} in term #{inspect(term_code)}"
        )

        form
        |> maybe_put_default_group_id(assigns)
    end
  end

  defp recommended_channel_group_id(
         selected_course: selected_course,
         term_code: term_code,
         channel_groups: channel_groups
       )
       when is_map(selected_course) and is_binary(term_code) do
    DiscordGraduationHelpers.recommended_channel_group_id(
      subject: Map.get(selected_course, "subject_code"),
      course_number: Map.get(selected_course, "course_number"),
      term_code: term_code,
      channel_groups: channel_groups
    )
  end

  defp recommended_channel_group_id(
         selected_course: _selected_course,
         term_code: _term_code,
         channel_groups: _channel_groups
       ),
       do: {:error, :course_not_configured}


  defp maybe_put_default_group_id(%{"group_id" => group_id} = form, _assigns)
       when is_binary(group_id) and group_id != "" do
    form
  end

  defp maybe_put_default_group_id(form, assigns) do
    case assigns |> discord_channels() |> channel_groups() |> List.first() do
      %{id: group_id} -> Map.put(form, "group_id", group_id)
      _missing -> form
    end
  end

  defp selected_course(%{selected_course: course}) when is_map(course), do: {:ok, course}
  defp selected_course(_state), do: {:error, "Select a course."}

  defp required_group_role(state, assigns) do
    group_id = state.form |> Map.get("group_id") |> blank_to_nil()

    role_id =
      assigns
      |> discord_channels()
      |> Enum.find(&(Map.get(&1, "id") == group_id))
      |> role_id_from_channel_group(discord_roles(assigns))

    case role_id do
      role_id when is_binary(role_id) -> {:ok, role_id}
      _missing -> {:error, "Selected channel group must have a student role requirement."}
    end
  end

  defp required_form_value(state, field, message) do
    value = state.form |> Map.get(field) |> blank_to_nil()

    if is_binary(value) do
      {:ok, value}
    else
      {:error, message}
    end
  end

  defp preserve_value_for_target("", params, state, field_name) do
    if form_target?(params, field_name), do: Map.get(state.form, "selected_term"), else: ""
  end

  defp preserve_value_for_target(value, _params, _state, _field_name), do: value

  defp form_target?(%{"_target" => ["add_my_courses", field_name]}, field_name), do: true
  defp form_target?(_params, _field_name), do: false

  defp blank_to_nil(value) when value in ["", nil], do: nil
  defp blank_to_nil(value), do: value

  defp filtered_courses(state, courses_by_term) do
    selected_term = Map.get(state.form || %{}, "selected_term")
    course_query = Map.get(state.form || %{}, "course_query", "")

    courses = Map.get(courses_by_term || %{}, selected_term) || []
    query = normalize_search(course_query)

    courses
    |> Enum.filter(fn course ->
      query == "" or String.contains?(course_search_text(course), query)
    end)
    |> Enum.sort_by(fn course ->
      {Map.get(course, "subject_code", ""), Map.get(course, "course_number", ""),
       Map.get(course, "section_number", ""), Map.get(course, "crn", "")}
    end)
    |> Enum.take(20)
  end

  defp selected_course?(state: state, course: course) do
    is_map(state.selected_course) && state.selected_course["crn"] == course["crn"]
  end

  defp channel_groups(channels) do
    channels
    |> Enum.filter(fn channel -> channel_type(channel) == 4 end)
    |> Enum.sort_by(fn channel -> {channel_position(channel), Map.get(channel, "name", "")} end)
    |> Enum.map(fn channel ->
      %{
        id: Map.get(channel, "id"),
        name: Map.get(channel, "name", "unnamed"),
        data: channel_data(channel)
      }
    end)
  end

  defp role_id_from_channel_group(nil, _roles), do: nil

  defp role_id_from_channel_group(group, roles) do
    roles_by_id = Map.new(roles, &{&1["id"], &1})

    group
    |> channel_data()
    |> Map.get("permission_overwrites", [])
    |> Enum.find_value(fn overwrite ->
      role_id = Map.get(overwrite, "id")
      role = Map.get(roles_by_id, role_id)

      if role_permission_overwrite?(overwrite) &&
           permission_includes?(
             permission_value: Map.get(overwrite, "allow"),
             permission_bit: 1024
           ) &&
           role && !default_role?(role) && !bot_managed_role?(role) do
        role_id
      end
    end)
  end

  defp channel_type(channel), do: channel |> channel_data() |> Map.get("type")
  defp channel_position(channel), do: channel |> channel_data() |> Map.get("position", 999_999)

  defp channel_data(channel) when is_map(channel) do
    Map.get(channel, "data") || Map.get(channel, :data) || channel
  end

  defp channel_data(_channel), do: %{}

  defp role_permission_overwrite?(permission_overwrite) do
    Map.get(permission_overwrite, "type") in [0, "0"]
  end

  defp permission_includes?(permission_value: permission_value, permission_bit: permission_bit) do
    permission_value
    |> parse_permission_integer()
    |> Bitwise.band(permission_bit) == permission_bit
  end

  defp parse_permission_integer(value) when is_integer(value), do: value

  defp parse_permission_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {permission_integer, ""} -> permission_integer
      _invalid -> 0
    end
  end

  defp parse_permission_integer(_value), do: 0

  defp default_role?(role), do: role["name"] == "@everyone"

  defp bot_managed_role?(role) do
    data = Map.get(role, "data", %{})
    tags = Map.get(data, "tags", %{})

    Map.get(data, "managed") == true or Map.has_key?(tags, "bot_id")
  end

  defp sorted_terms(courses_by_term) do
    courses_by_term
    |> Enum.map(fn {code, _courses} -> %{code: code, display: term_display_name(code)} end)
    |> Enum.sort_by(& &1.code, :desc)
  end

  defp closest_term_code(term_codes: term_codes, date: date) do
    term_codes
    |> Enum.map(fn term_code -> {term_code, term_start_date(term_code)} end)
    |> Enum.reject(fn {_term_code, start_date} -> is_nil(start_date) end)
    |> Enum.min_by(
      fn {_term_code, start_date} -> abs(Date.diff(start_date, date)) end,
      fn -> nil end
    )
    |> case do
      {term_code, _start_date} -> term_code
      nil -> nil
    end
  end

  defp term_start_date(term_code) when is_binary(term_code) and byte_size(term_code) >= 6 do
    year = String.slice(term_code, 0, 4)

    month_day =
      case String.slice(term_code, 4, 2) do
        "10" -> {1, 1}
        "30" -> {5, 1}
        "40" -> {8, 1}
        _other -> nil
      end

    with {year, ""} <- Integer.parse(year),
         {month, day} <- month_day,
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _invalid -> nil
    end
  end

  defp term_start_date(_term_code), do: nil

  defp term_display_name(term_code) when is_binary(term_code) and byte_size(term_code) >= 6 do
    year = String.slice(term_code, 0, 4)

    semester =
      case String.slice(term_code, 4, 2) do
        "10" -> "Spring"
        "30" -> "Summer"
        "40" -> "Fall"
        other -> other
      end

    "#{semester} #{year}"
  end

  defp term_display_name(term_code), do: term_code

  defp default_channel_name(nil, _term_code), do: ""

  defp default_channel_name(course, term_code) do
    subject = course |> Map.get("subject_code", "") |> String.downcase()
    number = Map.get(course, "course_number", "")

    [
      subject,
      number,
      term_year(term_code),
      term_slug(term_code)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("-")
    |> normalize_channel_name()
  end

  defp term_year(term_code) when is_binary(term_code) and byte_size(term_code) >= 4,
    do: String.slice(term_code, 0, 4)

  defp term_year(_term_code), do: nil

  defp term_slug(term_code) when is_binary(term_code) and byte_size(term_code) >= 6 do
    case String.slice(term_code, 4, 2) do
      "10" -> "spring"
      "30" -> "summer"
      "40" -> "fall"
      other -> other
    end
  end

  defp term_slug(_term_code), do: nil

  defp normalize_channel_name(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp normalize_channel_name(_value), do: ""

  defp course_prefix(course) do
    [
      Map.get(course, "subject_code", ""),
      Map.get(course, "course_number", ""),
      Map.get(course, "section_number", "")
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp course_name(course), do: Map.get(course, "course_name") || Map.get(course, "name") || ""

  defp primary_instructor(course) do
    Map.get(course, "primary_instructor_name") ||
      course
      |> Map.get("instructors", [])
      |> Enum.find_value(fn instructor ->
        if Map.get(instructor, "primary_instructor") == true, do: Map.get(instructor, "name")
      end) ||
      course
      |> Map.get("instructors", [])
      |> List.first()
      |> case do
        %{"name" => name} -> name
        _ -> ""
      end
  end

  defp course_search_text(course) do
    subject_code = Map.get(course, "subject_code", "")
    course_number = Map.get(course, "course_number", "")
    section_number = Map.get(course, "section_number", "")

    [
      subject_code,
      course_number,
      section_number,
      "#{subject_code} #{course_number}",
      "#{subject_code} #{course_number} #{section_number}",
      course_name(course),
      primary_instructor(course),
      Map.get(course, "crn", ""),
      instructor_emails(course)
    ]
    |> Enum.map_join(" ", &normalize_search/1)
  end

  defp instructor_emails(course) do
    course
    |> Map.get("instructors", [])
    |> Enum.map_join(" ", &(Map.get(&1, "email") || Map.get(&1, "email_address") || ""))
  end

  defp normalize_search(value) when is_binary(value),
    do: String.downcase(value) |> String.replace(~r/\s+/, "")

  defp normalize_search(_value), do: ""

  defp discord_channels(%{discord_channels: %{channels: channels}}) when is_list(channels),
    do: channels

  defp discord_channels(_assigns), do: []

  defp discord_roles(%{discord_roles: %{roles: roles}}) when is_list(roles), do: roles
  defp discord_roles(_assigns), do: []
end
