defmodule SimpleSyllabusReporter.SyllabusSchemas do
  require Logger

  @syllabus_list_editor Zoi.map(%{
                          "entity_id" => Zoi.optional(Zoi.string()),
                          "full_name" => Zoi.optional(Zoi.string()),
                          "first_name" => Zoi.optional(Zoi.string()),
                          "last_name" => Zoi.optional(Zoi.string()),
                          "has_headshot" => Zoi.optional(Zoi.boolean())
                        })

  @term_metadata Zoi.map(%{
                   "id" => Zoi.optional(Zoi.string()),
                   "name" => Zoi.optional(Zoi.string()),
                   "start_date" => Zoi.optional(Zoi.string()),
                   "end_date" => Zoi.optional(Zoi.string())
                 })

  @course_properties Zoi.map(%{
                       "subject_name" => Zoi.optional(Zoi.string()),
                       "course_number" => Zoi.optional(Zoi.string()),
                       "full_name" => Zoi.optional(Zoi.string()),
                       "name" => Zoi.optional(Zoi.string()),
                       "title" => Zoi.optional(Zoi.string()),
                       "term_id" => Zoi.optional(Zoi.string())
                     })

  @editor_account Zoi.map(%{
                    "email" => Zoi.optional(Zoi.string()),
                    "entity_id" => Zoi.optional(Zoi.string()),
                    "entity_type" => Zoi.optional(Zoi.string())
                  })

  @editor_role Zoi.map(%{
                 "name" => Zoi.optional(Zoi.string()),
                 "role_types" => Zoi.default(Zoi.optional(Zoi.array(Zoi.string())), [])
               })

  @syllabus_detail_editor Zoi.map(%{
                            "entity_id" => Zoi.optional(Zoi.string()),
                            "full_name" => Zoi.optional(Zoi.string()),
                            "first_name" => Zoi.optional(Zoi.string()),
                            "last_name" => Zoi.optional(Zoi.string()),
                            "accounts" =>
                              Zoi.default(Zoi.optional(Zoi.array(@editor_account)), []),
                            "role" => Zoi.optional(@editor_role)
                          })

  @syllabus_component Zoi.map(%{
                        "html" => Zoi.default(Zoi.optional(Zoi.string()), ""),
                        "sort_order" => Zoi.optional(Zoi.number()),
                        "name" => Zoi.optional(Zoi.string())
                      })

  @syllabus_metadata_list_item Zoi.map(%{
                                 "code" => Zoi.string(),
                                 "title" => Zoi.optional(Zoi.string()),
                                 "course_name" => Zoi.optional(Zoi.string()),
                                 "subtitle" => Zoi.optional(Zoi.string()),
                                 "term_name" => Zoi.optional(Zoi.string()),
                                 "term_id" => Zoi.optional(Zoi.string()),
                                 "term" => Zoi.optional(Zoi.string()),
                                 "editors" =>
                                   Zoi.default(Zoi.optional(Zoi.array(@syllabus_list_editor)), []),
                                 "entity_id" => Zoi.optional(Zoi.string()),
                                 "entity_type" => Zoi.optional(Zoi.string()),
                                 "family_name" => Zoi.optional(Zoi.string()),
                                 "following" => Zoi.optional(Zoi.boolean()),
                                 "is_student" => Zoi.optional(Zoi.boolean()),
                                 "visibility" => Zoi.optional(Zoi.string())
                               })

  @syllabus_metadata_list Zoi.array(@syllabus_metadata_list_item)

  @syllabus_detail Zoi.map(%{
                     "code" => Zoi.string(),
                     "title" => Zoi.optional(Zoi.string()),
                     "sub_title" => Zoi.optional(Zoi.string()),
                     "term" => Zoi.optional(@term_metadata),
                     "properties" => Zoi.optional(@course_properties),
                     "editors" =>
                       Zoi.default(Zoi.optional(Zoi.array(@syllabus_detail_editor)), []),
                     "active_users" =>
                       Zoi.default(Zoi.optional(Zoi.array(@syllabus_detail_editor)), []),
                     "components" =>
                       Zoi.default(Zoi.optional(Zoi.array(@syllabus_component)), []),
                     "status" => Zoi.optional(Zoi.string()),
                     "visibility" => Zoi.optional(Zoi.string()),
                     "is_published" => Zoi.optional(Zoi.boolean()),
                     "is_missing_required_content" => Zoi.optional(Zoi.boolean()),
                     "entity_id" => Zoi.optional(Zoi.string()),
                     "family_name" => Zoi.optional(Zoi.string())
                   })

  def parse_syllabi_metadata_list(items) when is_list(items) do
    case Zoi.parse(@syllabus_metadata_list, items) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, errors} ->
        Logger.warning(
          "parse_syllabi_metadata_list validation errors: #{inspect(Zoi.treefy_errors(errors))}"
        )

        {:ok, items}
    end
  end

  def parse_syllabi_metadata_list(other) do
    Logger.warning("parse_syllabi_metadata_list expected list, got: #{inspect(other)}")
    {:ok, []}
  end

  def parse_syllabus_detail(doc_data) when is_map(doc_data) do
    case Zoi.parse(@syllabus_detail, doc_data) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, errors} ->
        Logger.warning(
          "parse_syllabus_detail validation errors: #{inspect(Zoi.treefy_errors(errors))}"
        )

        {:ok, doc_data}
    end
  end

  def parse_syllabus_detail(other) do
    Logger.warning("parse_syllabus_detail expected map, got: #{inspect(other)}")
    {:error, "Unexpected detail format"}
  end
end
