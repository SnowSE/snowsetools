defmodule SimpleSyllabusReporter.SimpleSyllabusApi do
  @moduledoc """
  Pure HTTP service layer for the SimpleSyllabus API.

  Does not perform any caching — callers are responsible for caching.
  See `SimpleSyllabusReporter.Syllabi.SyllabusManager` for the caching layer.
  """
  require Logger
  import SimpleSyllabusReporter.Cache

  alias SimpleSyllabusReporter.SyllabusSchemas

  @base_url "https://snow.simplesyllabus.com/api2"

  @doc """
  Fetches all syllabi for an org from the API.

  Options:
    - `:term_statuses` — list of term status strings to filter by (default: `["future"]`). Pass `[]` for no filter.
  """
  def fetch_syllabi_by_org(org_id, opts \\ []) when is_binary(org_id) do
    term_statuses = Keyword.get(opts, :term_statuses, ["future"])
    term_id = Keyword.get(opts, :term_id)

    case fetch_syllabi_page(org_id, 0, term_statuses, term_id) do
      {:ok, %{"items" => first_page_raw, "pagination" => pagination}} ->
        all_raw =
          first_page_raw ++
            fetch_remaining_pages_by_org(org_id, pagination, term_statuses, term_id)

        Logger.info("fetch_syllabi_by_org org_id=#{org_id} fetched=#{length(all_raw)}")
        {:ok, docs} = SyllabusSchemas.parse_list(all_raw)
        {:ok, %{items: docs, pagination: pagination}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Fetches all syllabi for an editor email from the API."
  def fetch_syllabi_by_email(email) when is_binary(email) do
    case fetch_syllabi_page_by_editor(email, 0) do
      {:ok, %{"items" => first_page_raw, "pagination" => pagination}} ->
        all_raw = first_page_raw ++ fetch_remaining_pages_by_editor(email, pagination)
        Logger.info("fetch_syllabi_by_email email=#{email} fetched=#{length(all_raw)}")
        {:ok, docs} = SyllabusSchemas.parse_list(all_raw)
        {:ok, %{items: docs, pagination: pagination}}

      {:error, _} = err ->
        err
    end
  end

  @doc "Fetches full syllabus detail for a code from the API."
  def fetch_syllabus_detail(code) when is_binary(code) do
    url = "#{@base_url}/doc-full-page-get"

    case Req.get(url, params: [code: code], receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case body["items"] do
          [%{"doc_data" => doc_data} | _] ->
            Logger.info(
              "fetch_syllabus_detail code=#{inspect(code)} title=#{inspect(doc_data["title"])}"
            )

            doc_data
            |> sanitize_components()
            |> then(&SyllabusSchemas.parse_detail/1)

          _ ->
            Logger.warning("fetch_syllabus_detail code=#{inspect(code)} no items in response")
            {:error, "No document found"}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning(
          "fetch_syllabus_detail code=#{inspect(code)} status=#{status} body=#{inspect(body)}"
        )

        {:error, "Unexpected status #{status}"}

      {:error, reason} ->
        Logger.error("fetch_syllabus_detail code=#{inspect(code)} error=#{inspect(reason)}")
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

  defp fetch_remaining_pages_by_org(
         org_id,
         %{
           "total" => total,
           "returned" => returned,
           "page_size" => page_size
         },
         term_statuses,
         term_id
       ) do
    if total > returned do
      1..(ceil(total / page_size) - 1)
      |> Task.async_stream(
        fn page -> fetch_syllabi_page(org_id, page, term_statuses, term_id) end,
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
  end

  defp fetch_remaining_pages_by_editor(email, %{
         "total" => total,
         "returned" => returned,
         "page_size" => page_size
       }) do
    if total > returned do
      1..(ceil(total / page_size) - 1)
      |> Task.async_stream(fn page -> fetch_syllabi_page_by_editor(email, page) end,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, {:ok, %{"items" => items}}} ->
          items

        {:ok, {:error, reason}} ->
          Logger.warning(
            "fetch_syllabi_by_email page error email=#{email} reason=#{inspect(reason)}"
          )

          []

        {:exit, reason} ->
          Logger.warning(
            "fetch_syllabi_by_email page exit email=#{email} reason=#{inspect(reason)}"
          )

          []
      end)
    else
      []
    end
  end

  defp fetch_syllabi_page(org_id, page, term_statuses, term_id) do
    url = "#{@base_url}/doc-library-search"

    term_params = Enum.map(term_statuses, &{"term_statuses[]", &1})
    term_id_param = if term_id, do: [term_id: term_id], else: []

    case Req.get(url,
           params: [organization_id: org_id, page: page] ++ term_params ++ term_id_param,
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

  defp fetch_syllabi_page_by_editor(editor, page) do
    url = "#{@base_url}/doc-library-search"

    case Req.get(url,
           params: [editor: editor, page: page, "term_statuses[]": "future"],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning(
          "fetch_syllabi_page_by_editor editor=#{editor} page=#{page} status=#{status} body=#{inspect(body)}"
        )

        {:error, "Unexpected status #{status}"}

      {:error, reason} ->
        Logger.error(
          "fetch_syllabi_page_by_editor editor=#{editor} page=#{page} error=#{inspect(reason)}"
        )

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
end
