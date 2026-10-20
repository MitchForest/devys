-- F1: what the business does, which template an employee was hired from, and room for
-- real responsibilities. F3: who answers in a space. F0: a label for each signed-in device.
ALTER TABLE businesses ADD COLUMN brief text NOT NULL DEFAULT '' CHECK (length(brief) <= 4000);

ALTER TABLE employees ADD COLUMN template text NOT NULL DEFAULT 'custom'
  CHECK (template IN ('operations', 'engineering', 'growth', 'business-operations', 'custom'));
UPDATE employees SET template = 'operations' WHERE name = 'Head of Operations';
ALTER TABLE employees DROP CONSTRAINT employees_role_check;
ALTER TABLE employees ADD CONSTRAINT employees_role_check CHECK (length(role) BETWEEN 1 AND 2000);

ALTER TABLE spaces ADD COLUMN lead_employee_id text;
ALTER TABLE spaces ADD CONSTRAINT spaces_lead_fkey
  FOREIGN KEY (business_id, lead_employee_id) REFERENCES employees(business_id, id);

ALTER TABLE web_sessions ADD COLUMN label text CHECK (length(label) <= 80);
