CREATE TABLE IF NOT EXISTS family_members (
  family_id text NOT NULL,
  id text NOT NULL,
  name text NOT NULL,
  role text NOT NULL CHECK (role IN ('parent', 'kid')),
  grade_or_birth_year text,
  color_tag text NOT NULL,
  PRIMARY KEY (family_id, id)
);

CREATE TABLE IF NOT EXISTS accounts (
  identity_subject text PRIMARY KEY,
  family_id text NOT NULL,
  member_id text NOT NULL,
  role text NOT NULL CHECK (role IN ('parent', 'kid')),
  FOREIGN KEY (family_id, member_id) REFERENCES family_members(family_id, id)
);

CREATE TABLE IF NOT EXISTS events (
  family_id text NOT NULL,
  id uuid NOT NULL,
  title text NOT NULL,
  kid_id text,
  participant_ids text[] NOT NULL DEFAULT '{}',
  start_time timestamptz NOT NULL,
  end_time timestamptz NOT NULL,
  location text,
  driver text,
  source text NOT NULL CHECK (source IN ('manual', 'email_suggested', 'voice')),
  status text NOT NULL CHECK (status IN ('confirmed', 'pending_review')),
  PRIMARY KEY (family_id, id),
  CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS events_family_start_idx ON events(family_id, start_time);
CREATE INDEX IF NOT EXISTS events_participants_idx ON events USING gin(participant_ids);
