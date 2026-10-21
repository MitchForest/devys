-- identity
-- AL4: one name per concept on the wire. An employee's role is the template it was hired from;
-- what it is accountable for is its responsibilities, in the schema as in the API.
ALTER TABLE employees RENAME COLUMN role TO responsibilities;
ALTER TABLE employees RENAME CONSTRAINT employees_role_check TO employees_responsibilities_check;

-- work
-- Evidence is read by clients as stored: snake_case fields, and `at` in the API's one timestamp
-- form (ISO 8601, UTC, milliseconds) instead of Postgres's JSON form with the session offset.
UPDATE work_items SET evidence = (
  SELECT jsonb_agg(
    (entry - 'at' - 'pullRequest' - 'check')
    || CASE WHEN entry ? 'at' THEN jsonb_build_object('at',
         to_char((entry->>'at')::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
       ELSE '{}'::jsonb END
    || CASE WHEN entry ? 'pullRequest'
       THEN jsonb_build_object('pull_request', entry->'pullRequest') ELSE '{}'::jsonb END
    || CASE WHEN entry ? 'check' THEN jsonb_build_object('check', jsonb_build_object(
         'command', entry->'check'->'command', 'exit_code', entry->'check'->'exitCode'))
       ELSE '{}'::jsonb END
    ORDER BY position)
  FROM jsonb_array_elements(evidence) WITH ORDINALITY AS item(entry, position)
) WHERE jsonb_array_length(evidence) > 0;

-- memory
-- A claim's validity and its evidence's observation time in the API's field names.
UPDATE memories SET details = (details - 'validFrom' - 'validUntil' - 'evidence')
  || jsonb_build_object(
    'valid_from', details->'validFrom',
    'valid_until', details->'validUntil',
    'evidence', coalesce((
      SELECT jsonb_agg((e - 'observedAt') || jsonb_build_object('observed_at', e->'observedAt')
        ORDER BY position)
      FROM jsonb_array_elements(coalesce(details->'evidence', '[]'::jsonb))
        WITH ORDINALITY AS item(e, position)
    ), '[]'::jsonb));
UPDATE memory_links
  SET evidence = (evidence - 'observedAt') || jsonb_build_object('observed_at', evidence->'observedAt')
  WHERE evidence ? 'observedAt';
