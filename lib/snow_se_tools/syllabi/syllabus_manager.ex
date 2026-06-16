defmodule SnowSeTools.Syllabi.SyllabusDomainManager do
  require Logger

  alias SnowSeTools.Syllabi.{SyllabusDB, CachedOrganizationsDb}

  def search_by_org(org_id) do
    case SyllabusDB.list_by_org(org_id) do
      {:ok, [_ | _] = docs, cached_at} ->
        {:ok, %{items: docs, cached_at: cached_at}}

      {:ok, [], _} ->
        {:ok, %{items: [], cached_at: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def search_by_email(email) do
    case SyllabusDB.list_by_editor_email(email) do
      {:ok, [_ | _] = docs, cached_at} ->
        {:ok, %{items: docs, cached_at: cached_at}}

      {:ok, [], _} ->
        {:ok, %{items: [], cached_at: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_detail(code) do
    case SyllabusDB.get_detail(code) do
      {:ok, doc, _cached_at} when not is_nil(doc) ->
        {:ok, doc}

      {:ok, nil, _} ->
        {:error, "Detail not yet synced"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_departments do
    case CachedOrganizationsDb.get_searchable_orgs() do
      {:ok, [_ | _] = orgs} ->
        {:ok, Enum.sort_by(orgs, & &1["name"])}

      {:ok, []} ->
        {:error, "Organizations not yet synced. Please run a sync from settings."}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
