ALTER TABLE events
ADD COLUMN IF NOT EXISTS recurrence jsonb;

ALTER TABLE events
DROP CONSTRAINT IF EXISTS events_recurrence_shape;

ALTER TABLE events
ADD CONSTRAINT events_recurrence_shape CHECK (
  recurrence IS NULL OR (
    recurrence->>'frequency' IN ('daily', 'weekly', 'monthly')
    AND (recurrence->>'interval')::integer > 0
    AND recurrence ? 'endDate'
  )
);
