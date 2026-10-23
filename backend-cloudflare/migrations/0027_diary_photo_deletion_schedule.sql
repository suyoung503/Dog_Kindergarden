ALTER TABLE diary_photo_deletion_queue ADD COLUMN available_at TEXT;

UPDATE diary_photo_deletion_queue
SET available_at = queued_at
WHERE available_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_diary_photo_deletion_available
ON diary_photo_deletion_queue(available_at, queued_at);

