defmodule SnowSeTools.Curriculum.CurriculumDb do
  @moduledoc """
  Tables behind the curriculum map: skills and how they build on each other,
  which courses introduce, reinforce or master each skill, the course outcomes
  mirrored from the approved master syllabi, ABET outcomes and the matrix that
  says which courses cover them, and the AI runs that propose changes.

  Courses are keyed by `subject_code` + `course_number`, the same pair the
  academic programs use, so a program plan and the map line up without a
  separate course table.
  """

  require Logger

  alias SnowSeTools.Data.DbHelpers

  @skill_categories ~w(tool practice design concept)
  @levels ~w(introduced reinforced mastered)

  def skill_categories, do: @skill_categories
  def levels, do: @levels

  def bootstrap_tables do
    (table_statements() ++ seed_statements())
    |> Enum.reduce_while(:ok, fn {step, sql}, :ok ->
      case DbHelpers.query(sql, %{}) do
        {:ok, _rows} ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.error("Curriculum bootstrap failed step=#{step} reason=#{inspect(reason)}")
          {:halt, {:error, reason}}
      end
    end)
  end

  defp table_statements do
    [
      {"create skills",
       """
       CREATE TABLE IF NOT EXISTS curriculum_skills (
         id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
         name        TEXT        NOT NULL,
         category    TEXT        NOT NULL DEFAULT 'concept'
                       CHECK (category IN ('tool', 'practice', 'design', 'concept')),
         description TEXT        NOT NULL DEFAULT '',
         inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
         updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
       )
       """},
      {"index skill names",
       """
       CREATE UNIQUE INDEX IF NOT EXISTS curriculum_skills_name_unique_idx
       ON curriculum_skills (lower(name))
       """},
      {"create skill dependencies",
       """
       CREATE TABLE IF NOT EXISTS curriculum_skill_dependencies (
         skill_id           UUID        NOT NULL REFERENCES curriculum_skills(id) ON DELETE CASCADE,
         builds_on_skill_id UUID        NOT NULL REFERENCES curriculum_skills(id) ON DELETE CASCADE,
         inserted_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
         PRIMARY KEY (skill_id, builds_on_skill_id),
         CHECK (skill_id <> builds_on_skill_id)
       )
       """},
      {"create course skills",
       """
       CREATE TABLE IF NOT EXISTS curriculum_course_skills (
         subject_code  TEXT        NOT NULL,
         course_number TEXT        NOT NULL,
         skill_id      UUID        NOT NULL REFERENCES curriculum_skills(id) ON DELETE CASCADE,
         level         TEXT        NOT NULL
                         CHECK (level IN ('introduced', 'reinforced', 'mastered')),
         note          TEXT        NOT NULL DEFAULT '',
         updated_by    TEXT,
         inserted_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
         updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
         PRIMARY KEY (subject_code, course_number, skill_id)
       )
       """},
      {"create master syllabi",
       """
       CREATE TABLE IF NOT EXISTS curriculum_master_syllabi (
         subject_code      TEXT        NOT NULL,
         course_number     TEXT        NOT NULL,
         title             TEXT        NOT NULL DEFAULT '',
         snow_syllabus_id  TEXT,
         url               TEXT,
         description       TEXT        NOT NULL DEFAULT '',
         prerequisites     TEXT        NOT NULL DEFAULT '',
         corequisites      TEXT        NOT NULL DEFAULT '',
         content           TEXT        NOT NULL DEFAULT '',
         semester_approved TEXT        NOT NULL DEFAULT '',
         five_year_review  TEXT        NOT NULL DEFAULT '',
         first_fetched_at  TIMESTAMPTZ,
         fetched_at        TIMESTAMPTZ,
         fetch_error       TEXT,
         PRIMARY KEY (subject_code, course_number)
       )
       """},
      {"create course outcomes",
       """
       CREATE TABLE IF NOT EXISTS curriculum_course_outcomes (
         id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
         subject_code    TEXT        NOT NULL,
         course_number   TEXT        NOT NULL,
         text            TEXT        NOT NULL,
         normalized_text TEXT        NOT NULL,
         position        INTEGER     NOT NULL DEFAULT 0,
         abet_slos       INTEGER[]   NOT NULL DEFAULT '{}',
         first_seen_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
         last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
         retired_at      TIMESTAMPTZ,
         UNIQUE (subject_code, course_number, normalized_text)
       )
       """},
      {"create abet outcomes",
       """
       CREATE TABLE IF NOT EXISTS curriculum_abet_outcomes (
         id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
         code        TEXT        NOT NULL UNIQUE,
         kind        TEXT        NOT NULL CHECK (kind IN ('slo', 'criterion')),
         number      INTEGER,
         title       TEXT        NOT NULL,
         position    INTEGER     NOT NULL DEFAULT 0,
         inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
         updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
       )
       """},
      {"create course abet coverage",
       """
       CREATE TABLE IF NOT EXISTS curriculum_course_abet (
         subject_code    TEXT    NOT NULL,
         course_number   TEXT    NOT NULL,
         abet_outcome_id UUID    NOT NULL REFERENCES curriculum_abet_outcomes(id) ON DELETE CASCADE,
         tentative       BOOLEAN NOT NULL DEFAULT FALSE,
         PRIMARY KEY (subject_code, course_number, abet_outcome_id)
       )
       """},
      {"create abet imports",
       """
       CREATE TABLE IF NOT EXISTS curriculum_abet_imports (
         id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
         file_name      TEXT        NOT NULL,
         slo_sheet      TEXT        NOT NULL,
         criteria_sheet TEXT,
         imported_by    TEXT,
         imported_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
       )
       """},
      {"create runs",
       """
       CREATE TABLE IF NOT EXISTS curriculum_runs (
         id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
         program_id       UUID,
         status           TEXT        NOT NULL DEFAULT 'running'
                            CHECK (status IN ('running', 'completed', 'error')),
         started_by       TEXT,
         total_courses    INTEGER     NOT NULL DEFAULT 0,
         finished_courses INTEGER     NOT NULL DEFAULT 0,
         notes            JSONB       NOT NULL DEFAULT '[]',
         error            TEXT,
         started_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
         finished_at      TIMESTAMPTZ
       )
       """},
      {"create suggestions",
       """
       CREATE TABLE IF NOT EXISTS curriculum_suggestions (
         id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
         run_id        UUID        NOT NULL REFERENCES curriculum_runs(id) ON DELETE CASCADE,
         kind          TEXT        NOT NULL
                         CHECK (kind IN ('course_skill', 'skill_dependency', 'merge_skills')),
         subject_code  TEXT,
         course_number TEXT,
         payload       JSONB       NOT NULL DEFAULT '{}',
         fingerprint   TEXT        NOT NULL DEFAULT '',
         rationale     TEXT        NOT NULL DEFAULT '',
         evidence      TEXT        NOT NULL DEFAULT '',
         status        TEXT        NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'accepted', 'rejected', 'superseded')),
         decided_by    TEXT,
         decided_at    TIMESTAMPTZ,
         inserted_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
       )
       """},
      {"index suggestions by status",
       """
       CREATE INDEX IF NOT EXISTS curriculum_suggestions_status_idx
       ON curriculum_suggestions (status, subject_code, course_number)
       """}
    ]
  end

  # The skills the department already knows it teaches, so the first page is a
  # map rather than an empty table. Only seeded into an empty catalog: once
  # anyone has curated it, a restart must not bring back what they deleted.
  defp seed_statements do
    [
      {"seed skills",
       """
       INSERT INTO curriculum_skills (name, category, description)
       SELECT seed.name, seed.category, seed.description
       FROM (VALUES
         ('Command line', 'tool', 'Navigating and working in a shell: files, processes, paths, environment.'),
         ('Git (command line)', 'tool', 'Commits, branches, merges and history from the git CLI.'),
         ('GitHub', 'tool', 'Remotes, pull requests, issues, reviews and Actions on GitHub.'),
         ('.NET SDK CLI', 'tool', 'Creating, building, testing and running projects with the dotnet command.'),
         ('VS Code', 'tool', 'Editing, debugging and extensions in Visual Studio Code.'),
         ('Visual Studio', 'tool', 'Solutions, the debugger and tooling in Visual Studio.'),
         ('Unit testing', 'practice', 'Writing automated tests for small units of code.'),
         ('Test-driven development (TDD)', 'practice', 'Red, green, refactor: letting tests drive the design.'),
         ('Behavior-driven development (BDD)', 'practice', 'Specifying behavior as examples in the language of the domain.'),
         ('Dependency injection', 'design', 'Supplying a class its collaborators instead of constructing them.'),
         ('Mocks & fakes', 'design', 'Test doubles that stand in for real collaborators.'),
         ('Domain-driven design (DDD)', 'design', 'Modeling software around the domain and its ubiquitous language.'),
         ('Onion architecture', 'design', 'Layering so the domain core depends on nothing outside it.')
       ) AS seed(name, category, description)
       WHERE NOT EXISTS (SELECT 1 FROM curriculum_skills)
       """},
      {"seed skill dependencies",
       """
       INSERT INTO curriculum_skill_dependencies (skill_id, builds_on_skill_id)
       SELECT skill.id, builds_on.id
       FROM (VALUES
         ('Git (command line)', 'Command line'),
         ('GitHub', 'Git (command line)'),
         ('.NET SDK CLI', 'Command line'),
         ('Test-driven development (TDD)', 'Unit testing'),
         ('Behavior-driven development (BDD)', 'Test-driven development (TDD)'),
         ('Mocks & fakes', 'Unit testing'),
         ('Mocks & fakes', 'Dependency injection'),
         ('Onion architecture', 'Dependency injection'),
         ('Onion architecture', 'Domain-driven design (DDD)')
       ) AS seed(skill_name, builds_on_name)
       JOIN curriculum_skills skill ON skill.name = seed.skill_name
       JOIN curriculum_skills builds_on ON builds_on.name = seed.builds_on_name
       WHERE NOT EXISTS (SELECT 1 FROM curriculum_skill_dependencies)
       ON CONFLICT DO NOTHING
       """},
      {"seed abet student outcomes",
       """
       INSERT INTO curriculum_abet_outcomes (code, kind, number, title, position)
       VALUES
         ('SLO 1', 'slo', 1, 'An ability to identify, formulate, and solve complex engineering problems by applying principles of engineering, science, and mathematics.', 1),
         ('SLO 2', 'slo', 2, 'An ability to apply engineering design to produce solutions that meet specified needs with consideration of public health, safety, and welfare, as well as global, cultural, social, environmental, and economic factors.', 2),
         ('SLO 3', 'slo', 3, 'An ability to communicate effectively with a range of audiences.', 3),
         ('SLO 4', 'slo', 4, 'An ability to recognize ethical and professional responsibilities in engineering situations and make informed judgments, which must consider the impact of engineering solutions in global, economic, environmental, and societal contexts.', 4),
         ('SLO 5', 'slo', 5, 'An ability to function effectively on a team whose members together provide leadership, create a collaborative and inclusive environment, establish goals, plan tasks, and meet objectives.', 5),
         ('SLO 6', 'slo', 6, 'An ability to develop and conduct appropriate experimentation, analyze and interpret data, and use engineering judgment to draw conclusions.', 6),
         ('SLO 7', 'slo', 7, 'An ability to acquire and apply new knowledge as needed, using appropriate learning strategies.', 7)
       ON CONFLICT (code) DO NOTHING
       """}
    ]
  end
end
