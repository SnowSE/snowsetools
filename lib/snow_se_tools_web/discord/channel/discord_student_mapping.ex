defmodule SnowSeToolsWeb.Discord.DiscordStudentMapping do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Discord.DiscordDomainManager
  alias SnowSeTools.Snow.SnowCourseCacheDomainManager
  alias SnowSeToolsWeb.Discord.DiscordStudentRow

  defstruct key: nil,
            assignment: nil,
            students: [],
            student_items: [],
            filtered_mappings: [],
            loading?: true,
            error: nil

  @state_assign :discord_student_mapping_states

  def assign_component(socket, key, assignment: assignment) do
    state = fetch_state(socket.assigns, key) || %__MODULE__{key: key, assignment: assignment}

    state =
      if is_map(assignment) do
        %{
          state
          | assignment: assignment,
            students: [],
            student_items: [],
            loading?: true,
            error: nil
        }
      else
        %{state | assignment: nil, students: [], student_items: [], loading?: false, error: nil}
      end

    socket
    |> put_state(key, state)
    |> maybe_attach_hooks()
    |> maybe_request_data(key: key, assignment: assignment)
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
  attr :student_row_states, :map, default: %{}

  def render(assigns) do
    assigns =
      assign(assigns, :mapped_discord_user_ids, mapped_discord_user_ids(assigns.mappings))

    ~H"""
    <div class="pl-4">
      <div
        :if={@state.error}
        class="mb-2 rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-200"
      >
        {@state.error}
      </div>

      <div :if={@state.loading?} class="text-sm text-slate-500">
        <span class="inline-flex items-center gap-2">
          <span class="size-3 animate-spin rounded-full border border-slate-500 border-t-transparent"></span>
          Loading students...
        </span>
      </div>

      <div
        :if={!@state.loading? and @state.student_items == []}
        class="rounded-md border border-slate-800 bg-slate-950/35 p-3 text-sm text-slate-500"
      >
        No students cached. Sync this course to load roster.
      </div>

      <div :if={!@state.loading? and @state.student_items != []} class="space-y-2">
        <div class="text-xs uppercase tracking-wide text-slate-500">
          students in the course ({length(@state.student_items)})
        </div>

        <DiscordStudentRow.render
          :for={item <- @state.student_items}
          state={item.state}
          student={item.student}
          mapping={item.mapping}
          is_mapped={item.is_mapped}
          required_role_id={item.required_role_id}
          members={@members}
          roles={@roles}
          mapped_discord_user_ids={@mapped_discord_user_ids}
        />
      </div>
    </div>
    """
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :discord_student_mapping_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("discord-student-mapping:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :discord_student_mapping_hooks_attached?], true)
    end
  end

  defp maybe_request_data(socket, key: key, assignment: assignment) when is_map(assignment) do
    if LiveView.connected?(socket) do
      SnowCourseCacheDomainManager.request_section_students(
        pid: self(),
        key: key,
        term_code: assignment["term_code"],
        crn: assignment["crn"]
      )

      DiscordDomainManager.request_student_mappings_for_course(
        pid: self(),
        key: key,
        term_code: assignment["term_code"],
        crn: assignment["crn"]
      )
    end

    socket
  end

  defp maybe_request_data(socket, _opts), do: socket

  # -- info hooks --

  defp hooked_info(
         {:snow_course_cache, {:section_students_loaded, key, {:ok, payload}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        students = Map.get(payload, :students, [])
        socket = ensure_student_rows(socket, key, students)

        socket =
          put_state(socket, key, %{state | students: students, loading?: false, error: nil})

        socket = rebuild_student_items(socket, key)

        {:cont, socket}
    end
  end

  defp hooked_info(
         {:snow_course_cache, {:section_students_loaded, key, {:error, reason}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord student roster load failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{state | loading?: false, error: "Could not load course roster."})}
    end
  end

  defp hooked_info(
         {:discord, {:student_mappings_for_course_loaded, key, {:ok, filtered_mappings}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        socket = put_state(socket, key, %{state | filtered_mappings: filtered_mappings})
        socket = rebuild_student_items(socket, key)

        {:cont, socket}
    end
  end

  defp hooked_info(
         {:discord, {:student_mappings_for_course_loaded, _key, {:error, reason}}},
         socket
       ) do
    Logger.error("Discord student mappings for course load failed reason=#{inspect(reason)}")
    {:cont, socket}
  end

  defp hooked_info({:snow_course_cache, {:section_students_synced, key, {:ok, _result}}}, socket) do
    case fetch_state(socket.assigns, key) do
      %{assignment: assignment} when is_map(assignment) ->
        SnowCourseCacheDomainManager.request_section_students(
          pid: self(),
          key: key,
          term_code: assignment["term_code"],
          crn: assignment["crn"]
        )

      _other ->
        :ok
    end

    {:cont, socket}
  end

  defp hooked_info(
         {:snow_course_cache, {:section_students_synced, key, {:error, reason}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord student roster sync failed reason=#{inspect(reason)}")
        {:cont, put_state(socket, key, %{state | loading?: false, error: "Roster sync failed."})}
    end
  end

  defp hooked_info(
         {:discord, {:course_channel_assignment_loaded, key, {:ok, assignment}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        updated = %{state | assignment: assignment}

        if is_map(assignment) do
          {:cont,
           socket
           |> put_state(key, %{
             updated
             | students: [],
               student_items: [],
               loading?: true,
               error: nil
           })
           |> maybe_request_data(key: key, assignment: assignment)}
        else
          {:cont,
           put_state(socket, key, %{updated | students: [], student_items: [], loading?: false})}
        end
    end
  end

  defp hooked_info(
         {:discord, {:course_channel_assignment_loaded, key, {:error, reason}}},
         socket
       ) do
    case fetch_state(socket.assigns, key) do
      nil ->
        {:cont, socket}

      state ->
        Logger.error("Discord course assignment load failed reason=#{inspect(reason)}")

        {:cont,
         put_state(socket, key, %{
           state
           | loading?: false,
             error: "Could not load course assignment."
         })}
    end
  end

  defp hooked_info({:discord, {:student_discord_mapping_saved, _key, {:ok, _}}}, socket) do
    request_all_student_mappings(socket)
  end

  defp hooked_info(
         {:discord, {:student_discord_mapping_saved, _key, {:error, reason}}},
         socket
       ) do
    Logger.error("Discord student mapping save failed reason=#{inspect(reason)}")
    {:cont, socket}
  end

  defp hooked_info({:discord, {:student_discord_mapping_deleted, _key, {:ok, _}}}, socket) do
    request_all_student_mappings(socket)
  end

  defp hooked_info(
         {:discord, {:student_discord_mapping_deleted, _key, {:error, reason}}},
         socket
       ) do
    Logger.error("Discord student mapping delete failed reason=#{inspect(reason)}")
    {:cont, socket}
  end

  defp hooked_info({:discord, {:data_synced, _summary}}, socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{assignment: assignment}} when is_map(assignment) ->
        DiscordDomainManager.request_course_channel_assignment(
          pid: self(),
          key: key,
          channel_id: assignment["discord_channel_id"]
        )

      _assign ->
        :ok
    end)

    {:cont, socket}
  end

  defp hooked_info(_message, socket), do: {:cont, socket}

  # -- helpers --

  defp rebuild_student_items(socket, key) do
    case fetch_state(socket.assigns, key) do
      nil ->
        socket

      state ->
        student_row_states = Map.get(socket.assigns, :discord_student_row_states, %{})
        items = build_student_items(state, student_row_states)

        put_state(socket, key, %{state | student_items: items})
    end
  end

  defp build_student_items(state, student_row_states) do
    assignment = state.assignment
    mappings_by_badger_id = Map.new(state.filtered_mappings || [], &{&1["badger_id"], &1})

    (state.students || [])
    |> Enum.filter(&Map.get(&1, "badger_id"))
    |> Enum.sort_by(fn student -> String.downcase(Map.get(student, "last_name", "")) end)
    |> Enum.map(fn student ->
      mapping = Map.get(mappings_by_badger_id, student["badger_id"])
      row_key = student_row_key(state.key, student["badger_id"])

      row_state =
        DiscordStudentRow.fetch_state(
          %{:discord_student_row_states => student_row_states},
          row_key
        ) || %DiscordStudentRow{key: row_key}

      %{
        key: row_key,
        state: row_state,
        student: student,
        mapping: mapping,
        is_mapped: mapping != nil,
        required_role_id: if(is_map(assignment), do: assignment["discord_role_id"], else: nil)
      }
    end)
  end

  defp request_all_student_mappings(socket) do
    Enum.each(socket.assigns, fn
      {key, %__MODULE__{assignment: assignment}} when is_map(assignment) ->
        DiscordDomainManager.request_student_mappings_for_course(
          pid: self(),
          key: key,
          term_code: assignment["term_code"],
          crn: assignment["crn"]
        )

      _assign ->
        :ok
    end)

    {:cont, socket}
  end

  defp student_row_key(mapping_key, badger_id),
    do: "discord-student-row:#{mapping_key}:#{badger_id}"

  defp ensure_student_rows(socket, mapping_key, students) do
    Enum.reduce(students, socket, fn student, acc ->
      badger_id = Map.get(student, "badger_id")

      if is_binary(badger_id) do
        DiscordStudentRow.assign_component(acc, student_row_key(mapping_key, badger_id))
      else
        acc
      end
    end)
  end

  defp mapped_discord_user_ids(mappings) do
    mappings
    |> Enum.map(& &1["discord_user_id"])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp put_state(socket, key, state) do
    states = Map.get(socket.assigns, @state_assign, %{})
    assign(socket, @state_assign, Map.put(states, key, state))
  end
end
