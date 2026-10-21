-- apps
-- U7: the apps each business has installed from the directory, and whether the owner keeps
-- them in the sidebar. Documents and Code come with every business.
CREATE TABLE app_installs (
  business_id text NOT NULL REFERENCES businesses(id),
  app_id text NOT NULL CHECK (app_id ~ '^[a-z][a-z0-9-]{0,39}$'),
  pinned boolean NOT NULL DEFAULT true,
  installed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, app_id)
);
INSERT INTO app_installs (business_id, app_id)
  SELECT id, app FROM businesses CROSS JOIN unnest(ARRAY['documents', 'code']) AS app;
