-- work
-- A routine is work an employee runs on a schedule or when an event happens, for one of its
-- responsibilities or a project. An employee proposes it; the owner's decision on one revision
-- activates it, and any later revision is proposed again. A run is a turn of the employee, not
-- a work item. `trigger` is `{kind: "cron", expression, timezone, hours?}` or
-- `{kind: "event", source, type, filters}`. Only an active cron routine has a next run.
CREATE TABLE routines (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  employee_id text NOT NULL,
  project_id text,
  title text NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
  instruction text NOT NULL CHECK (length(instruction) BETWEEN 1 AND 4000),
  trigger jsonb NOT NULL CHECK (trigger ->> 'kind' IN ('cron', 'event')),
  notify text NOT NULL CHECK (notify IN ('always', 'when_found')),
  state text NOT NULL DEFAULT 'proposed' CHECK (state IN ('proposed', 'active', 'paused')),
  revision integer NOT NULL DEFAULT 1 CHECK (revision >= 1),
  next_run_at timestamptz,
  last_run_at timestamptz,
  last_result text CHECK (length(last_result) <= 500),
  -- When `when_found` runs found nothing and posted nothing, newest last; the briefing counts them.
  silent_runs timestamptz[] NOT NULL DEFAULT '{}',
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (business_id, id),
  CONSTRAINT routines_employee_fkey
    FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id),
  CONSTRAINT routines_project_fkey
    FOREIGN KEY (business_id, project_id) REFERENCES projects(business_id, id),
  CONSTRAINT routines_next_run_check
    CHECK (next_run_at IS NULL OR (state = 'active' AND trigger ->> 'kind' = 'cron'))
);
CREATE INDEX routines_business ON routines (business_id, updated_at DESC);
-- The dispatcher's minute tick: active scheduled routines by their next run.
CREATE INDEX routines_due ON routines (next_run_at) WHERE state = 'active';
-- Event routing: active event routines by source and type.
CREATE INDEX routines_events ON routines (business_id, (trigger ->> 'source'), (trigger ->> 'type'))
  WHERE state = 'active' AND trigger ->> 'kind' = 'event';

-- A follow-up: when waiting work looks again. A due date stays only a deadline.
ALTER TABLE work_items ADD COLUMN wake_at timestamptz;
ALTER TABLE work_items ADD CONSTRAINT work_items_wake_check
  CHECK (wake_at IS NULL OR state = 'waiting');
-- The dispatcher's minute tick: waiting work by when it wakes.
CREATE INDEX work_items_wake ON work_items (wake_at) WHERE state = 'waiting';
