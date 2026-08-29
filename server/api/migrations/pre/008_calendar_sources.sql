CREATE TABLE IF NOT EXISTS calendar_sources (
  family_id text NOT NULL,
  id uuid NOT NULL,
  name text NOT NULL,
  feed_url_ciphertext text NOT NULL,
  participant_ids text[] NOT NULL,
  status text NOT NULL CHECK (status IN ('pending', 'ready', 'error')),
  last_synced_at timestamptz,
  last_error text,
  etag text,
  last_modified text,
  PRIMARY KEY (family_id, id),
  CHECK (cardinality(participant_ids) > 0)
);

CREATE TABLE IF NOT EXISTS imported_calendar_events (
  family_id text NOT NULL,
  source_id uuid NOT NULL,
  external_uid text NOT NULL,
  title text NOT NULL,
  start_time timestamptz NOT NULL,
  end_time timestamptz NOT NULL,
  location text,
  participant_ids text[] NOT NULL,
  fingerprint text NOT NULL,
  PRIMARY KEY (source_id, external_uid),
  FOREIGN KEY (family_id, source_id)
    REFERENCES calendar_sources(family_id, id)
    ON DELETE CASCADE,
  CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS imported_calendar_events_family_start_idx
ON imported_calendar_events(family_id, start_time);

CREATE INDEX IF NOT EXISTS imported_calendar_events_fingerprint_idx
ON imported_calendar_events(family_id, fingerprint);
