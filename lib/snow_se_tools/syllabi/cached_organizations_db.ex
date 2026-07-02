defmodule SnowSeTools.Syllabi.CachedOrganizationsDb do
  alias SnowSeTools.Data.DbHelpers

  def upsert_organizations(orgs) when is_list(orgs) do
    if Enum.empty?(orgs) do
      :ok
    else
      sql = """
      INSERT INTO syllabus_cached_organizations (org_id, parent_org_id, name, level, metadata, cached_at, updated_at)
      SELECT
        d.org_id,
        d.parent_org_id,
        d.name,
        d.level,
        d.metadata::jsonb,
        NOW(),
        NOW()
      FROM UNNEST(
        $(org_ids)::text[],
        $(parent_org_ids)::text[],
        $(names)::text[],
        $(levels)::int[],
        $(metadata_list)::text[]
      ) AS d(org_id, parent_org_id, name, level, metadata)
      ON CONFLICT (org_id) DO UPDATE SET
        parent_org_id = EXCLUDED.parent_org_id,
        name = EXCLUDED.name,
        level = EXCLUDED.level,
        metadata = EXCLUDED.metadata,
        cached_at = NOW(),
        updated_at = NOW()
      """

      params = %{
        "org_ids" => Enum.map(orgs, & &1["entity_id"]),
        "parent_org_ids" => Enum.map(orgs, & &1["parent_entity_id"]),
        "names" => Enum.map(orgs, & &1["name"]),
        "levels" => Enum.map(orgs, & &1["level"]),
        "metadata_list" =>
          Enum.map(orgs, fn org ->
            Jason.encode!(%{
              "is_self_active" => org["is_self_active"],
              "children_count" => Enum.count(org["children"] || [])
            })
          end)
      }

      case DbHelpers.run_sql(sql, params) do
        {:error, reason} -> {:error, reason}
        _rows -> :ok
      end
    end
  end

  def get_searchable_orgs do
    sql = """
    SELECT org_id, name, level
    FROM syllabus_cached_organizations
    WHERE level >= 2
    ORDER BY level, name
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err ->
        err

      rows ->
        orgs =
          Enum.map(rows, fn row ->
            %{
              "entity_id" => row["org_id"],
              "name" => row["name"],
              "level" => row["level"]
            }
          end)

        {:ok, orgs}
    end
  end

  def get_all_organizations do
    sql = """
    SELECT org_id, parent_org_id, name, level, metadata
    FROM syllabus_cached_organizations
    ORDER BY level, name
    """

    case DbHelpers.run_sql(sql, %{}) do
      {:error, _} = err ->
        err

      rows ->
        orgs =
          Enum.map(rows, fn row ->
            %{
              org_id: row["org_id"],
              parent_org_id: row["parent_org_id"],
              name: row["name"],
              level: row["level"],
              metadata: row["metadata"]
            }
          end)

        {:ok, orgs}
    end
  end

  def clear_cache do
    sql = "DELETE FROM syllabus_cached_organizations"
    DbHelpers.run_sql(sql, %{})
  end
end
