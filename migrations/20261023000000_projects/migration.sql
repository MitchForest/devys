-- work
-- U7: spaces become projects, bounded initiatives with an optional goal, deadline and budget,
-- a lead and assigned employees. A work item belongs to at most one project; a project still
-- references artifacts and files without copying them. Renamed, never aliased.
ALTER TABLE spaces RENAME TO projects;
ALTER TABLE projects RENAME COLUMN purpose TO goal;
ALTER TABLE projects RENAME CONSTRAINT spaces_pkey TO projects_pkey;
ALTER TABLE projects RENAME CONSTRAINT spaces_business_id_id_key TO projects_business_id_id_key;
ALTER TABLE projects RENAME CONSTRAINT spaces_name_check TO projects_name_check;
ALTER TABLE projects RENAME CONSTRAINT spaces_purpose_check TO projects_goal_check;
ALTER TABLE projects RENAME CONSTRAINT spaces_lead_fkey TO projects_lead_fkey;
ALTER TABLE projects ALTER COLUMN goal DROP NOT NULL;
ALTER TABLE projects ALTER COLUMN goal DROP DEFAULT;
UPDATE projects SET goal = NULL WHERE goal = '';
ALTER TABLE projects ADD COLUMN deadline date;
ALTER TABLE projects ADD COLUMN budget_cents bigint CHECK (budget_cents >= 0);
ALTER TABLE projects ADD COLUMN budget_currency text CHECK (budget_currency ~ '^[A-Z]{3}$');
ALTER TABLE projects ADD CONSTRAINT projects_budget_check
  CHECK ((budget_cents IS NULL) = (budget_currency IS NULL));

-- The employees assigned to a project. The lead answers in its channel whether or not listed.
CREATE TABLE project_members (
  business_id text NOT NULL,
  project_id text NOT NULL,
  employee_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, project_id, employee_id),
  FOREIGN KEY (business_id, project_id) REFERENCES projects(business_id, id) ON DELETE CASCADE,
  FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id)
);

ALTER TABLE space_items RENAME TO project_items;
ALTER TABLE project_items RENAME COLUMN space_id TO project_id;
ALTER TABLE project_items RENAME CONSTRAINT space_items_pkey TO project_items_pkey;
ALTER TABLE project_items RENAME CONSTRAINT space_items_space_id_kind_ref_key
  TO project_items_project_id_kind_ref_key;
ALTER TABLE project_items RENAME CONSTRAINT space_items_business_id_space_id_fkey
  TO project_items_business_id_project_id_fkey;
ALTER TABLE project_items RENAME CONSTRAINT space_items_ref_length TO project_items_ref_length;

-- A work item shown in projects moves into one: the oldest place it was shown.
ALTER TABLE commitments ADD COLUMN project_id text;
ALTER TABLE commitments ADD CONSTRAINT commitments_project_fkey
  FOREIGN KEY (business_id, project_id) REFERENCES projects(business_id, id);
UPDATE commitments c SET project_id = (
  SELECT i.project_id FROM project_items i
  WHERE i.business_id = c.business_id AND i.kind = 'commitment' AND i.ref = c.id
  ORDER BY i.created_at, i.id LIMIT 1);
CREATE INDEX commitments_by_project ON commitments (business_id, project_id)
  WHERE project_id IS NOT NULL;
DELETE FROM project_items WHERE kind = 'commitment';
ALTER TABLE project_items DROP CONSTRAINT space_items_kind_check;
ALTER TABLE project_items ADD CONSTRAINT project_items_kind_check CHECK (kind IN ('artifact', 'file'));

-- conversations
-- A space's conversation becomes its project's channel, with its messages, reads and follows.
ALTER TABLE conversations DROP CONSTRAINT conversations_key_check;
INSERT INTO conversations (business_id, key, created_at)
  SELECT business_id, 'project:' || substr(key, 7), created_at FROM conversations
  WHERE key LIKE 'space:%';
UPDATE messages SET conversation = 'project:' || substr(conversation, 7)
  WHERE conversation LIKE 'space:%';
UPDATE conversation_reads SET conversation = 'project:' || substr(conversation, 7)
  WHERE conversation LIKE 'space:%';
UPDATE follows SET conversation = 'project:' || substr(conversation, 7)
  WHERE conversation LIKE 'space:%';
DELETE FROM conversations WHERE key LIKE 'space:%';
ALTER TABLE conversations ADD CONSTRAINT conversations_key_check
  CHECK (key ~ '^(direct|project|work):[A-Za-z0-9-]{1,64}$');

-- authority
ALTER TABLE decisions DROP CONSTRAINT decisions_conversation_check;
UPDATE decisions SET conversation = 'project:' || substr(conversation, 7)
  WHERE conversation LIKE 'space:%';
ALTER TABLE decisions ADD CONSTRAINT decisions_conversation_check
  CHECK (conversation IS NULL OR conversation ~ '^(direct|project|work):[A-Za-z0-9-]{1,64}$');
