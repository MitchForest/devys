-- connections
-- AL3: Drive files and writes belong to Documents, whose app owns the drive capabilities; the
-- connection keeps only the Google grant. The rows move to the same tables under Documents.
ALTER TABLE drive_files RENAME TO drive_files_moving;
ALTER TABLE drive_files_moving RENAME CONSTRAINT drive_files_pkey TO drive_files_moving_pkey;
ALTER TABLE drive_operations RENAME TO drive_operations_moving;
ALTER TABLE drive_operations_moving RENAME CONSTRAINT drive_operations_pkey
  TO drive_operations_moving_pkey;

-- documents
-- A file the owner chose in the Drive picker, or one Devys wrote. Disconnecting removes it.
CREATE TABLE drive_files (
  business_id text NOT NULL,
  connection_id text NOT NULL REFERENCES google_connections(id) ON DELETE CASCADE,
  file_id text NOT NULL,
  name text NOT NULL,
  mime_type text NOT NULL,
  PRIMARY KEY (business_id, file_id)
);
INSERT INTO drive_files (business_id, connection_id, file_id, name, mime_type)
  SELECT business_id, connection_id, file_id, name, mime_type FROM drive_files_moving;

-- A Drive write's receipt: its input, the file it targets and whether it is known to have landed.
CREATE TABLE drive_operations (
  business_id text NOT NULL,
  operation_id text NOT NULL,
  connection_id text NOT NULL,
  input_hash text NOT NULL,
  file_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('prepared', 'uncertain', 'completed')),
  PRIMARY KEY (business_id, operation_id)
);
INSERT INTO drive_operations (business_id, operation_id, connection_id, input_hash, file_id, status)
  SELECT business_id, operation_id, connection_id, input_hash, file_id, status
  FROM drive_operations_moving;

-- connections
DROP TABLE drive_files_moving;
DROP TABLE drive_operations_moving;
