CREATE TABLE IF NOT EXISTS family_reminders (
  family_id text NOT NULL,
  id uuid NOT NULL,
  title text NOT NULL CHECK (length(btrim(title)) > 0),
  assignee_ids text[] NOT NULL,
  due_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'completed')),
  completed_at timestamptz,
  completed_by_member_id text,
  alert_lead_time_minutes integer,
  created_by_member_id text NOT NULL,
  notification_claimed_at timestamptz,
  notification_sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (family_id, id),
  CHECK (cardinality(assignee_ids) > 0),
  CHECK (alert_lead_time_minutes IS NULL OR alert_lead_time_minutes IN (0, 5, 15, 60, 1440)),
  CHECK (
    (status = 'open' AND completed_at IS NULL AND completed_by_member_id IS NULL)
    OR
    (status = 'completed' AND completed_at IS NOT NULL AND completed_by_member_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS family_reminders_family_due_idx
ON family_reminders(family_id, due_at);

CREATE INDEX IF NOT EXISTS family_reminders_assignees_idx
ON family_reminders USING gin(assignee_ids);

CREATE INDEX IF NOT EXISTS family_reminders_pending_notifications_idx
ON family_reminders(due_at, alert_lead_time_minutes)
WHERE status = 'open' AND notification_sent_at IS NULL AND alert_lead_time_minutes IS NOT NULL;
