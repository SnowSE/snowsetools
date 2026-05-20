defmodule SimpleSyllabusReporter.Syllabi.SyllabusManager do
  @moduledoc """
  Orchestration layer for syllabus data. Serves cached results from the
  database when available and falls back to the SimpleSyllabus API,
  persisting fetched data for future requests.
  """
  require Logger

  alias SimpleSyllabusReporter.SimpleSyllabusApi
  alias SimpleSyllabusReporter.Syllabi.SyllabusDB

  @doc """
  Returns syllabi for an org. Serves from DB cache when available;
  fetches from the API and persists on a cache miss.

  Returns `{:ok, %{items: docs, cached_at: datetime_or_nil}}` or `{:error, term}`.
  """
  def search_by_org(org_id) do
    case SyllabusDB.list_by_org(org_id) do
      {:ok, [_ | _] = docs, cached_at} ->
        {:ok, %{items: docs, cached_at: cached_at}}

      {:ok, [], _} ->
        fetch_and_persist_by_org(org_id)

      {:error, reason} ->
        Logger.warning(
          "SyllabusManager.search_by_org DB read failed, falling back to API reason=#{inspect(reason)}"
        )

        fetch_and_persist_by_org(org_id)
    end
  end

  @doc """
  Returns syllabi for an editor email. Serves from DB cache when available;
  fetches from the API and persists on a cache miss.

  Returns `{:ok, %{items: docs, cached_at: datetime_or_nil}}` or `{:error, term}`.
  """
  def search_by_email(email) do
    case SyllabusDB.list_by_editor_email(email) do
      {:ok, [_ | _] = docs, cached_at} ->
        {:ok, %{items: docs, cached_at: cached_at}}

      {:ok, [], _} ->
        fetch_and_persist_by_email(email)

      {:error, reason} ->
        Logger.warning(
          "SyllabusManager.search_by_email DB read failed, falling back to API reason=#{inspect(reason)}"
        )

        fetch_and_persist_by_email(email)
    end
  end

  @doc """
  Returns full detail for a syllabus code. Serves from DB cache when available;
  fetches from the API and persists on a cache miss.

  Returns `{:ok, doc}` or `{:error, term}`.
  """
  def get_detail(code) do
    case SyllabusDB.get_detail(code) do
      {:ok, doc, _cached_at} when not is_nil(doc) ->
        {:ok, doc}

      {:ok, nil, _} ->
        fetch_and_persist_detail(code)

      {:error, reason} ->
        Logger.warning(
          "SyllabusManager.get_detail DB read failed, falling back to API code=#{code} reason=#{inspect(reason)}"
        )

        fetch_and_persist_detail(code)
    end
  end

  @doc "Returns all level-2 schools. Falls back to API list when DB is empty."
  def get_departments do
    with {:ok, orgs} <- SimpleSyllabusApi.get_organizations(),
         {:ok, populated_ids} <- SyllabusDB.list_populated_org_ids() do
      populated = MapSet.new(populated_ids)

      schools =
        orgs
        |> Enum.filter(&(&1["level"] == 2 && &1["is_self_active"]))
        |> Enum.sort_by(& &1["name"])

      if Enum.any?(schools, &MapSet.member?(populated, &1["entity_id"])) do
        {:ok, schools}
      else
        # DB not yet populated — return all schools so the UI isn't empty
        {:ok, schools}
      end
    end
  end

  defp fetch_and_persist_by_org(org_id) do
    case SimpleSyllabusApi.fetch_syllabi_by_org(org_id) do
      {:ok, %{items: docs} = result} ->
        Task.start(fn -> SyllabusDB.upsert_list_items(docs, org_id: org_id) end)
        {:ok, Map.put(result, :cached_at, nil)}

      {:error, _} = err ->
        err
    end
  end

  defp fetch_and_persist_by_email(email) do
    case SimpleSyllabusApi.fetch_syllabi_by_email(email) do
      {:ok, %{items: docs} = result} ->
        Task.start(fn -> SyllabusDB.upsert_list_items(docs, linked_email: email) end)
        {:ok, Map.put(result, :cached_at, nil)}

      {:error, _} = err ->
        err
    end
  end

  defp fetch_and_persist_detail(code) do
    case SimpleSyllabusApi.fetch_syllabus_detail(code) do
      {:ok, doc} = result ->
        Task.start(fn -> SyllabusDB.upsert_detail(code, doc) end)
        result

      {:error, _} = err ->
        err
    end
  end
end
