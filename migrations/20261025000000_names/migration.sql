-- work
-- AL2: one name per concept. A commitment is a work item, in the schema as in the product.
ALTER TABLE commitments RENAME TO work_items;
ALTER TABLE work_items RENAME CONSTRAINT commitments_pkey TO work_items_pkey;
ALTER TABLE work_items RENAME CONSTRAINT commitments_project_fkey TO work_items_project_fkey;
ALTER TABLE work_items RENAME CONSTRAINT commitments_state_check TO work_items_state_check;
ALTER TABLE work_items RENAME CONSTRAINT commitments_title_check TO work_items_title_check;
ALTER TABLE work_items RENAME CONSTRAINT commitments_objective_check TO work_items_objective_check;
ALTER TABLE work_items RENAME CONSTRAINT commitments_next_action_check
  TO work_items_next_action_check;
ALTER TABLE work_items RENAME CONSTRAINT commitments_wait_condition_check
  TO work_items_wait_condition_check;
ALTER INDEX commitments_business RENAME TO work_items_business;
ALTER INDEX commitments_due RENAME TO work_items_due;
ALTER INDEX commitments_by_project RENAME TO work_items_by_project;
ALTER TABLE work_items ADD CONSTRAINT work_items_business_id_id_key UNIQUE (business_id, id);
-- Every record names an employee of its own business.
ALTER TABLE work_items ADD CONSTRAINT work_items_owner_fkey
  FOREIGN KEY (business_id, owner_employee_id) REFERENCES employees(business_id, id);

-- code
-- An assignment is a coding session (its Ref kind, devys:code/session/<id>).
ALTER TABLE assignments RENAME TO coding_sessions;
ALTER TABLE coding_sessions RENAME COLUMN commitment_id TO work_item_id;
-- The provider's own session (Codex thread, Claude Code session) is named as such.
ALTER TABLE coding_sessions RENAME COLUMN session_id TO provider_session_id;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_pkey TO coding_sessions_pkey;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_id_check TO coding_sessions_id_check;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_provider_check
  TO coding_sessions_provider_check;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_purpose_check
  TO coding_sessions_purpose_check;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_objective_check
  TO coding_sessions_objective_check;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_repository_check
  TO coding_sessions_repository_check;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_base_commit_check
  TO coding_sessions_base_commit_check;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_branch_check
  TO coding_sessions_branch_check;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_worktree_check
  TO coding_sessions_worktree_check;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_session_id_check
  TO coding_sessions_provider_session_id_check;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_reviews_fkey TO coding_sessions_reviews_fkey;
ALTER TABLE coding_sessions RENAME CONSTRAINT assignments_business_id_fkey
  TO coding_sessions_business_id_fkey;
ALTER INDEX assignments_by_commitment RENAME TO coding_sessions_by_work_item;
ALTER TABLE coding_sessions DROP CONSTRAINT assignments_commitment_id_fkey;
ALTER TABLE coding_sessions DROP CONSTRAINT assignments_employee_id_fkey;
ALTER TABLE coding_sessions ADD CONSTRAINT coding_sessions_work_item_fkey
  FOREIGN KEY (business_id, work_item_id) REFERENCES work_items(business_id, id);
ALTER TABLE coding_sessions ADD CONSTRAINT coding_sessions_employee_fkey
  FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id);

-- authority
ALTER TABLE decisions RENAME COLUMN commitment_id TO work_item_id;
ALTER TABLE decisions ADD CONSTRAINT decisions_work_item_fkey
  FOREIGN KEY (business_id, work_item_id) REFERENCES work_items(business_id, id);
ALTER TABLE decisions ADD CONSTRAINT decisions_employee_fkey
  FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id);
ALTER TABLE grants ADD CONSTRAINT grants_employee_fkey
  FOREIGN KEY (business_id, employee_id) REFERENCES employees(business_id, id);
-- The work capabilities take the product's words. Each active grant is revoked and reissued,
-- so a grant stays immutable and decisions keep binding the revision they named.
CREATE TEMP TABLE renamed (old text PRIMARY KEY, new text NOT NULL) ON COMMIT DROP;
INSERT INTO renamed VALUES
  ('commitmentList', 'workList'),
  ('commitmentCreate', 'workCreate'),
  ('commitmentUpdate', 'workUpdate'),
  ('commitmentComplete', 'workComplete');
INSERT INTO grants (id, business_id, employee_id, capability, mode, constraints, responsibility)
  SELECT gen_random_uuid()::text, g.business_id, g.employee_id, r.new, g.mode, g.constraints,
    g.responsibility
  FROM grants g JOIN renamed r ON r.old = g.capability WHERE g.revoked_at IS NULL;
UPDATE grants SET revoked_at = now()
  WHERE capability IN (SELECT old FROM renamed) AND revoked_at IS NULL;
-- A request's hash names the work item under its old field name, so no open request can be
-- matched again: each is closed and the employee asks anew.
UPDATE decisions SET status = 'rejected', decided_at = now()
  WHERE status IN ('pending', 'approved');
