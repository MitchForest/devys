-- identity
-- The starting team (F1, 2026-10-23): the Chief of Staff replaces the Head of Operations, Admin
-- replaces Business Operations, and Finance joins.
ALTER TABLE employees DROP CONSTRAINT employees_template_check;
UPDATE employees SET template = 'chief-of-staff' WHERE template = 'operations';
UPDATE employees SET template = 'admin' WHERE template = 'business-operations';
ALTER TABLE employees ADD CONSTRAINT employees_template_check
  CHECK (template IN ('chief-of-staff', 'admin', 'finance', 'growth', 'engineering', 'custom'));
