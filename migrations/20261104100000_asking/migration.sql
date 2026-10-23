-- authority
-- `askOwner` gains the file kind: answered with the file the owner chose, put in the business
-- folder; `answer` is that file's ref. An approve may show a draft (its ref and the hash of its
-- content when asked, both in `input`) and list the exact steps it covers.
ALTER TABLE decisions DROP CONSTRAINT decisions_kind_check;
ALTER TABLE decisions ADD CONSTRAINT decisions_kind_check
  CHECK (kind IN ('decision', 'approve', 'take_over', 'secret', 'connect', 'file'));
ALTER TABLE decisions ADD COLUMN answer text
  CHECK (answer IS NULL OR (kind = 'file' AND answer ~ '^devys:documents/file/[^/]+$'));
