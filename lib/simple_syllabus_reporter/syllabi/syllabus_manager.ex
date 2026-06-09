defmodule SimpleSyllabusReporter.Syllabi.SyllabusDomainManager do
  @moduledoc """
  Orchestration layer for syllabus data. All queries read exclusively from
  the local database cache. No API calls during searches - syncing happens
  only from the settings page.
  """
  require Logger

  alias SimpleSyllabusReporter.Syllabi.{SyllabusDB, CachedOrganizationsDb}

  @doc """
  Returns syllabi for an org from the database cache.

  Returns `{:ok, %{items: docs, cached_at: datetime_or_nil}}` or `{:error, term}`.
  """
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

  @doc """
  Returns syllabi for an editor email from the database cache.

  Returns `{:ok, %{items: docs, cached_at: datetime_or_nil}}` or `{:error, term}`.
  """
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

  @doc """
  Returns full detail for a syllabus code from the database cache.

  Returns `{:ok, doc}` or `{:error, term}`.
  """
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

  @doc "Returns all level-2 schools from the cached organizations."
  def get_departments do
    case CachedOrganizationsDb.get_searchable_orgs() do
      {:ok, [_ | _] = orgs} ->
        # Return organizations sorted by name
        {:ok, Enum.sort_by(orgs, & &1.name)}

      {:ok, []} ->
        # No organizations cached yet - user needs to sync first
        {:error, "Organizations not yet synced. Please run a sync from settings."}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
