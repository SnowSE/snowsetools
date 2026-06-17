defmodule SnowSeTools.Snow.SnowCourseCacheDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.Snow.{SnowCourseCacheDb, MySnowApi}
  alias SnowSeToolsWeb.Admin.AdminSnowCoursesUIMessages

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def request_dashboard(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_dashboard, pid})
  end

  def sync_course_list(pid: pid, term_code: term_code, jwt_token: jwt_token) do
    GenServer.cast(__MODULE__, {:sync_course_list, pid, term_code, jwt_token})
  end

  def sync_term_rosters(pid: pid, term_code: term_code, jwt_token: jwt_token) do
    GenServer.cast(__MODULE__, {:sync_term_rosters, pid, term_code, jwt_token})
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
  def handle_cast({:request_dashboard, pid}, state) do
    send_snapshot(pid)
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
          :ok -> {:ok, length(students)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
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
