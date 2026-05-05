

CREATE TABLE IF NOT EXISTS users (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email       TEXT        NOT NULL UNIQUE,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Required elements define what content each syllabus must contain for reporting
CREATE TABLE IF NOT EXISTS required_elements (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  description TEXT        NOT NULL DEFAULT '',
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Default required elements per Snow College syllabus policy
INSERT INTO required_elements (name, description) VALUES
  ('Assignment Overview',              'A brief description of each major assignment, examination, etc.'),
  ('Course Information',               'Prefix, number, section number, and course title.'),
  ('Course Student Learning Outcomes', 'Student-facing language describing what they will learn. Should align with GE and program outcomes.'),
  ('Overview of Course Units',         'A general description of the subject matter of each unit of discussion or study.'),
  ('Prerequisites and Corequisites',   'Statement of pre- or corequisites, or a statement that there are none.'),
  ('Required Materials',               'Notification of required textbook(s) or a statement that there are none to buy.')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS required_element_report_instructions (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  required_element_id  UUID        NOT NULL REFERENCES required_elements(id) ON DELETE CASCADE,
  content              TEXT        NOT NULL,
  inserted_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One report per syllabus analysis run
CREATE TABLE IF NOT EXISTS generated_reports (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  syllabus_code   TEXT        NOT NULL,
  syllabus_title  TEXT        NOT NULL,
  instructor_name TEXT        NOT NULL,
  status          TEXT        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'completed', 'error')),
  inserted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row per required-element evaluation within a report
CREATE TABLE IF NOT EXISTS generated_report_items (
  id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  generated_report_id       UUID        NOT NULL REFERENCES generated_reports(id) ON DELETE CASCADE,
  required_element_id       UUID        NOT NULL REFERENCES required_elements(id) ON DELETE RESTRICT,
  status                    TEXT        NOT NULL CHECK (status IN ('met', 'not_met', 'partially_met')),
  description               TEXT        NOT NULL DEFAULT '',
  evidence                  TEXT        NOT NULL DEFAULT '',
  additional_considerations TEXT        NOT NULL DEFAULT '',
  inserted_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (generated_report_id, required_element_id)
);
