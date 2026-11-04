
-- Snow SE Tools Database Schema
-- This schema creates all tables from scratch for a fresh database

CREATE TABLE users (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email       TEXT        NOT NULL UNIQUE,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE groups (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL UNIQUE,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO groups (name)
VALUES ('admin')
ON CONFLICT (name) DO UPDATE
SET updated_at = NOW();

CREATE TABLE user_groups (
  user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  group_id    UUID        NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, group_id)
);

CREATE TABLE syllabus_required_elements (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  description TEXT        NOT NULL DEFAULT '',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO syllabus_required_elements (name, description) VALUES
  ('Assignment Overview',              'A brief description of each major assignment, examination, etc.'),
  ('Course Information',               'Prefix, number, section number, and course title.'),
  ('Course Student Learning Outcomes', 'Student-facing language describing what they will learn. Should align with GE and program outcomes.'),
  ('Overview of Course Units',         'A general description of the subject matter of each unit of discussion or study.'),
  ('Prerequisites and Corequisites',   'Statement of pre- or corequisites, or a statement that there are none.'),
  ('Required Materials',               'Notification of required textbook(s) or a statement that there are none to buy.')
ON CONFLICT DO NOTHING;

CREATE TABLE syllabus_required_element_report_instructions (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  required_element_id  UUID        NOT NULL REFERENCES syllabus_required_elements(id) ON DELETE CASCADE,
  content              TEXT        NOT NULL,
  inserted_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE syllabus_generated_reports (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  syllabus_code   TEXT        NOT NULL,
  syllabus_title  TEXT        NOT NULL,
  instructor_name TEXT        NOT NULL,
  status          TEXT        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'completed', 'error')),
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE syllabus_generated_report_items (
  id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  generated_report_id       UUID        NOT NULL REFERENCES syllabus_generated_reports(id) ON DELETE CASCADE,
  required_element_id       UUID        NOT NULL REFERENCES syllabus_required_elements(id) ON DELETE RESTRICT,
  status                    TEXT        NOT NULL CHECK (status IN ('met', 'not_met', 'partially_met')),
  description               TEXT        NOT NULL DEFAULT '',
  evidence                  TEXT        NOT NULL DEFAULT '',
  additional_considerations TEXT        NOT NULL DEFAULT '',
  inserted_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (generated_report_id, required_element_id)
);

CREATE TABLE syllabus_ai_completions (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  topic       TEXT        NOT NULL,
  event       TEXT        NOT NULL,
  model       TEXT        NOT NULL DEFAULT '',
  endpoint    TEXT        NOT NULL DEFAULT '',
  messages    JSONB       NOT NULL DEFAULT '[]',
  status      TEXT        NOT NULL CHECK (status IN ('ok', 'error')),
  result      TEXT        NOT NULL DEFAULT '',
  thinking    TEXT        NOT NULL DEFAULT '',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE syllabi (
  code              TEXT        PRIMARY KEY,
  title             TEXT,
  course_name       TEXT,
  term_name         TEXT,
  term_id           TEXT,
  org_id            TEXT,
  linked_emails     TEXT[]      NOT NULL DEFAULT '{}',
  editors           JSONB       NOT NULL DEFAULT '[]',
  list_data         JSONB       NOT NULL DEFAULT '{}',
  detail_data       JSONB,
  list_cached_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  detail_cached_at  TIMESTAMPTZ,
  sync_status       TEXT        NOT NULL DEFAULT 'pending'
                      CHECK (sync_status IN ('pending', 'synced', 'error')),
  sync_error        TEXT,
  synced_at         TIMESTAMPTZ,
  inserted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE syllabus_cached_organizations (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          TEXT        NOT NULL UNIQUE,
  parent_org_id   TEXT,
  name            TEXT        NOT NULL,
  level           INT         NOT NULL,
  metadata        JSONB       NOT NULL DEFAULT '{}',
  cached_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE syllabus_available_terms (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  term_id         TEXT        NOT NULL UNIQUE,
  term_name       TEXT        NOT NULL,
  status          TEXT        NOT NULL DEFAULT 'active',
  cached_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE snow_terms (
  term_code   TEXT        PRIMARY KEY,
  term_name   TEXT        NOT NULL,
  cached_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE snow_courses (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  term_code               TEXT        NOT NULL REFERENCES snow_terms(term_code) ON DELETE CASCADE,
  crn                     TEXT        NOT NULL,
  subject_code            TEXT        NOT NULL,
  course_number           TEXT        NOT NULL,
  section_number          TEXT        NOT NULL,
  course_name             TEXT        NOT NULL,
  primary_instructor_name  TEXT,
  data                    TEXT        NOT NULL,
  cached_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(term_code, crn)
);

CREATE INDEX snow_courses_term_code_idx ON snow_courses(term_code);

CREATE TABLE snow_section_students (
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
);

CREATE INDEX snow_section_students_term_crn_idx ON snow_section_students(term_code, crn);

CREATE TABLE discord_guilds (
  id         TEXT        PRIMARY KEY,
  name       TEXT,
  data       JSONB       NOT NULL,
  synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE discord_bot_users (
  id         TEXT        PRIMARY KEY,
  name       TEXT,
  data       JSONB       NOT NULL,
  synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE discord_members (
  id         TEXT        PRIMARY KEY,
  name       TEXT,
  data       JSONB       NOT NULL,
  synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX discord_members_name_idx ON discord_members(name);

CREATE TABLE discord_channels (
  id         TEXT        PRIMARY KEY,
  name       TEXT,
  data       JSONB       NOT NULL,
  synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX discord_channels_name_idx ON discord_channels(name);

CREATE TABLE discord_roles (
  id         TEXT        PRIMARY KEY,
  name       TEXT,
  data       JSONB       NOT NULL,
  synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX discord_roles_name_idx ON discord_roles(name);

CREATE TABLE discord_invites (
  id         TEXT        PRIMARY KEY,
  name       TEXT,
  data       JSONB       NOT NULL,
  synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE course_channel_assignments (
  crn                TEXT        PRIMARY KEY,
  term_code          TEXT        NOT NULL,
  discord_channel_id TEXT        NOT NULL,
  discord_role_id    TEXT        NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX course_channel_assignments_channel_idx
ON course_channel_assignments(discord_channel_id);

CREATE TABLE student_discord_mapping (
  badger_id        TEXT        PRIMARY KEY,
  discord_user_id   TEXT        NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX student_discord_mapping_discord_user_idx
ON student_discord_mapping(discord_user_id);

CREATE TABLE academic_programs (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL UNIQUE,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE academic_program_semesters (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  academic_program_id UUID        NOT NULL REFERENCES academic_programs(id) ON DELETE CASCADE,
  position            INTEGER     NOT NULL DEFAULT 0,
  inserted_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(academic_program_id, position)
);

CREATE INDEX academic_program_semesters_program_idx
ON academic_program_semesters(academic_program_id, position);

CREATE TABLE academic_program_semester_courses (
  id                           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  academic_program_semester_id UUID        NOT NULL REFERENCES academic_program_semesters(id) ON DELETE CASCADE,
  subject_code                 TEXT        NOT NULL,
  course_number                TEXT        NOT NULL,
  position                     INTEGER     NOT NULL DEFAULT 0,
  inserted_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(academic_program_semester_id, subject_code, course_number)
);

CREATE INDEX academic_program_semester_courses_semester_idx
ON academic_program_semester_courses(academic_program_semester_id, position);

CREATE TABLE schedule_change_groups (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE schedule_changes (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          UUID        NOT NULL REFERENCES schedule_change_groups(id) ON DELETE CASCADE,
  crn               TEXT        NOT NULL,
  term              TEXT        NOT NULL,
  course_name       TEXT,
  target_professor TEXT,
  meet_info         JSONB,
  operation         TEXT        NOT NULL DEFAULT 'update' CHECK (operation IN ('add', 'update')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  inserted_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_schedule_changes_group_id ON schedule_changes(group_id);
CREATE INDEX idx_schedule_changes_crn_term ON schedule_changes(crn, term);

CREATE TABLE schedule_layouts (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  scope       TEXT        NOT NULL DEFAULT 'user' CHECK (scope IN ('user', 'shared')),
  user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  term_code   TEXT,
  entries     JSONB       NOT NULL DEFAULT '[]'::jsonb,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_schedule_layouts_user_id ON schedule_layouts(user_id);
CREATE INDEX idx_schedule_layouts_scope ON schedule_layouts(scope);

-- Conflicts a person has looked at and decided are fine. Private to them, and
-- named by a fingerprint that covers the meeting times, so a class that moves
-- brings its conflict back.
CREATE TABLE acknowledged_conflicts (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  term_code   TEXT        NOT NULL,
  fingerprint TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, term_code, fingerprint)
);

CREATE INDEX idx_acknowledged_conflicts_user_term ON acknowledged_conflicts(user_id, term_code);

-- Curriculum map (SnowSeTools.Curriculum.CurriculumDb)

CREATE TABLE curriculum_skills (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  category    TEXT        NOT NULL DEFAULT 'concept'
                CHECK (category IN ('tool', 'practice', 'design', 'concept')),
  description TEXT        NOT NULL DEFAULT '',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX curriculum_skills_name_unique_idx
ON curriculum_skills (lower(name));

CREATE TABLE curriculum_skill_dependencies (
  skill_id           UUID        NOT NULL REFERENCES curriculum_skills(id) ON DELETE CASCADE,
  builds_on_skill_id UUID        NOT NULL REFERENCES curriculum_skills(id) ON DELETE CASCADE,
  inserted_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (skill_id, builds_on_skill_id),
  CHECK (skill_id <> builds_on_skill_id)
);

CREATE TABLE curriculum_course_skills (
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
);

CREATE TABLE curriculum_master_syllabi (
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
);

CREATE TABLE curriculum_course_outcomes (
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
);

CREATE TABLE curriculum_abet_outcomes (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT        NOT NULL UNIQUE,
  kind        TEXT        NOT NULL CHECK (kind IN ('slo', 'criterion')),
  number      INTEGER,
  title       TEXT        NOT NULL,
  position    INTEGER     NOT NULL DEFAULT 0,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE curriculum_course_abet (
  subject_code    TEXT    NOT NULL,
  course_number   TEXT    NOT NULL,
  abet_outcome_id UUID    NOT NULL REFERENCES curriculum_abet_outcomes(id) ON DELETE CASCADE,
  tentative       BOOLEAN NOT NULL DEFAULT FALSE,
  PRIMARY KEY (subject_code, course_number, abet_outcome_id)
);

CREATE TABLE curriculum_abet_imports (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  file_name      TEXT        NOT NULL,
  slo_sheet      TEXT        NOT NULL,
  criteria_sheet TEXT,
  imported_by    TEXT,
  imported_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE curriculum_runs (
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
);

CREATE TABLE curriculum_suggestions (
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
);

CREATE INDEX curriculum_suggestions_status_idx
ON curriculum_suggestions (status, subject_code, course_number);

-- Overrides for the AI endpoint, model and key set in the environment, so an
-- admin can point the app at a different server without a redeploy. At most
-- one row: id is fixed TRUE. A NULL column means "use the environment value".
CREATE TABLE ai_settings (
  id         BOOLEAN     PRIMARY KEY DEFAULT TRUE CHECK (id),
  endpoint   TEXT,
  model      TEXT,
  api_key    TEXT,
  updated_by TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
