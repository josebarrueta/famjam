ALTER TABLE family_invitations
ADD COLUMN IF NOT EXISTS guardian_consent_at timestamptz;

ALTER TABLE family_invitations
ADD COLUMN IF NOT EXISTS guardian_member_id text;

CREATE INDEX IF NOT EXISTS family_invitations_guardian_consent_idx
ON family_invitations(family_id, guardian_consent_at)
WHERE role = 'kid' AND guardian_consent_at IS NOT NULL;
