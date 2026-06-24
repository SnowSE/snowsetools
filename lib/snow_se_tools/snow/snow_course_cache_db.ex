defmodule SnowSeTools.Snow.SnowCourseCacheDb do
  alias SnowSeTools.Data.DbHelpers

  @term_summary_schema Zoi.object(%{
                         "term_code" => Zoi.string(),
                         "term_name" => Zoi.string(),
                         "cached_at" => Zoi.string(),
                         "course_count" => Zoi.integer(),
                         "roster_count" => Zoi.integer()
                       })

  @course_schema Zoi.object(%{
                   "term_code" => Zoi.string(),
                   "crn" => Zoi.string(),
                   "subject_code" => Zoi.string(),
                   "course_number" => Zoi.string(),
                   "section_number" => Zoi.string(),
                   "course_name" => Zoi.string(),
                   "primary_instructor_name" => Zoi.optional(Zoi.string()),
                   "cached_at" => Zoi.string(),
                   "roster_count" => Zoi.integer()
                 })

  @course_catalog_schema Zoi.object(%{
                           "subject_code" => Zoi.string(),
                           "course_number" => Zoi.string(),
                           "name" => Zoi.string()
                         })

  def bootstrap_cache_tables do
    params = %{}

    statements = [
      """
      CREATE TABLE IF NOT EXISTS snow_terms (
        term_code   TEXT        PRIMARY KEY,
        term_name   TEXT        NOT NULL,
        cached_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS snow_courses (
        id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        term_code             TEXT        NOT NULL REFERENCES snow_terms(term_code) ON DELETE CASCADE,
        crn                   TEXT        NOT NULL,
        subject_code          TEXT        NOT NULL,
        course_number         TEXT        NOT NULL,
        section_number        TEXT        NOT NULL,
        course_name           TEXT        NOT NULL,
        primary_instructor_name TEXT,
        data                  TEXT        NOT NULL,
        cached_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE(term_code, crn)
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS snow_section_students (
        id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        term_code       TEXT        NOT NULL REFERENCES snow_terms(term_code) ON DELETE CASCADE,
        crn             TEXT        NOT NULL,
        badger_id       TEXT,
        first_name      TEXT,
        last_name       TEXT,
        email           TEXT,
        data            TEXT        NOT NULL,
        last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
      """,
      """
      CREATE INDEX IF NOT EXISTS snow_courses_term_code_idx ON snow_courses(term_code)
      """,
      """
      CREATE INDEX IF NOT EXISTS snow_section_students_term_crn_idx ON snow_section_students(term_code, crn)
      """
    ]

    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case DbHelpers.run_sql(sql, params) do
        {:error, reason} ->
          {:halt, {:error, reason}}

        _ ->
          {:cont, :ok}
      end
    end)
  end

  def upsert_term(term_code: term_code, term_name: term_name) do
    sql = """
    INSERT INTO snow_terms (term_code, term_name, cached_at, updated_at)
    VALUES ($(term_code), $(term_name), NOW(), NOW())
    ON CONFLICT (term_code) DO UPDATE SET
      term_name = EXCLUDED.term_name,
      cached_at = NOW(),
      updated_at = NOW()
    """

    DbHelpers.run_sql(sql, %{"term_code" => term_code, "term_name" => term_name})
  end

  def save_courses(term_code: term_code, term_name: term_name, courses: courses)
      when is_list(courses) do
    DbHelpers.transaction(fn ->
      case upsert_term(term_code: term_code, term_name: term_name) do
        {:error, reason} ->
          {:error, reason}

        _ ->
          delete_sql = "DELETE FROM snow_courses WHERE term_code = $(term_code)"

          case DbHelpers.run_sql(delete_sql, %{"term_code" => term_code}) do
            {:error, reason} ->
              {:error, reason}

            _ ->
              rows =
                Enum.map(courses, fn course ->
                  attrs = course_attributes(course)
                  Map.put(attrs, "term_code", term_code)
                end)

              insert_sql = """
              INSERT INTO snow_courses (
                term_code,
                crn,
                subject_code,
                course_number,
                section_number,
                course_name,
                primary_instructor_name,
                data,
                cached_at,
                updated_at
              )
              SELECT
                d.term_code,
                d.crn,
                d.subject_code,
                d.course_number,
                d.section_number,
                d.course_name,
                d.primary_instructor_name,
                d.data,
                NOW(),
                NOW()
              FROM UNNEST(
                $(term_codes)::text[],
                $(crns)::text[],
                $(subject_codes)::text[],
                $(course_numbers)::text[],
                $(section_numbers)::text[],
                $(course_names)::text[],
                $(primary_instructor_names)::text[],
                $(data_list)::text[]
              ) AS d(
                term_code,
                crn,
                subject_code,
                course_number,
                section_number,
                course_name,
                primary_instructor_name,
                data
              )
              ON CONFLICT (term_code, crn) DO UPDATE SET
                subject_code = EXCLUDED.subject_code,
                course_number = EXCLUDED.course_number,
                section_number = EXCLUDED.section_number,
                course_name = EXCLUDED.course_name,
                primary_instructor_name = EXCLUDED.primary_instructor_name,
                data = EXCLUDED.data,
                cached_at = NOW(),
                updated_at = NOW()
              """

              params = %{
                "term_codes" => Enum.map(rows, & &1["term_code"]),
                "crns" => Enum.map(rows, & &1["crn"]),
                "subject_codes" => Enum.map(rows, & &1["subject_code"]),
                "course_numbers" => Enum.map(rows, & &1["course_number"]),
                "section_numbers" => Enum.map(rows, & &1["section_number"]),
                "course_names" => Enum.map(rows, & &1["course_name"]),
                "primary_instructor_names" =>
                  Enum.map(rows, &Map.get(&1, "primary_instructor_name")),
                "data_list" => Enum.map(rows, & &1["data"])
              }

              case DbHelpers.run_sql(insert_sql, params) do
                {:error, reason} -> {:error, reason}
                _ -> :ok
              end
          end
      end
    end)
  end

  def save_section_students(term_code: term_code, crn: crn, students: students)
      when is_list(students) do
    DbHelpers.transaction(fn ->
      delete_sql =
        "DELETE FROM snow_section_students WHERE term_code = $(term_code) AND crn = $(crn)"

      case DbHelpers.run_sql(delete_sql, %{"term_code" => term_code, "crn" => crn}) do
        {:error, reason} ->
          {:error, reason}

        _ ->
          rows =
            Enum.map(students, fn student ->
              student_attributes(student)
              |> Map.put("term_code", term_code)
              |> Map.put("crn", crn)
            end)

          insert_sql = """
          INSERT INTO snow_section_students (
            term_code,
            crn,
            badger_id,
            first_name,
            last_name,
            email,
            data,
            last_synced_at,
            updated_at
          )
          SELECT
            d.term_code,
            d.crn,
            d.badger_id,
            d.first_name,
            d.last_name,
            d.email,
            d.data,
            NOW(),
            NOW()
          FROM UNNEST(
            $(term_codes)::text[],
            $(crns)::text[],
            $(badger_ids)::text[],
            $(first_names)::text[],
            $(last_names)::text[],
            $(emails)::text[],
            $(data_list)::text[]
          ) AS d(
            term_code,
            crn,
            badger_id,
            first_name,
            last_name,
            email,
            data
          )
          """

          params = %{
            "term_codes" => Enum.map(rows, & &1["term_code"]),
            "crns" => Enum.map(rows, & &1["crn"]),
            "badger_ids" => Enum.map(rows, & &1["badger_id"]),
            "first_names" => Enum.map(rows, & &1["first_name"]),
            "last_names" => Enum.map(rows, & &1["last_name"]),
            "emails" => Enum.map(rows, & &1["email"]),
            "data_list" => Enum.map(rows, & &1["data"])
          }

          case DbHelpers.run_sql(insert_sql, params) do
            {:error, reason} -> {:error, reason}
            _ -> :ok
          end
      end
    end)
  end

  def list_terms_with_courses do
    sql = """
    SELECT
      t.term_code,
      t.term_name,
      to_char(t.cached_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS cached_at,
      COUNT(DISTINCT c.crn)::integer AS course_count,
      COUNT(DISTINCT s.crn)::integer AS roster_count
    FROM snow_terms t
    LEFT JOIN snow_courses c ON c.term_code = t.term_code
    LEFT JOIN snow_section_students s ON s.term_code = t.term_code
    GROUP BY t.term_code, t.term_name, t.cached_at
    ORDER BY t.term_code DESC
    """

    DbHelpers.run_sql(sql, %{}, @term_summary_schema)
  end

  def list_courses_for_term(term_code: term_code) do
    sql = """
    SELECT
      c.term_code,
      c.crn,
      c.subject_code,
      c.course_number,
      c.section_number,
      c.course_name,
      c.primary_instructor_name,
      to_char(c.cached_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS cached_at,
      COUNT(s.id)::integer AS roster_count
    FROM snow_courses c
    LEFT JOIN snow_section_students s
      ON s.term_code = c.term_code
     AND s.crn = c.crn
    WHERE c.term_code = $(term_code)
    GROUP BY
      c.term_code,
      c.crn,
      c.subject_code,
      c.course_number,
      c.section_number,
      c.course_name,
      c.primary_instructor_name,
      c.cached_at
    ORDER BY c.subject_code, c.course_number, c.section_number, c.crn
    """

    DbHelpers.run_sql(sql, %{"term_code" => term_code}, @course_schema)
  end

  def list_course_data_for_term(term_code: term_code) do
    sql = """
    SELECT c.data::jsonb AS data
    FROM snow_courses c
    WHERE c.term_code = $(term_code)
    ORDER BY c.subject_code, c.course_number, c.section_number, c.crn
    """

    case DbHelpers.run_sql(sql, %{"term_code" => term_code}) do
      {:error, _} = err -> err
      rows -> {:ok, Enum.map(rows, & &1["data"])}
    end
  end

  def list_course_catalog do
    sql = """
    SELECT DISTINCT ON (subject_code, course_number)
      subject_code,
      course_number,
      course_name AS name
    FROM snow_courses
    WHERE subject_code IS NOT NULL
      AND subject_code != ''
      AND course_number IS NOT NULL
      AND course_number != ''
    ORDER BY subject_code, course_number, course_name, cached_at DESC
    """

    DbHelpers.run_sql(sql, %{}, @course_catalog_schema)
  end

  def get_section_students(term_code: term_code, crn: crn) do
    sql = """
    SELECT data
    FROM snow_section_students
    WHERE term_code = $(term_code)
      AND crn = $(crn)
    ORDER BY last_synced_at DESC
    """

    case DbHelpers.run_sql(sql, %{"term_code" => term_code, "crn" => crn}) do
      {:error, _} = err -> err
      rows -> {:ok, Enum.map(rows, & &1["data"])}
    end
  end

  defp course_attributes(course) when is_map(course) do
    instructors = course["instructors"] || []

    primary_instructor =
      Enum.find(instructors, &(&1["primary_instructor"] == true)) || List.first(instructors)

    %{
      "crn" => course["crn"] || "",
      "subject_code" => course["subject_code"] || "",
      "course_number" => course["course_number"] || "",
      "section_number" => course["section_number"] || "",
      "course_name" => course["name"] || course["title"] || "",
      "primary_instructor_name" => instructor_name(primary_instructor),
      "data" => Jason.encode!(course)
    }
  end

  defp student_attributes(student) when is_map(student) do
    %{
      "badger_id" => student["badgerid"],
      "first_name" => student["first_name"],
      "last_name" => student["last_name"],
      "email" => student["email"],
      "data" => Jason.encode!(student)
    }
  end

  defp instructor_name(nil), do: nil
  defp instructor_name(%{"name" => name}) when is_binary(name), do: name
  defp instructor_name(_), do: nil

  def delete_term(term_code: term_code) do
    sql = "DELETE FROM snow_terms WHERE term_code = $(term_code)"

    DbHelpers.run_sql(sql, %{"term_code" => term_code})
  end
end
