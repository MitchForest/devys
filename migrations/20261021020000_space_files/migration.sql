-- work
-- U6: a space can show a file from the business folder by its path, beside work and artifacts.
ALTER TABLE space_items DROP CONSTRAINT space_items_kind_check;
ALTER TABLE space_items ADD CONSTRAINT space_items_kind_check CHECK (kind IN ('commitment', 'artifact', 'file'));
ALTER TABLE space_items ADD CONSTRAINT space_items_ref_length CHECK (length(ref) BETWEEN 1 AND 1024);
