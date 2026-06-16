defmodule SnowSeTools.Syllabi.SyncWorker do
  require Logger

  alias SnowSeTools.SimpleSyllabusApi

  alias SnowSeTools.Syllabi.{
    SyllabusDB,
    CachedOrganizationsDb,
    AvailableTermsDb
  }

  @max_concurrent_requests 4

  def sync_term(term_id: term_id) do
    Logger.info("SyncWorker starting term sync term_id=#{term_id}")

    case get_schools() do
      {:error, _} = err ->
        err

      {:ok, schools, total_schools} ->
        Logger.info("SyncWorker syncing #{total_schools} schools term_id=#{term_id}")

        case fetch_all_orgs_syllabi_metadata(term_id: term_id, schools: schools) do
          {:error, _} = err ->
            err

          {:ok, all_syllabi} ->
            syllabi_codes = Enum.map(all_syllabi, & &1["code"])

            SnowSeTools.Syllabi.Syncing.SyllabusScraperAgent.report_syllabi_to_sync(
              length(syllabi_codes)
            )

            Task.async_stream(
              all_syllabi,
              fn syllabus ->
                sync_single_syllabus(syllabus: syllabus)
              end,
              max_concurrency: @max_concurrent_requests,
              timeout: 60_000,
              on_timeout: :kill_task
            )
            |> Enum.reduce_while(:ok, fn task_result, :ok ->
              case task_result do
                {:ok, :ok} ->
                  SnowSeTools.Syllabi.Syncing.SyllabusScraperAgent.report_syllabus_synced()
                  {:cont, :ok}

                {:ok, {:error, reason}} ->
                  SnowSeTools.Syllabi.Syncing.SyllabusScraperAgent.report_sync_error(reason)

                  {:halt, {:error, reason}}

                {:exit, reason} ->
                  SnowSeTools.Syllabi.Syncing.SyllabusScraperAgent.report_sync_error(reason)

                  {:halt, {:error, reason}}
              end
            end)
        end
    end
  end

  defp get_schools do
    with {:ok, orgs} <- SimpleSyllabusApi.get_organizations(),
         :ok <- CachedOrganizationsDb.upsert_organizations(orgs) do
      schools = Enum.filter(orgs, &(&1["level"] == 2 && &1["is_self_active"]))
      total_schools = length(schools)
      {:ok, schools, total_schools}
    else
      {:error, reason} ->
        Logger.error("SyncWorker failed to get schools reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  def sync_term_list do
    Logger.info("SyncWorker starting term list sync")

    case SimpleSyllabusApi.get_available_terms() do
      {:ok, terms} ->
        term_count = length(terms)
        Logger.info("SyncWorker fetched #{term_count} available terms")

        case AvailableTermsDb.upsert_terms(terms) do
          :ok ->
            {:ok, term_count}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("SyncWorker failed to fetch terms reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_all_orgs_syllabi_metadata(term_id: term_id, schools: schools) do
    Logger.info("SyncWorker fetching all syllabi metadata by org")

    result =
      schools
      |> Enum.with_index()
      |> Task.async_stream(
        fn {org, idx} ->
          fetch_org_metadata(term_id: term_id, org: org, org_index: idx)
        end,
        max_concurrency: @max_concurrent_requests,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce({:ok, %{}}, fn task_result, acc ->
        case {task_result, acc} do
          {{:ok, {:ok, {org_id, syllabi}}}, {:ok, acc_map}} ->
            {:ok, Map.put(acc_map, org_id, syllabi)}

          {{:ok, {:error, reason}}, _} ->
            {:error, reason}

          {{:exit, _reason}, acc} ->
            acc
        end
      end)

    case result do
      {:ok, syllabi_by_org} ->
        Logger.info("SyncWorker fetched syllabi for #{map_size(syllabi_by_org)} orgs")

        all_syllabi =
          Enum.flat_map(syllabi_by_org, fn {org_id, syllabi} ->
            Enum.map(syllabi, &Map.put(&1, "__org_id", org_id))
          end)

        {:ok, all_syllabi}

      {:error, _} = err ->
        err
    end
  end

  defp fetch_org_metadata(term_id: term_id, org: org, org_index: org_index) do
    org_id = org["entity_id"]
    org_name = org["name"]

    Logger.info(
      "SyncWorker fetching metadata org #{org_index + 1} org_id=#{org_id} org_name=#{org_name}"
    )

    case SimpleSyllabusApi.fetch_syllabi_metadata_list_by_org(org_id, term_id: term_id) do
      {:ok, %{syllabus_metadata_list: syllabi}} ->
        Logger.info("SyncWorker fetched #{length(syllabi)} syllabi metadata org_id=#{org_id}")

        {:ok, {org_id, syllabi}}

      {:error, reason} ->
        Logger.error(
          "SyncWorker failed to fetch syllabi metadata org_id=#{org_id} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp sync_single_syllabus(syllabus: syl) do
    code = syl["code"]

    case SimpleSyllabusApi.fetch_syllabus_detail(code) do
      {:ok, detail} ->
        case SyllabusDB.upsert_syllabus(
               syllabus_metadata: syl,
               syllabus_details: detail,
               org_id: syl["__org_id"],
               linked_email: nil
             ) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("SyncWorker upsert failed code=#{code} reason=#{inspect(reason)}")
            {:error, "Failed to upsert syllabus #{code}: #{reason}"}
        end

      {:error, reason} ->
        Logger.error("SyncWorker detail fetch failed code=#{code} reason=#{inspect(reason)}")
        {:error, "Failed to fetch detail for syllabus #{code}: #{reason}"}
    end
  end
end
