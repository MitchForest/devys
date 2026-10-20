-- Each employee runs on a model chosen when it is set up (an id from config/models.ts).
-- Existing employees take the default at the time of this migration.
ALTER TABLE employees ADD COLUMN model text;
UPDATE employees SET model = 'claude-opus-5-5';
ALTER TABLE employees ALTER COLUMN model SET NOT NULL;
ALTER TABLE employees ADD CONSTRAINT employees_model_length CHECK (length(model) BETWEEN 1 AND 120);
