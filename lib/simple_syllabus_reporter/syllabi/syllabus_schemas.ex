defmodule SimpleSyllabusReporter.SyllabusSchemas do
  @moduledoc """
  Zoi schemas for normalizing SimpleSyllabus API responses.

  Both schemas use string keys (matching what the API returns and what templates
  access via bracket notation). Unknown fields are silently stripped.

  On a parse error the raw data is returned with a warning log so that unexpected
  API changes degrade gracefully rather than crash.
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Sub-schemas
  # ---------------------------------------------------------------------------

  # Editors that appear inside list-search results
  @list_editor Zoi.map(%{
                 "entity_id" => Zoi.optional(Zoi.string()),
                 "full_name" => Zoi.optional(Zoi.string()),
                 "first_name" => Zoi.optional(Zoi.string()),
                 "last_name" => Zoi.optional(Zoi.string()),
                 "has_headshot" => Zoi.optional(Zoi.boolean())
               })

  # Term object inside detail doc_data
  @term Zoi.map(%{
          "id" => Zoi.optional(Zoi.string()),
          "name" => Zoi.optional(Zoi.string()),
          "start_date" => Zoi.optional(Zoi.string()),
          "end_date" => Zoi.optional(Zoi.string())
        })

  # Course properties object inside detail doc_data
  @properties Zoi.map(%{
                "subject_name" => Zoi.optional(Zoi.string()),
                "course_number" => Zoi.optional(Zoi.string()),
                "full_name" => Zoi.optional(Zoi.string()),
                "name" => Zoi.optional(Zoi.string()),
                "title" => Zoi.optional(Zoi.string()),
                "term_id" => Zoi.optional(Zoi.string())
              })

  # Account inside an editor/active_user entry
  @account Zoi.map(%{
             "email" => Zoi.optional(Zoi.string()),
             "entity_id" => Zoi.optional(Zoi.string()),
             "entity_type" => Zoi.optional(Zoi.string())
           })

  # Role inside an editor/active_user entry
  @role Zoi.map(%{
          "name" => Zoi.optional(Zoi.string()),
          "role_types" => Zoi.default(Zoi.optional(Zoi.array(Zoi.string())), [])
        })

  # Full editor object (detail + active_users)
  @detail_editor Zoi.map(%{
                   "entity_id" => Zoi.optional(Zoi.string()),
                   "full_name" => Zoi.optional(Zoi.string()),
                   "first_name" => Zoi.optional(Zoi.string()),
                   "last_name" => Zoi.optional(Zoi.string()),
                   "accounts" => Zoi.default(Zoi.optional(Zoi.array(@account)), []),
                   "role" => Zoi.optional(@role)
                 })

  # Syllabus content component
  @component Zoi.map(%{
               "html" => Zoi.default(Zoi.optional(Zoi.string()), ""),
               "sort_order" => Zoi.optional(Zoi.number()),
               "name" => Zoi.optional(Zoi.string())
             })

  # ---------------------------------------------------------------------------
  # Top-level schemas
  # ---------------------------------------------------------------------------

  # Single item returned by doc-library-search
  @list_item Zoi.map(%{
               "code" => Zoi.string(),
               "title" => Zoi.optional(Zoi.string()),
               "course_name" => Zoi.optional(Zoi.string()),
               "subtitle" => Zoi.optional(Zoi.string()),
               "term_name" => Zoi.optional(Zoi.string()),
               "term_id" => Zoi.optional(Zoi.string()),
               "term" => Zoi.optional(Zoi.string()),
               "editors" => Zoi.default(Zoi.optional(Zoi.array(@list_editor)), []),
               "entity_id" => Zoi.optional(Zoi.string()),
               "entity_type" => Zoi.optional(Zoi.string()),
               "family_name" => Zoi.optional(Zoi.string()),
               "following" => Zoi.optional(Zoi.boolean()),
               "is_student" => Zoi.optional(Zoi.boolean()),
               "visibility" => Zoi.optional(Zoi.string())
             })

  @list_schema Zoi.array(@list_item)

  # doc_data returned by doc-full-page-get (after HTML sanitization)
  @detail_schema Zoi.map(%{
                   "code" => Zoi.string(),
                   "title" => Zoi.optional(Zoi.string()),
                   "sub_title" => Zoi.optional(Zoi.string()),
                   "term" => Zoi.optional(@term),
                   "properties" => Zoi.optional(@properties),
                   "editors" => Zoi.default(Zoi.optional(Zoi.array(@detail_editor)), []),
                   "active_users" => Zoi.default(Zoi.optional(Zoi.array(@detail_editor)), []),
                   "components" => Zoi.default(Zoi.optional(Zoi.array(@component)), []),
                   "status" => Zoi.optional(Zoi.string()),
                   "visibility" => Zoi.optional(Zoi.string()),
                   "is_published" => Zoi.optional(Zoi.boolean()),
                   "is_missing_required_content" => Zoi.optional(Zoi.boolean()),
                   "entity_id" => Zoi.optional(Zoi.string()),
                   "family_name" => Zoi.optional(Zoi.string())
                 })

  # ---------------------------------------------------------------------------
  # Public parse functions
  # ---------------------------------------------------------------------------

  @doc """
  Parses and normalises a list of syllabus search results.
  Returns `{:ok, list}` always — falls back to raw items if validation fails.
  """
  def parse_list(items) when is_list(items) do
    case Zoi.parse(@list_schema, items) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, errors} ->
        Logger.warning(
          "SyllabusSchemas.parse_list validation errors: #{inspect(Zoi.treefy_errors(errors))}"
        )

        {:ok, items}
    end
  end

  def parse_list(other) do
    Logger.warning("SyllabusSchemas.parse_list expected list, got: #{inspect(other)}")
    {:ok, []}
  end

  @doc """
  Parses and normalises a single syllabus detail (doc_data).
  Returns `{:ok, doc}` always — falls back to raw doc if validation fails.
  """
  def parse_detail(doc_data) when is_map(doc_data) do
    case Zoi.parse(@detail_schema, doc_data) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, errors} ->
        Logger.warning(
          "SyllabusSchemas.parse_detail validation errors: #{inspect(Zoi.treefy_errors(errors))}"
        )

        {:ok, doc_data}
    end
  end

  def parse_detail(other) do
    Logger.warning("SyllabusSchemas.parse_detail expected map, got: #{inspect(other)}")
    {:error, "Unexpected detail format"}
  end
end
