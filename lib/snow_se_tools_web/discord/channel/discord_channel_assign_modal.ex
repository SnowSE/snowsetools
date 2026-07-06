defmodule SnowSeToolsWeb.Discord.DiscordChannelAssignModal do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeTools.Snow.SnowCourseCacheDomainManager

  defstruct open_channel_id: nil,
            channel: nil,
            selected_course: nil,
            assigning?: false,
            error: nil,
            form: %{},
            sorted_terms: [],
            terms_loaded?: false

  @state_assign :discord_channel_assign_modal

  def assign_component(socket, _key) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    socket
    |> put_state(state)
    |> maybe_attach_hooks()
    |> maybe_request_courses()
  end

  def fetch_state(assigns), do: Map.get(assigns, @state_assign)

  attr :channel, :map, required: true
  attr :assignment, :any, default: nil

  def render_button(assigns) do
    ~H"""
    <div :if={!@assignment}>
      <button
        type="button"
        phx-click="discord-channel-assign-modal:open"
        phx-value-channel_id={channel_id(@channel)}
        class="inline-flex items-center gap-2 rounded-md border border-indigo-500/30 bg-indigo-500/10 px-3 py-2 text-sm font-medium text-indigo-100 transition hover:bg-indigo-500/20"
      >
        <.icon name="hero-plus" class="size-4" /> Assign to course
      </button>
    </div>
    """
  end

  attr :state, __MODULE__, required: true
  attr :assignment, :any, default: nil
  attr :roles, :list, default: []
  attr :courses_by_term, :map, default: %{}

  def render(assigns) do
    assigns =
      assigns
      |> assign(:sorted_terms, sorted_terms(assigns.courses_by_term))
      |> assign(:filtered_courses, filtered_courses(assigns.state, assigns.courses_by_term))

    ~H"""
    <%= if @state.open_channel_id do %>
      <.modal
        id={"discord-channel-assign-modal-#{@state.open_channel_id}"}
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

          <div :if={@state.assigning?} class="text-sm text-slate-400">Assigning course...</div>

          <div :if={!@state.assigning?}>
            <form
              id="discord-assign-form"
              phx-change="discord-channel-assign-modal:assign_form:change"
            >
              <div>
                <label class="mb-2 block text-sm font-medium text-slate-300">Term</label>
                <select
                  id="discord-assign-term-select"
                  name="assign_form[selected_term]"
                  value={Map.get(@state.form, "selected_term") || ""}
                  class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
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

              <%= if Map.get(@state.form, "selected_term") do %>
                <div class="mt-3">
                  <label class="mb-2 block text-sm font-medium text-slate-300">Search courses</label>
                  <input
                    id="discord-assign-course-query"
                    type="text"
                    name="assign_form[course_query]"
                    value={Map.get(@state.form, "course_query", "")}
                    placeholder="MATH 1010 or College Algebra"
                    phx-debounce="200"
                    class="w-full rounded-md border border-slate-700 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
                  />

                  <div class="mt-3 max-h-64 overflow-y-auto space-y-2">
                    <%= if @filtered_courses == [] do %>
                      <div class="rounded-md border border-slate-800 bg-slate-950/35 p-3 text-sm text-slate-500">
                        No matching courses found.
                      </div>
                    <% else %>
                      <%= for course <- @filtered_courses do %>
                        <button
                          id={"discord-assign-course-option-#{course["crn"]}"}
                          type="button"
                          phx-click="discord-channel-assign-modal:select_course"
                          phx-value-crn={course["crn"]}
                          class={[
                            "flex w-full flex-col gap-1 rounded-md border px-3 py-2 text-left transition",
                            @state.selected_course && @state.selected_course["crn"] == course["crn"] &&
                              "border-indigo-500/40 bg-indigo-500/10",
                            !(@state.selected_course && @state.selected_course["crn"] == course["crn"]) &&
                              "border-slate-800 bg-slate-950/45 hover:border-slate-700 hover:bg-slate-900/60"
                          ]}
                        >
                          <span class="text-sm font-medium text-slate-100">{course_prefix(course)}</span>
                          <span class="text-xs text-slate-500">{course["course_name"]}</span>
                        </button>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </form>
          </div>

          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              phx-click="discord-channel-assign-modal:close"
              class="rounded-md border border-slate-700 px-3 py-2 text-sm text-slate-300 transition hover:bg-slate-900"
            >
              Cancel
            </button>
            <button
              id="discord-assign-save"
              type="button"
              phx-click="discord-channel-assign-modal:save"
              disabled={is_nil(@state.selected_course) || @state.assigning?}
              class="inline-flex items-center gap-2 rounded-md border border-indigo-500/30 bg-indigo-500/15 px-3 py-2 text-sm font-semibold text-indigo-100 transition hover:bg-indigo-500/25 disabled:cursor-not-allowed disabled:opacity-60"
            >
              <.icon name="hero-check" class="size-4" /> Assign course
            </button>
          </div>
        </div>
      </.modal>
    <% end %>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_channel_assign_modal_hooks_attached?) do
      socket
    else
      Logger.info(
        "attaching hooks for discord-channel-assign-modal to socket=#{inspect(socket.id)}"
      )

      socket
      |> LiveView.attach_hook(
        "discord-channel-assign-modal:event",
        :handle_event,
        &hooked_event/3
      )
      |> LiveView.attach_hook(
        "discord-channel-assign-modal:info",
        :handle_info,
        &hooked_info/2
      )
      |> put_in([Access.key(:private), :discord_channel_assign_modal_hooks_attached?], true)
    end
  end

  defp maybe_request_courses(socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    if Map.get(state, :terms_loaded?, false) do
      socket
    else
      Logger.info("Requesting all courses from SnowCourseCacheDomainManager...")
      SnowCourseCacheDomainManager.request_all_courses(pid: self())
      socket
    end
  end

  defp hooked_event("discord-channel-assign-modal:open", %{"channel_id" => channel_id}, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}
    channel = find_channel_by_id(socket.assigns, channel_id)
    courses_by_term = Map.get(socket.assigns, :courses_by_term, %{})
    form = initial_form_for_channel(channel: channel, courses_by_term: courses_by_term)

    {:halt,
     put_state(socket, %{
       state
       | open_channel_id: channel_id,
         channel: channel,
         form: form,
         selected_course: nil,
         assigning?: false,
         error: nil
     })}
  end

  defp hooked_event("discord-channel-assign-modal:close", params, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    Logger.debug(
      "AssignModal close hook fired: open_channel_id=#{inspect(state.open_channel_id)} params=#{inspect(params)}"
    )

    {:halt,
     put_state(socket, %{
       state
       | open_channel_id: nil,
         channel: nil,
         form: %{},
         selected_course: nil,
         assigning?: false,
         error: nil
     })}
  end

  defp hooked_event("discord-channel-assign-modal:assign_form:change", params, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}
    form_params = Map.get(params, "assign_form", %{})

    selected_term =
      form_params
      |> Map.get("selected_term", Map.get(state.form, "selected_term"))
      |> preserve_selected_term_for_course_search(params, state)

    selected_term = if(selected_term == "", do: nil, else: selected_term)

    course_query = Map.get(form_params, "course_query", Map.get(state.form, "course_query", ""))

    {:halt,
     put_state(socket, %{
       state
       | form: %{"selected_term" => selected_term, "course_query" => course_query},
         selected_course: nil
     })}
  end

  defp hooked_event("discord-channel-assign-modal:select_course", %{"crn" => crn}, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    courses =
      Map.get(
        Map.get(socket.assigns, :courses_by_term, %{}),
        Map.get(state.form, "selected_term"),
        []
      )

    selected_course = Enum.find(courses, &(&1["crn"] == crn))

    {:halt, put_state(socket, %{state | selected_course: selected_course})}
  end

  defp hooked_event("discord-channel-assign-modal:save", _params, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}
    channel_id = Map.get(state.channel, :id) || Map.get(state.channel, "id")
    role_id = find_channel_role_id(channel: state.channel, roles: discord_roles(socket.assigns))

    cond do
      is_nil(state.selected_course) or is_nil(channel_id) ->
        {:halt, put_state(socket, %{state | error: "Select a course and term before saving."})}

      is_nil(role_id) ->
        {:halt,
         put_state(socket, %{
           state
           | error: "Could not find a course role in this channel's permission overwrites."
         })}

      true ->
        DiscordDomainManager.save_course_channel_assignment(
          pid: self(),
          key: "discord-channel-row:#{channel_id}",
          crn: state.selected_course["crn"],
          term_code: state.selected_course["term_code"],
          discord_channel_id: channel_id,
          discord_role_id: role_id
        )

        {:halt, put_state(socket, %{state | assigning?: true})}
    end
  end

  defp hooked_event("discord-channel-assign-modal:" <> rest, params, socket) do
    Logger.debug("Unhandled event discord-channel-assign-modal:#{rest} params=#{inspect(params)}")
    {:halt, socket}
  end

  defp hooked_event(_event, _params, socket), do: {:cont, socket}

  defp preserve_selected_term_for_course_search("", params, state) do
    if form_target?(params, "course_query") do
      Map.get(state.form, "selected_term")
    else
      ""
    end
  end

  defp preserve_selected_term_for_course_search(selected_term, _params, _state), do: selected_term

  defp form_target?(%{"_target" => ["assign_form", field_name]}, field_name), do: true
  defp form_target?(_params, _field_name), do: false

  defp initial_form_for_channel(channel: channel, courses_by_term: courses_by_term) do
    term_codes = Map.keys(courses_by_term || %{})
    channel_name = channel_name(channel)

    %{
      "selected_term" => initial_term_code(channel_name: channel_name, term_codes: term_codes),
      "course_query" => initial_course_query(channel_name)
    }
  end

  defp initial_term_code(channel_name: channel_name, term_codes: term_codes) do
    case channel_term_parts(channel_name) do
      {_query_words, [first_term_word, second_term_word]} ->
        mapped_term_code =
          term_code_from_words(
            first_term_word: first_term_word,
            second_term_word: second_term_word,
            term_codes: term_codes
          )

        mapped_term_code || closest_term_code(term_codes: term_codes, date: Date.utc_today())

      _no_term_parts ->
        closest_term_code(term_codes: term_codes, date: Date.utc_today())
    end
  end

  defp initial_course_query(channel_name) do
    case channel_term_parts(channel_name) do
      {query_words, [_first_term_word, _second_term_word]} -> Enum.join(query_words, " ")
      _no_term_parts -> channel_name
    end
  end

  defp channel_term_parts(channel_name) do
    words = channel_name_words(channel_name)

    if length(words) >= 3 do
      {Enum.drop(words, -2), Enum.take(words, -2)}
    else
      nil
    end
  end

  defp channel_name_words(channel_name) do
    channel_name
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
  end

  defp term_code_from_words(
         first_term_word: first_term_word,
         second_term_word: second_term_word,
         term_codes: term_codes
       ) do
    term_codes = MapSet.new(term_codes)

    [
      {first_term_word, second_term_word},
      {second_term_word, first_term_word}
    ]
    |> Enum.find_value(fn {year, semester} ->
      with true <- year?(year),
           semester_code when is_binary(semester_code) <- semester_code(semester),
           term_code = "#{year}#{semester_code}",
           true <- MapSet.member?(term_codes, term_code) do
        term_code
      else
        _not_mappable -> nil
      end
    end)
  end

  defp year?(value) when is_binary(value), do: String.match?(value, ~r/^\d{4}$/)
  defp year?(_value), do: false

  defp semester_code("spring"), do: "10"
  defp semester_code("summer"), do: "30"
  defp semester_code("fall"), do: "40"
  defp semester_code("autumn"), do: "40"
  defp semester_code(_semester), do: nil

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

  defp hooked_info({:snow_course_cache, {:all_courses_loaded, {:ok, courses_by_term}}}, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    sorted =
      courses_by_term
      |> Enum.map(fn {code, _courses} -> %{code: code, display: term_display_name(code)} end)
      |> Enum.sort_by(& &1.code, :desc)

    {:cont, put_state(socket, %{state | sorted_terms: sorted, terms_loaded?: true})}
  end

  defp hooked_info({:discord, {:course_channel_assignment_saved, key, {:ok, _result}}}, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    if key == assignment_key_for_channel_id(state.open_channel_id) do
      {:cont, put_state(socket, closed_state(state))}
    else
      {:cont, socket}
    end
  end

  defp hooked_info({:discord, {:course_channel_assignment_saved, key, {:error, reason}}}, socket) do
    state = fetch_state(socket.assigns) || %__MODULE__{}

    if key == assignment_key_for_channel_id(state.open_channel_id) do
      Logger.error("Discord course assignment save failed reason=#{inspect(reason)}")

      {:cont,
       put_state(socket, %{
         state
         | assigning?: false,
           error: "Could not save assignment."
       })}
    else
      {:cont, socket}
    end
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  defp put_state(socket, state), do: assign(socket, @state_assign, state)

  defp closed_state(state) do
    %{
      state
      | open_channel_id: nil,
        channel: nil,
        form: %{},
        selected_course: nil,
        assigning?: false,
        error: nil
    }
  end

  defp assignment_key_for_channel_id(channel_id) when is_binary(channel_id) do
    "discord-channel-row:#{channel_id}"
  end

  defp assignment_key_for_channel_id(_channel_id), do: nil

  defp find_channel_by_id(assigns, channel_id) do
    row_states = Map.get(assigns, :discord_channel_row_states, %{})

    Enum.find_value(row_states, fn {_k, row} ->
      if is_struct(row, SnowSeToolsWeb.Discord.DiscordChannelRow) and
           is_map(row.channel) and
           channel_id in [Map.get(row.channel, :id), Map.get(row.channel, "id")] do
        row.channel
      else
        nil
      end
    end) || %{}
  end

  defp find_channel_role_id(channel: channel, roles: roles) do
    roles_by_id = Map.new(roles, &{&1["id"], &1})
    permission_overwrites = channel_permission_overwrites(channel)

    find_role_id_for_overwrite(
      permission_overwrites: permission_overwrites,
      roles_by_id: roles_by_id,
      matcher: &student_visibility_overwrite?/1
    ) ||
      find_role_id_for_overwrite(
        permission_overwrites: permission_overwrites,
        roles_by_id: roles_by_id,
        matcher: &view_channel_allowed_overwrite?/1
      )
  end

  defp find_role_id_for_overwrite(
         permission_overwrites: permission_overwrites,
         roles_by_id: roles_by_id,
         matcher: matcher
       ) do
    permission_overwrites
    |> Enum.filter(matcher)
    |> Enum.map(&Map.get(&1, "id"))
    |> Enum.find(fn role_id ->
      role = Map.get(roles_by_id, role_id)
      role && !default_role?(role) && !bot_managed_role?(role)
    end)
  end

  defp channel_permission_overwrites(channel) do
    channel
    |> channel_data()
    |> Map.get("permission_overwrites", [])
  end

  defp channel_data(channel) when is_map(channel) do
    Map.get(channel, "data") || Map.get(channel, :data) || channel
  end

  defp channel_data(_channel), do: %{}

  defp student_visibility_overwrite?(permission_overwrite) do
    role_permission_overwrite?(permission_overwrite) &&
      parse_permission_integer(Map.get(permission_overwrite, "allow")) == 1024 &&
      !permission_includes?(
        permission_value: Map.get(permission_overwrite, "deny"),
        permission_bit: 1024
      )
  end

  defp view_channel_allowed_overwrite?(permission_overwrite) do
    role_permission_overwrite?(permission_overwrite) &&
      permission_includes?(
        permission_value: Map.get(permission_overwrite, "allow"),
        permission_bit: 1024
      ) &&
      !permission_includes?(
        permission_value: Map.get(permission_overwrite, "deny"),
        permission_bit: 1024
      )
  end

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

  defp discord_roles(assigns) do
    case Map.get(assigns, :discord_roles) do
      %{roles: roles} when is_list(roles) -> roles
      _ -> []
    end
  end

  defp sorted_terms(courses_by_term) do
    courses_by_term
    |> Enum.map(fn {code, _courses} -> %{code: code, display: term_display_name(code)} end)
    |> Enum.sort_by(& &1.code, :desc)
  end

  defp channel_id(channel), do: Map.get(channel, :id) || Map.get(channel, "id")

  defp filtered_courses(state, courses_by_term) do
    selected_term = Map.get(state.form || %{}, "selected_term")
    course_query = Map.get(state.form || %{}, "course_query", "")

    courses = Map.get(courses_by_term || %{}, selected_term) || []
    query = normalize(course_query)

    courses
    |> Enum.filter(fn course ->
      query == "" or
        String.contains?(course_search_text(course), query)
    end)
    |> Enum.sort_by(fn course ->
      {Map.get(course, "subject_code", ""), Map.get(course, "course_number", ""),
       Map.get(course, "section_number", ""), Map.get(course, "crn", "")}
    end)
  end

  defp channel_name(channel) do
    Map.get(channel || %{}, :name) || Map.get(channel || %{}, "name") || "unnamed"
  end

  defp course_prefix(course) do
    [
      Map.get(course, "subject_code", ""),
      Map.get(course, "course_number", ""),
      Map.get(course, "section_number", "")
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
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
      Map.get(course, "course_name", ""),
      Map.get(course, "crn", "")
    ]
    |> Enum.map_join(" ", &normalize/1)
  end

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

  defp normalize(value) when is_binary(value),
    do: String.downcase(value) |> String.replace(~r/\s+/, "")

  defp normalize(_), do: ""
end
