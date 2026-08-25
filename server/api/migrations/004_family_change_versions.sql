CREATE TABLE IF NOT EXISTS family_change_versions (
  family_id text PRIMARY KEY,
  version bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
