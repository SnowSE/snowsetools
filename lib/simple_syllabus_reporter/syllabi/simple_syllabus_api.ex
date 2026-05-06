defmodule SimpleSyllabusReporter.SimpleSyllabusApi do
  require Logger
  import SimpleSyllabusReporter.Cache

  alias SimpleSyllabusReporter.SyllabusSchemas

  @base_url "https://snow.simplesyllabus.com/api2"

  def search_syllabi(org_id) when is_binary(org_id) do
    fetch_syllabi_by_org(org_id)
  end

  ttl_cache def fetch_syllabi_by_org(org_id) do
    case fetch_syllabi_page(org_id, 0) do
      {:ok, %{"items" => first_page_raw, "pagination" => pagination}} ->
        %{"total" => total, "returned" => returned, "page_size" => page_size} = pagination

        remaining_pages =
          if total > returned do
            last_page = ceil(total / page_size) - 1

            1..last_page
            |> Task.async_stream(
              fn page -> fetch_syllabi_page(org_id, page) end,
              timeout: 15_000,
              on_timeout: :kill_task
            )
            |> Enum.flat_map(fn
              {:ok, {:ok, %{"items" => items}}} ->
                items

              {:ok, {:error, reason}} ->
                Logger.warning(
                  "fetch_syllabi_by_org page error org_id=#{org_id} reason=#{inspect(reason)}"
                )

                []

              {:exit, reason} ->
                Logger.warning(
                  "fetch_syllabi_by_org page exit org_id=#{org_id} reason=#{inspect(reason)}"
                )

                []
            end)
          else
            []
          end

        all_raw = first_page_raw ++ remaining_pages

        Logger.info(
          "fetch_syllabi_by_org org_id=#{org_id} total=#{total} fetched=#{length(all_raw)}"
        )

        {:ok, docs} = SyllabusSchemas.parse_list(all_raw)
        {:ok, %{items: docs, pagination: pagination}}

      {:error, _} = err ->
        err
    end
  end

  defp fetch_syllabi_page(org_id, page) do
    url = "#{@base_url}/doc-library-search"

    case Req.get(url,
           params: [organization_id: org_id, page: page, "term_statuses[]": "future"],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning(
          "fetch_syllabi_page org_id=#{org_id} page=#{page} status=#{status} body=#{inspect(body)}"
        )

        {:error, "Unexpected status #{status}"}

      {:error, reason} ->
        Logger.error("fetch_syllabi_page org_id=#{org_id} page=#{page} error=#{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  ttl_cache def get_syllabus_details(code) do
    url = "#{@base_url}/doc-full-page-get"

    case Req.get(url,
           params: [code: code],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case body["items"] do
          [%{"doc_data" => doc_data} | _] ->
            Logger.info(
              "get_syllabus_details code=#{inspect(code)} title=#{inspect(doc_data["title"])}"
            )

            doc_data
            |> sanitize_components()
            |> then(&SyllabusSchemas.parse_detail/1)

          _ ->
            Logger.warning("get_syllabus_details code=#{inspect(code)} no items in response")
            {:error, "No document found"}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning(
          "get_syllabus_details code=#{inspect(code)} status=#{status} body=#{inspect(body)}"
        )

        {:error, "Unexpected status #{status}"}

      {:error, reason} ->
        Logger.error("get_syllabus_details code=#{inspect(code)} error=#{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  defp sanitize_components(doc_data) do
    components =
      (doc_data["components"] || [])
      |> Enum.map(fn component ->
        Map.update(component, "html", "", &SimpleSyllabusReporter.SyllabusScrubber.sanitize/1)
      end)

    Map.put(doc_data, "components", components)
  end

  @organization_schema Zoi.object(%{
                         "entity_id" => Zoi.string(),
                         "name" => Zoi.string(),
                         "level" => Zoi.integer(),
                         "parent_id" => Zoi.nullable(Zoi.string()),
                         "parent_level" => Zoi.nullable(Zoi.integer()),
                         "entity_type" => Zoi.string(),
                         "is_active" => Zoi.boolean(),
                         "is_self_active" => Zoi.boolean(),
                         "is_parent_active" => Zoi.boolean(),
                         "locale" => Zoi.string(),
                         "name_locale" => Zoi.string()
                       })

  def get_departments do
    case get_organizations() do
      {:ok, orgs} ->
        departments =
          orgs
          |> Enum.filter(&(&1["is_self_active"] && &1["level"] >= 2))
          |> Enum.sort_by(&{&1["level"], &1["name"]})

        {:ok, departments}

      {:error, _} = err ->
        err
    end
  end

  ttl_cache def get_organizations do
    url = "#{@base_url}/app-state"

    case Req.get(url, params: [locale: "en-US"], receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        raw_orgs =
          body
          |> get_in(["items", Access.at(0), "state", "organizations"])
          |> List.wrap()

        orgs =
          Enum.flat_map(raw_orgs, fn org ->
            case Zoi.parse(@organization_schema, org) do
              {:ok, valid} ->
                [valid]

              {:error, reason} ->
                Logger.warning(
                  "get_organizations validation failed org=#{inspect(org["name"])} reason=#{inspect(reason)}"
                )

                []
            end
          end)

        Logger.info("get_organizations fetched count=#{length(orgs)}")
        {:ok, orgs}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("get_organizations status=#{status} body=#{inspect(body)}")
        {:error, "Unexpected status #{status}"}

      {:error, reason} ->
        Logger.error("get_organizations error=#{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end
end
