
-- Simple Syllabus Reporter Database Schema
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
