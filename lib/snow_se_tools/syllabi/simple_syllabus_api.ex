defmodule SnowSeTools.SimpleSyllabusApi do
  require Logger
  import SnowSeTools.Cache

  alias SnowSeTools.SyllabusSchemas
  alias SnowSeTools.Syllabi.Syncing.SyllabusSyncPubsub

  @base_url "https://snow.simplesyllabus.com/api2"
  @user_agent "Mozilla/5.0 (compatible; SnowSeTools/1.0)"

  defp req_opts(opts) do
    [receive_timeout: 10_000, headers: [{"User-Agent", @user_agent}]] ++ opts
  end

  @spec fetch_syllabi_metadata_list_by_org(binary, keyword) ::
          {:ok, %{syllabus_metadata_list: [map()]}} | {:error, term()}
  def fetch_syllabi_metadata_list_by_org(org_id, term_id: term_id)
      when is_binary(org_id) and is_binary(term_id) do
    case fetch_all_syllabi_metadata_list_pages_by_org(org_id, term_id) do
      {:ok, all_items} ->
        Logger.info(
          "fetch_syllabi_metadata_list_by_org org_id=#{org_id} term_id=#{term_id} fetched=#{length(all_items)}"
        )

        {:ok, %{syllabus_metadata_list: all_items}}

      {:error, reason} = err ->
        SyllabusSyncPubsub.broadcast_sync_error(
          "fetch_syllabi_metadata_list_by_org",
          "Failed to fetch syllabi list for org #{org_id} term #{term_id}: #{reason}"
        )

        err
    end
  end

  def fetch_syllabus_detail(code) when is_binary(code) do
    url = "#{@base_url}/doc-full-page-get"

    case Req.get(url, req_opts(params: [code: code])) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case body["items"] do
          [%{"doc_data" => doc_data} | _] ->
            doc_data
            |> sanitize_components()
            |> then(&SyllabusSchemas.parse_syllabus_detail/1)

          _ ->
            Logger.warning("fetch_syllabus_detail code=#{inspect(code)} no items in response")
            {:error, "No document found"}
        end

      {:ok, %Req.Response{status: status, body: _body}} ->
        SyllabusSyncPubsub.broadcast_sync_error(
          "fetch_syllabus_detail",
          "Failed to fetch syllabus detail for #{code}: Unexpected status #{status}"
        )

        {:error, "Unexpected status #{status}"}

      {:error, reason} ->
        SyllabusSyncPubsub.broadcast_sync_error(
          "fetch_syllabus_detail",
          "Failed to fetch syllabus detail for #{code}: #{inspect(reason)}"
        )

        {:error, inspect(reason)}
    end
  end

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

  @term_schema Zoi.object(%{
                 "entity_id" => Zoi.string(),
                 "name" => Zoi.string()
               })

  ttl_cache def get_organizations do
    url = "#{@base_url}/app-state"

    case Req.get(url, req_opts(params: [locale: "en-US"])) do
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

      {:ok, %Req.Response{status: status, body: _body}} ->
        error_msg = "Failed to fetch organizations: API returned status #{status}"
        SyllabusSyncPubsub.broadcast_sync_error("get_organizations", error_msg)
        {:error, error_msg}

      {:error, reason} ->
        error_msg = "Failed to fetch organizations: #{inspect(reason)}"
        SyllabusSyncPubsub.broadcast_sync_error("get_organizations", error_msg)
        {:error, error_msg}
    end
  end

  def get_available_terms do
    url = "#{@base_url}/app-state"

    case Req.get(url, req_opts(params: [locale: "en-US"])) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        raw_terms =
          body
          |> get_in(["items", Access.at(0), "state", "terms"])
          |> List.wrap()

        if Enum.all?(raw_terms, &is_nil/1) do
          {:error, "No terms found in API response"}
        else
          {terms, failures} =
            Enum.reduce(raw_terms, {[], []}, fn term, {valid_acc, fail_acc} ->
              case Zoi.parse(@term_schema, term) do
                {:ok, valid} ->
                  {[{valid["entity_id"], valid["name"]} | valid_acc], fail_acc}

                {:error, reason} ->
                  term_name = term["name"] || "unknown"
                  {valid_acc, ["#{term_name}: #{inspect(reason)}" | fail_acc]}
              end
            end)

          terms = Enum.reverse(terms)
          failures = Enum.reverse(failures)

          if Enum.empty?(terms) do
            error_details = Enum.join(Enum.reverse(failures), "; ")
            SyllabusSyncPubsub.broadcast_sync_error("get_available_terms", error_details)
            {:error, error_details}
          else
            {:ok, terms}
          end
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        error_msg =
          "Failed to fetch available terms: API returned status #{status}, body: #{inspect(body)}"

        SyllabusSyncPubsub.broadcast_sync_error("get_available_terms", error_msg)
        {:error, error_msg}

      {:error, reason} ->
        error_msg = "Failed to fetch available terms: #{inspect(reason)}"
        SyllabusSyncPubsub.broadcast_sync_error("get_available_terms", error_msg)
        {:error, error_msg}
    end
  end

  defp fetch_all_syllabi_metadata_list_pages_by_org(org_id, term_id) do
    url = "#{@base_url}/doc-library-search"

    case fetch_paginated_items(url, organization_id: org_id, "term_ids[]": term_id) do
      {:ok, all_items} ->
        {:ok, list_items} = SyllabusSchemas.parse_syllabi_metadata_list(all_items)
        {:ok, list_items}

      {:error, reason} ->
        SyllabusSyncPubsub.broadcast_sync_error(
          "fetch_all_syllabi_metadata_list_pages_by_org",
          "Failed to fetch syllabi metadata list for org #{org_id} term #{term_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp fetch_paginated_items(url, params, current_page \\ 0, total_pages \\ nil, acc \\ []) do
    page_params = Keyword.put(params, :page, current_page)

    case Req.get(url, req_opts(params: page_params)) do
      {:ok, %Req.Response{status: 200, body: %{"items" => items, "pagination" => pagination}}}
      when is_nil(total_pages) ->
        new_total_pages = ceil(pagination["total"] / pagination["page_size"])

        fetch_paginated_items(url, params, 1, new_total_pages, items)

      {:ok, %Req.Response{status: 200, body: %{"items" => items}}} when not is_nil(total_pages) ->
        new_acc = acc ++ items

        if current_page + 1 >= total_pages do
          {:ok, new_acc}
        else
          fetch_paginated_items(url, params, current_page + 1, total_pages, new_acc)
        end

      {:ok, %Req.Response{status: status}} when is_nil(total_pages) ->
        {:error, "Unexpected status #{status} from #{url}"}

      {:ok, %Req.Response{status: status}} when not is_nil(total_pages) ->
        Logger.warning(
          "fetch_paginated_items status error url=#{url} page=#{current_page} status=#{status}"
        )

        if current_page + 1 >= total_pages do
          {:ok, acc}
        else
          fetch_paginated_items(url, params, current_page + 1, total_pages, acc)
        end

      {:error, reason} when is_nil(total_pages) ->
        {:error, "Request failed for #{url}: #{inspect(reason)}"}

      {:error, reason} when not is_nil(total_pages) ->
        Logger.warning(
          "fetch_paginated_items error url=#{url} page=#{current_page} reason=#{inspect(reason)}"
        )

        if current_page + 1 >= total_pages do
          {:ok, acc}
        else
          fetch_paginated_items(url, params, current_page + 1, total_pages, acc)
        end
    end
  end

  defp sanitize_components(doc_data) do
    components =
      (doc_data["components"] || [])
      |> Enum.map(fn component ->
        Map.update(component, "html", "", &SnowSeTools.SyllabusScrubber.sanitize/1)
      end)

    Map.put(doc_data, "components", components)
  end
end
