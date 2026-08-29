CREATE TABLE IF NOT EXISTS family_invitations (
  code_hash text PRIMARY KEY,
  family_id text NOT NULL,
  role text NOT NULL CHECK (role IN ('parent', 'kid')),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz
);

CREATE INDEX IF NOT EXISTS family_invitations_active_idx
ON family_invitations(expires_at)
WHERE consumed_at IS NULL;
