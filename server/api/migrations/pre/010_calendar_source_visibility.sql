ALTER TABLE calendar_sources
ADD COLUMN IF NOT EXISTS owner_member_id text;

ALTER TABLE calendar_sources
ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'family';

UPDATE calendar_sources source
SET owner_member_id = (
  SELECT account.member_id
  FROM accounts account
  WHERE account.family_id = source.family_id
    AND account.role = 'parent'
  ORDER BY account.identity_subject
  LIMIT 1
)
WHERE source.owner_member_id IS NULL;

ALTER TABLE calendar_sources
ALTER COLUMN owner_member_id SET NOT NULL;

ALTER TABLE calendar_sources
DROP CONSTRAINT IF EXISTS calendar_sources_visibility_check;

ALTER TABLE calendar_sources
ADD CONSTRAINT calendar_sources_visibility_check
CHECK (visibility IN ('personal', 'family'));

ALTER TABLE calendar_sources
DROP CONSTRAINT IF EXISTS calendar_sources_owner_member_fkey;

ALTER TABLE calendar_sources
ADD CONSTRAINT calendar_sources_owner_member_fkey
FOREIGN KEY (family_id, owner_member_id)
REFERENCES family_members(family_id, id)
ON DELETE CASCADE;
