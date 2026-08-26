ALTER TABLE family_invitations
ADD COLUMN IF NOT EXISTS recipient_email text;
