defmodule SnowSeTools.Curriculum.OutcomeDb do
  @moduledoc """
  The master syllabi as last read from snow.edu, and the course outcomes they
  list.

  Outcomes mirror the approved syllabus rather than being edited here: a read
  adds the outcomes that are new, keeps the ones still listed, and marks the
  ones that disappeared as retired instead of deleting them, so the page can
  say what changed and when.
  """

  alias SnowSeTools.Curriculum.MasterSyllabus
  alias SnowSeTools.Data.DbHelpers

  @syllabus_columns """
  subject_code, course_number, title, snow_syllabus_id, url, description, prerequisites,
  corequisites, content, semester_approved, five_year_review, fetch_error,
  to_char(first_fetched_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS first_fetched_at,
  to_char(fetched_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS fetched_at
  """

  def list_master_syllabi do
    DbHelpers.query("SELECT #{@syllabus_columns} FROM curriculum_master_syllabi", %{})
  end

  def list_outcomes do
    sql = """
    SELECT
      o.id, o.subject_code, o.course_number, o.text, o.position, o.abet_slos,
      to_char(o.first_seen_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS first_seen_at,
      to_char(o.retired_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS retired_at,
      (m.first_fetched_at IS NOT NULL AND o.first_seen_at > m.first_fetched_at) AS added_since_first_read
    FROM curriculum_course_outcomes o
    LEFT JOIN curriculum_master_syllabi m
      ON m.subject_code = o.subject_code AND m.course_number = o.course_number
    ORDER BY o.subject_code, o.course_number, o.retired_at NULLS FIRST, o.position
    """

    DbHelpers.query(sql, %{})
  end

  @doc """
  Stores a freshly read syllabus and brings the course's outcomes in line with
  it. Answers how many outcomes were added and retired by this read.
  """
  def save_master_syllabus(
        subject_code: subject_code,
        course_number: course_number,
        syllabus: syllabus
      ) do
    course = %{"subject_code" => subject_code, "course_number" => course_number}

    DbHelpers.transaction(fn ->
      with {:ok, _rows} <- upsert_syllabus(course, syllabus),
           {:ok, added} <- upsert_outcomes(course, syllabus["outcomes"] || []),
           {:ok, retired} <- retire_missing(course, syllabus["outcomes"] || []) do
        {:ok, %{added: added, retired: retired}}
      end
    end)
  end

  @doc "Remembers that the last read failed, keeping what an earlier read stored."
  def record_fetch_error(subject_code: subject_code, course_number: course_number, error: error) do
    sql = """
    INSERT INTO curriculum_master_syllabi (subject_code, course_number, fetch_error)
    VALUES ($(subject_code), $(course_number), $(error))
    ON CONFLICT (subject_code, course_number) DO UPDATE SET fetch_error = EXCLUDED.fetch_error
    """

    params = %{"subject_code" => subject_code, "course_number" => course_number, "error" => error}

    case DbHelpers.query(sql, params) do
      {:ok, _rows} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_syllabus(course, syllabus) do
    sql = """
    INSERT INTO curriculum_master_syllabi (
      subject_code, course_number, title, snow_syllabus_id, url, description, prerequisites,
      corequisites, content, semester_approved, five_year_review,
      first_fetched_at, fetched_at, fetch_error
    )
    VALUES (
      $(subject_code), $(course_number), $(title), $(snow_syllabus_id), $(url), $(description),
      $(prerequisites), $(corequisites), $(content), $(semester_approved), $(five_year_review),
      NOW(), NOW(), NULL
    )
    ON CONFLICT (subject_code, course_number) DO UPDATE SET
      title = EXCLUDED.title,
      snow_syllabus_id = EXCLUDED.snow_syllabus_id,
      url = EXCLUDED.url,
      description = EXCLUDED.description,
      prerequisites = EXCLUDED.prerequisites,
      corequisites = EXCLUDED.corequisites,
      content = EXCLUDED.content,
      semester_approved = EXCLUDED.semester_approved,
      five_year_review = EXCLUDED.five_year_review,
      first_fetched_at = COALESCE(curriculum_master_syllabi.first_fetched_at, NOW()),
      fetched_at = NOW(),
      fetch_error = NULL
    """

    params =
      Map.merge(course, %{
        "title" => syllabus["title"] || "",
        "snow_syllabus_id" => syllabus["snow_syllabus_id"],
        "url" => syllabus["url"],
        "description" => syllabus["description"] || "",
        "prerequisites" => syllabus["prerequisites"] || "",
        "corequisites" => syllabus["corequisites"] || "",
        "content" => syllabus["content"] || "",
        "semester_approved" => syllabus["semester_approved"] || "",
        "five_year_review" => syllabus["five_year_review"] || ""
      })

    DbHelpers.query(sql, params)
  end

  # `xmax = 0` is true only for a row this statement inserted, which is how an
  # upsert tells a new outcome from one it merely saw again.
  defp upsert_outcomes(course, outcomes) do
    sql = """
    INSERT INTO curriculum_course_outcomes
      (subject_code, course_number, text, normalized_text, position, abet_slos)
    VALUES ($(subject_code), $(course_number), $(text), $(normalized_text), $(position), $(abet_slos))
    ON CONFLICT (subject_code, course_number, normalized_text) DO UPDATE SET
      text = EXCLUDED.text,
      position = EXCLUDED.position,
      abet_slos = EXCLUDED.abet_slos,
      last_seen_at = NOW(),
      retired_at = NULL
    RETURNING (xmax = 0) AS inserted
    """

    outcomes
    |> Enum.uniq_by(&MasterSyllabus.normalize_outcome/1)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, 0}, fn {text, position}, {:ok, added} ->
      params =
        Map.merge(course, %{
          "text" => text,
          "normalized_text" => MasterSyllabus.normalize_outcome(text),
          "position" => position,
          "abet_slos" => MasterSyllabus.abet_slos(text)
        })

      case DbHelpers.query(sql, params) do
        {:ok, [%{"inserted" => true}]} -> {:cont, {:ok, added + 1}}
        {:ok, _seen_again} -> {:cont, {:ok, added}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp retire_missing(course, outcomes) do
    sql = """
    UPDATE curriculum_course_outcomes
    SET retired_at = NOW()
    WHERE subject_code = $(subject_code)
      AND course_number = $(course_number)
      AND retired_at IS NULL
      AND NOT (normalized_text = ANY($(seen)::text[]))
    RETURNING id
    """

    params = Map.put(course, "seen", Enum.map(outcomes, &MasterSyllabus.normalize_outcome/1))

    case DbHelpers.query(sql, params) do
      {:ok, rows} -> {:ok, length(rows)}
      {:error, reason} -> {:error, reason}
    end
  end
end
