defmodule SnowSeToolsWeb.Scheduling.CourseListForTerm do
  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeTools.Snow.{SnowCourseCacheDomainManager, SnowCourseCachePubSub}

  defstruct [
    :selected_term_code,
    :courses,
    :loading?,
    :error
  ]

  @key :scheduling_course_data

  def assign_component(socket) do
    socket
    |> assign_new(@key, fn ->
      %__MODULE__{
        selected_term_code: nil,
        courses: [],
        loading?: false,
        error: nil
      }
    end)
    |> maybe_attach_hooks()
  end

  def courses(%__MODULE__{courses: courses}), do: courses
  def courses(_state), do: []

  def sync_selected_term(socket, term_code: term_code) when is_binary(term_code) do
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      socket
    else
      socket
      |> assign(@key, %{
        state
        | selected_term_code: term_code,
          courses: [],
          loading?: true,
          error: nil
      })
      |> request_term_courses(term_code: term_code)
    end
  end

  def sync_selected_term(socket, term_code: nil) do
    assign(socket, @key, %{
      socket.assigns[@key]
      | selected_term_code: nil,
        courses: [],
        loading?: false,
        error: nil
    })
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :scheduling_course_data_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("scheduling-course-data:info", :handle_info, &hooked_info/2)
      |> put_in([Access.key(:private), :scheduling_course_data_hooks_attached?], true)
    end
  end

  def hooked_info(
        {:snow_course_cache,
         {:term_courses_loaded, {:ok, %{term_code: term_code, courses: courses}}}},
        socket
      ) do
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      {:halt, assign(socket, @key, %{state | courses: courses, loading?: false, error: nil})}
    else
      {:halt, socket}
    end
  end

  def hooked_info(
        {:snow_course_cache,
         {:term_courses_loaded, {:error, %{term_code: term_code, reason: reason}}}},
        socket
      ) do
    Logger.error(
      "CourseListForTerm failed to load term courses term_code=#{term_code} reason=#{inspect(reason)}"
    )

    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      {:halt,
       socket
       |> assign(@key, %{state | courses: [], loading?: false, error: reason})
       |> LiveView.put_flash(:error, "Could not load courses for the selected term.")}
    else
      {:halt, socket}
    end
  end

  def hooked_info({:snow_course_cache, {:course_cache_updated, term_code, _term_name}}, socket) do
    refresh_selected_term(socket, term_code: term_code)
  end

  def hooked_info({:snow_course_cache, {:course_cache_updated, %{term_code: term_code}}}, socket) do
    refresh_selected_term(socket, term_code: term_code)
  end

  def hooked_info({:snow_course_cache, {:course_cache_updated, _summary}}, socket) do
    refresh_selected_term(socket, term_code: socket.assigns[@key].selected_term_code)
  end

  def hooked_info({:snow_course_cache, {:course_cache_deleted, term_code}}, socket) do
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      {:halt, assign(socket, @key, %{state | courses: [], loading?: false, error: nil})}
    else
      {:halt, socket}
    end
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  defp refresh_selected_term(socket, term_code: term_code)
       when is_binary(term_code) do
    state = socket.assigns[@key]

    if state.selected_term_code == term_code do
      {:halt,
       socket
       |> assign(@key, %{state | loading?: true, error: nil})
       |> request_term_courses(term_code: term_code)}
    else
      {:halt, socket}
    end
  end

  defp refresh_selected_term(socket, term_code: _term_code), do: {:halt, socket}

  defp request_term_courses(socket, term_code: term_code) do
    if LiveView.connected?(socket) do
      SnowCourseCachePubSub.subscribe()

      if Process.whereis(SnowCourseCacheDomainManager) do
        SnowCourseCacheDomainManager.request_term_courses(pid: self(), term_code: term_code)
        socket
      else
        Logger.error(
          "CourseListForTerm could not request term courses because SnowCourseCacheDomainManager is not running"
        )

        socket
        |> assign(@key, %{socket.assigns[@key] | loading?: false, error: :not_running})
        |> LiveView.put_flash(:error, "Could not request courses for the selected term.")
      end
    else
      socket
    end
  end
end
