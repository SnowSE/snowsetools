defmodule SnowSeTools.Snow.SnowCourseCacheDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.Snow.{SnowCourseCacheDb, MySnowApi, SnowCourseCachePubSub}
  alias SnowSeToolsWeb.Admin.AdminSnowCoursesUIMessages

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def request_dashboard(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_dashboard, pid})
  end

  def request_course_catalog(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_course_catalog, pid})
  end

  def request_all_courses(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_all_courses, pid})
  end

  def request_term_courses(pid: pid, term_code: term_code)
      when is_pid(pid) and is_binary(term_code) do
    GenServer.cast(__MODULE__, {:request_term_courses, pid, term_code})
  end

  def request_term_courses(pid: pid, key: key, term_code: term_code)
      when is_pid(pid) and is_binary(term_code) do
    GenServer.cast(__MODULE__, {:request_term_courses, pid, key, term_code})
  end

  def request_section_students(pid: pid, key: key, term_code: term_code, crn: crn)
      when is_pid(pid) and is_binary(term_code) and is_binary(crn) do
    GenServer.cast(__MODULE__, {:request_section_students, pid, key, term_code, crn})
  end

  def request_course(pid: pid, key: key, term_code: term_code, crn: crn)
      when is_pid(pid) and is_binary(term_code) and is_binary(crn) do
    GenServer.cast(__MODULE__, {:request_course, pid, key, term_code, crn})
  end

  def sync_course_list(pid: pid, term_code: term_code, jwt_token: jwt_token) do
    GenServer.cast(__MODULE__, {:sync_course_list, pid, term_code, jwt_token})
  end

  def sync_term_rosters(pid: pid, term_code: term_code, jwt_token: jwt_token) do
    GenServer.cast(__MODULE__, {:sync_term_rosters, pid, term_code, jwt_token})
  end

  def sync_section_students(pid: pid, term_code: term_code, crn: crn, jwt_token: jwt_token) do
    GenServer.cast(__MODULE__, {:sync_section_students, pid, term_code, crn, jwt_token})
  end

  def delete_term(pid: pid, term_code: term_code) do
    GenServer.cast(__MODULE__, {:delete_term, pid, term_code})
  end

  @impl true
  def init(:ok) do
    case SnowCourseCacheDb.bootstrap_cache_tables() do
      {:error, reason} ->
        Logger.error("Snow course cache bootstrap failed reason=#{inspect(reason)}")
        {:stop, reason}

      _ ->
        {:ok, %{}}
    end
  end

  @impl true
  def handle_cast({:request_all_courses, pid}, state) do
    result =
      case SnowCourseCacheDb.list_terms_with_courses() do
        {:ok, terms} -> {:ok, group_courses_by_term(terms)}
        {:error, reason} -> {:error, reason}
        [] -> {:ok, %{}}
      end

    send(pid, {:snow_course_cache, {:all_courses_loaded, result}})
    {:noreply, state}
  end

  def handle_cast({:request_dashboard, pid}, state) do
    send_snapshot(pid)
    {:noreply, state}
  end

  def handle_cast({:request_course_catalog, pid}, state) do
    catalog =
      case SnowCourseCacheDb.list_course_catalog() do
        {:error, reason} ->
          Logger.error("Snow course cache catalog load failed reason=#{inspect(reason)}")
          {:error, reason}

        courses ->
          {:ok, courses}
      end

    send(pid, {:snow_course_cache, {:course_catalog_loaded, catalog}})
    {:noreply, state}
  end

  def handle_cast({:request_term_courses, pid, term_code}, state) do
    result =
      case SnowCourseCacheDb.list_course_data_for_term(term_code: term_code) do
        {:ok, courses} ->
          {:ok, %{term_code: term_code, courses: courses}}

        {:error, reason} ->
          Logger.error(
            "Snow course cache term course load failed term_code=#{term_code} reason=#{inspect(reason)}"
          )

          {:error, %{term_code: term_code, reason: reason}}
      end

    send(pid, {:snow_course_cache, {:term_courses_loaded, result}})
    {:noreply, state}
  end

  def handle_cast({:request_term_courses, pid, key, term_code}, state) do
    result =
      case SnowCourseCacheDb.list_course_data_for_term(term_code: term_code) do
        {:ok, courses} ->
          {:ok, %{term_code: term_code, courses: courses}}

        {:error, reason} ->
          Logger.error(
            "Snow course cache term course load failed term_code=#{term_code} reason=#{inspect(reason)}"
          )

          {:error, %{term_code: term_code, reason: reason}}
      end

    send(pid, {:snow_course_cache, {:term_courses_loaded, key, result}})
    {:noreply, state}
  end

  def handle_cast({:request_section_students, pid, key, term_code, crn}, state) do
    result =
      case SnowCourseCacheDb.get_section_students(term_code: term_code, crn: crn) do
        {:ok, students} -> {:ok, %{term_code: term_code, crn: crn, students: students}}
        {:error, reason} -> {:error, %{term_code: term_code, crn: crn, reason: reason}}
      end

    send(pid, {:snow_course_cache, {:section_students_loaded, key, result}})
    {:noreply, state}
  end

  def handle_cast({:request_course, pid, key, term_code, crn}, state) do
    result =
      case SnowCourseCacheDb.get_course(term_code: term_code, crn: crn) do
        {:error, reason} -> {:error, %{term_code: term_code, crn: crn, reason: reason}}
        nil -> {:ok, %{term_code: term_code, crn: crn, course: nil}}
        course -> {:ok, %{term_code: term_code, crn: crn, course: course}}
      end

    send(pid, {:snow_course_cache, {:course_loaded, key, result}})
    {:noreply, state}
  end

  def handle_cast({:sync_course_list, pid, term_code, jwt_token}, state) do
    Task.start(fn -> sync_course_list_async(pid, term_code, jwt_token) end)
    {:noreply, state}
  end

  def handle_cast({:sync_term_rosters, pid, term_code, jwt_token}, state) do
    Task.start(fn -> sync_term_rosters_async(pid, term_code, jwt_token) end)
    {:noreply, state}
  end

  def handle_cast({:sync_section_students, pid, key, term_code, crn, jwt_token}, state) do
    Task.start(fn -> sync_section_students_async(pid, key, term_code, crn, jwt_token) end)
    {:noreply, state}
  end

  def handle_cast({:delete_term, pid, term_code}, state) do
    case SnowCourseCacheDb.delete_term(term_code: term_code) do
      {:error, reason} ->
        AdminSnowCoursesUIMessages.send_snow_cache_action_result(
          pid: pid,
          result: {:error, reason}
        )

      _ ->
        SnowCourseCachePubSub.broadcast_course_cache_deleted(term_code)

        AdminSnowCoursesUIMessages.send_snow_cache_action_result(
          pid: pid,
          result: {:ok, "Deleted #{build_term_display_name(term_code)}."}
        )

        send_snapshot(pid)
    end

    {:noreply, state}
  end

  defp sync_course_list_async(pid, term_code, jwt_token) do
    term_name = build_term_display_name(term_code)

    case MySnowApi.fetch_course_list(term_code: term_code, jwt_token: jwt_token) do
      {:ok, courses} ->
        case SnowCourseCacheDb.save_courses(
               term_code: term_code,
               term_name: term_name,
               courses: courses
             ) do
          :ok ->
            SnowCourseCachePubSub.broadcast_course_cache_updated(term_code, term_name)

            AdminSnowCoursesUIMessages.send_snow_cache_action_result(
              pid: pid,
              result: {:ok, "Cached #{length(courses)} courses for #{term_name}."}
            )

            send_snapshot(pid)

          {:error, reason} ->
            AdminSnowCoursesUIMessages.send_snow_cache_action_result(
              pid: pid,
              result: {:error, reason}
            )
        end

      {:error, reason} ->
        AdminSnowCoursesUIMessages.send_snow_cache_action_result(
          pid: pid,
          result: {:error, reason}
        )
    end
  end

  defp sync_term_rosters_async(pid, term_code, jwt_token) do
    case SnowCourseCacheDb.list_courses_for_term(term_code: term_code) do
      {:error, reason} ->
        AdminSnowCoursesUIMessages.send_snow_cache_action_result(
          pid: pid,
          result: {:error, reason}
        )

      [] ->
        AdminSnowCoursesUIMessages.send_snow_cache_action_result(
          pid: pid,
          result: {:error, "No cached courses found for #{term_code}."}
        )

      courses ->
        results =
          courses
          |> Task.async_stream(
            fn course ->
              sync_single_roster(term_code, course["crn"], jwt_token)
            end,
            timeout: :infinity,
            max_concurrency: 4
          )
          |> Enum.to_list()

        {synced_count, failed_reasons} =
          Enum.reduce(results, {0, []}, fn
            {:ok, {:ok, _count}}, {success_count, reasons} ->
              {success_count + 1, reasons}

            {:ok, {:error, reason}}, {success_count, reasons} ->
              {success_count, [reason | reasons]}

            {:exit, reason}, {success_count, reasons} ->
              {success_count, [inspect(reason) | reasons]}
          end)

        total = length(courses)

        if failed_reasons == [] do
          AdminSnowCoursesUIMessages.send_snow_cache_action_result(
            pid: pid,
            result:
              {:ok,
               "Cached #{synced_count}/#{total} rosters for #{build_term_display_name(term_code)}."}
          )
        else
          AdminSnowCoursesUIMessages.send_snow_cache_action_result(
            pid: pid,
            result:
              {:error,
               "Cached #{synced_count}/#{total} rosters for #{build_term_display_name(term_code)}; failures: #{Enum.join(Enum.reverse(failed_reasons), "; ")}"}
          )
        end

        send_snapshot(pid)
    end
  end

  defp sync_single_roster(term_code, crn, jwt_token) do
    case MySnowApi.fetch_section_students(term_code: term_code, crn: crn, jwt_token: jwt_token) do
      {:ok, students} ->
        case SnowCourseCacheDb.save_section_students(
               term_code: term_code,
               crn: crn,
               students: students
             ) do
          :ok ->
            {:ok, length(students)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_section_students_async(pid, key, term_code, crn, jwt_token) do
    case sync_single_roster(term_code, crn, jwt_token) do
      {:ok, count} ->
        send(
          pid,
          {:snow_course_cache,
           {:section_students_synced, key, {:ok, %{term_code: term_code, crn: crn, count: count}}}}
        )

      {:error, reason} ->
        Logger.error(
          "Snow course section roster sync failed term_code=#{term_code} crn=#{crn} reason=#{inspect(reason)}"
        )

        send(
          pid,
          {:snow_course_cache,
           {:section_students_synced, key,
            {:error, %{term_code: term_code, crn: crn, reason: reason}}}}
        )
    end
  end

  defp send_snapshot(pid) do
    case load_snapshot() do
      {:ok, terms} ->
        AdminSnowCoursesUIMessages.send_snow_cache_terms(pid: pid, terms: terms)

      {:error, reason} ->
        AdminSnowCoursesUIMessages.send_snow_cache_snapshot_error(pid: pid, reason: reason)
    end
  end

  defp load_snapshot do
    case SnowCourseCacheDb.list_terms_with_courses() do
      {:error, reason} ->
        {:error, reason}

      [] ->
        {:ok, []}

      terms ->
        term_tasks =
          terms
          |> Task.async_stream(
            fn term ->
              case SnowCourseCacheDb.list_courses_for_term(term_code: term["term_code"]) do
                {:error, reason} ->
                  {:error, reason}

                courses ->
                  {:ok, Map.put(term, "courses", courses)}
              end
            end,
            timeout: :infinity,
            max_concurrency: 4
          )
          |> Enum.to_list()

        case Enum.find(term_tasks, fn
               {:ok, {:error, _}} -> true
               {:exit, _} -> true
               _ -> false
             end) do
          {:ok, {:error, reason}} ->
            {:error, reason}

          {:exit, reason} ->
            {:error, inspect(reason)}

          nil ->
            loaded_terms =
              Enum.map(term_tasks, fn {:ok, {:ok, term}} -> term end)

            {:ok, loaded_terms}
        end
    end
  end

  defp group_courses_by_term(terms) do
    terms
    |> Enum.map(fn term -> {term["term_code"], term["courses"]} end)
    |> Map.new()
  end

  defp build_term_display_name(term_code) when is_binary(term_code) do
    case String.length(term_code) >= 6 do
      true ->
        year = String.slice(term_code, 0, 4)
        semester_code = String.slice(term_code, 4, 2)

        semester_name =
          case semester_code do
            "10" -> "Spring"
            "30" -> "Summer"
            "40" -> "Fall"
            _ -> semester_code
          end

        "#{semester_name} #{year}"

      false ->
        term_code
    end
  end
end
