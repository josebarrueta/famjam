ALTER TABLE family_invitations
ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid();

UPDATE family_invitations SET id = gen_random_uuid() WHERE id IS NULL;

ALTER TABLE family_invitations ALTER COLUMN id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS family_invitations_id_idx
ON family_invitations(id);

CREATE INDEX IF NOT EXISTS family_invitations_family_pending_idx
ON family_invitations(family_id, expires_at)
WHERE consumed_at IS NULL;
