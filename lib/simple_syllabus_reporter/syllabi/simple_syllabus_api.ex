defmodule SimpleSyllabusReporter.SimpleSyllabusApi do
  require Logger
  import SimpleSyllabusReporter.Cache

  alias SimpleSyllabusReporter.SyllabusSchemas

  @base_url "https://snow.simplesyllabus.com/api2"

  @doc """
  Searches for syllabi by a free-text query, fanning out to multiple API filter
  strategies simultaneously (instructor name, course title, course number) and
  merging the deduplicated results.

  Returns `{:ok, %{items: [...], pagination: %{total: n}}}` or `{:error, reason}`.
  """
  def search_syllabi(query) when is_binary(query) do
    fetch_syllabi_multi(query |> String.trim() |> String.downcase())
  end

  defp build_filter_sets(query) do
    base = [
      %{"editor" => query},
      %{"search" => query}
    ]

    # If the query is a pure integer, also search by course number
    case Integer.parse(String.trim(query)) do
      {n, ""} -> [%{"course_number" => n} | base]
      _ -> base
    end
  end

  ttl_cache def fetch_syllabi_multi(normalized_query) do
    all_items =
      normalized_query
      |> build_filter_sets()
      |> Task.async_stream(
        fn filters ->
          fetch_syllabi(normalize_filters(filters))
        end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, {:ok, %{items: items}}} ->
          items

        {:ok, {:error, reason}} ->
          Logger.warning("search_syllabi partial error reason=#{inspect(reason)}")
          []

        {:exit, reason} ->
          Logger.warning("search_syllabi task exit reason=#{inspect(reason)}")
          []
      end)

    # Deduplicate by "code", preserving first-seen order
    {deduplicated, _} =
      Enum.reduce(all_items, {[], MapSet.new()}, fn doc, {acc, seen} ->
        code = doc["code"]

        if MapSet.member?(seen, code) do
          {acc, seen}
        else
          {[doc | acc], MapSet.put(seen, code)}
        end
      end)

    deduplicated = Enum.reverse(deduplicated)

    Logger.info(
      "search_syllabi query=#{inspect(normalized_query)} raw=#{length(all_items)} deduped=#{length(deduplicated)}"
    )

    {:ok, %{items: deduplicated, pagination: %{"total" => length(deduplicated)}}}
  end

  defp normalize_filters(filters) do
    filters
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.reject(fn {_k, v} -> v == nil or v == "" or v == [] end)
    |> Enum.sort()
  end

  ttl_cache def fetch_syllabi(normalized_filters) do
    url = "#{@base_url}/doc-library-search"

    params =
      Enum.flat_map(normalized_filters, fn
        {"term_statuses", statuses} when is_list(statuses) ->
          Enum.map(statuses, fn s -> {"term_statuses[]", s} end)

        {"term_statuses", status} ->
          [{"term_statuses[]", status}]

        {k, v} ->
          [{k, v}]
      end)

    # Default to future terms if not specified
    params =
      if Enum.any?(params, fn {k, _} -> k == "term_statuses[]" end),
        do: params,
        else: params ++ [{"term_statuses[]", "future"}]

    case Req.get(url, params: params, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        raw_docs = Map.get(body, "items", [])
        pagination = Map.get(body, "pagination", %{})

        Logger.info(
          "search_syllabi filters=#{inspect(normalized_filters)} count=#{length(raw_docs)} total=#{pagination["total"]}"
        )

        {:ok, docs} = SyllabusSchemas.parse_list(raw_docs)
        {:ok, %{items: docs, pagination: pagination}}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning(
          "search_syllabi filters=#{inspect(normalized_filters)} status=#{status} body=#{inspect(body)}"
        )

        {:error, "Unexpected status #{status}"}

      {:error, reason} ->
        Logger.error(
          "search_syllabi filters=#{inspect(normalized_filters)} error=#{inspect(reason)}"
        )

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

  # ---------------------------------------------------------------------------
  # Organizations
  # ---------------------------------------------------------------------------

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

  @doc """
  Returns `{:ok, [org]}` where each org is a validated map with:
    - `"entity_id"`, `"name"`, `"level"` (1–3)
    - `"parent_id"` / `"parent_level"` (nil for root)
    - `"entity_type"` (`"organization1"` | `"organization2"` | `"organization3"`)
    - `"is_active"`, `"is_self_active"`, `"is_parent_active"`
    - `"locale"`, `"name_locale"`

  Results are cached for 6 hours.
  """
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
