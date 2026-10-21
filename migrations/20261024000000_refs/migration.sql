-- conversations
-- U8: everything that points at a record holds a Ref, devys:<app>/<kind>/<id> with the id
-- percent-encoded as encodeURIComponent does (src/protocol/ref.ts). A page card's
-- `artifact:<id>` and a card's bare work item or coding session id are rewritten; a ref that
-- names nothing any more is cleared.
CREATE FUNCTION pg_temp.uri_component(value text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(string_agg(
    CASE WHEN b BETWEEN 48 AND 57 OR b BETWEEN 65 AND 90 OR b BETWEEN 97 AND 122
      OR b IN (33, 39, 40, 41, 42, 45, 46, 95, 126) THEN chr(b)
      ELSE '%' || upper(lpad(to_hex(b), 2, '0')) END, '' ORDER BY i), '')
  FROM (SELECT i, get_byte(convert_to(value, 'UTF8'), i) AS b
        FROM generate_series(0, octet_length(convert_to(value, 'UTF8')) - 1) AS i) AS bytes
$$;

UPDATE messages m SET ref = CASE
    WHEN m.ref LIKE 'artifact:%'
      THEN 'devys:documents/artifact/' || pg_temp.uri_component(substr(m.ref, 10))
    WHEN EXISTS (SELECT 1 FROM commitments c WHERE c.business_id = m.business_id AND c.id = m.ref)
      THEN 'devys:work/item/' || pg_temp.uri_component(m.ref)
    WHEN EXISTS (SELECT 1 FROM assignments a WHERE a.business_id = m.business_id AND a.id = m.ref)
      THEN 'devys:code/session/' || pg_temp.uri_component(m.ref)
  END
  WHERE m.ref IS NOT NULL;
ALTER TABLE messages ADD CONSTRAINT messages_ref_check
  CHECK (ref ~ '^devys:[a-z]+/[a-z]+/[^/]+$' AND length(ref) <= 2048);

-- work
-- A project shows artifacts and files of the business folder, each by its Ref, once.
ALTER TABLE project_items ADD COLUMN item_ref text;
UPDATE project_items SET item_ref = CASE kind
    WHEN 'artifact' THEN 'devys:documents/artifact/' || pg_temp.uri_component(ref)
    WHEN 'file' THEN 'devys:documents/file/' || pg_temp.uri_component(ref)
  END;
ALTER TABLE project_items DROP CONSTRAINT project_items_project_id_kind_ref_key;
ALTER TABLE project_items DROP COLUMN kind;
ALTER TABLE project_items DROP COLUMN ref;
ALTER TABLE project_items RENAME COLUMN item_ref TO ref;
ALTER TABLE project_items ALTER COLUMN ref SET NOT NULL;
ALTER TABLE project_items ADD CONSTRAINT project_items_ref_check
  CHECK (ref ~ '^devys:documents/(artifact|file)/[^/]+$' AND length(ref) <= 2048);
ALTER TABLE project_items ADD CONSTRAINT project_items_project_id_ref_key UNIQUE (project_id, ref);

DROP FUNCTION pg_temp.uri_component(text);

-- authority
-- listSkills is replaced by readSkill: each active grant is revoked and reissued, so a grant
-- stays immutable and decisions keep binding the revision they named.
INSERT INTO grants (id, business_id, employee_id, capability, mode, constraints, responsibility)
  SELECT gen_random_uuid()::text, business_id, employee_id, 'readSkill', mode, constraints,
    responsibility
  FROM grants WHERE capability = 'listSkills' AND revoked_at IS NULL;
UPDATE grants SET revoked_at = now() WHERE capability = 'listSkills' AND revoked_at IS NULL;
