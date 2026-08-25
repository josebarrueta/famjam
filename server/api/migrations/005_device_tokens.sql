CREATE TABLE IF NOT EXISTS device_tokens (
  token text PRIMARY KEY,
  family_id text NOT NULL,
  member_id text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (family_id, member_id) REFERENCES family_members(family_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS device_tokens_family_idx ON device_tokens(family_id);
