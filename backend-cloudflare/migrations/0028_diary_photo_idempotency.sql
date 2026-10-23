ALTER TABLE diary_photos ADD COLUMN client_request_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_diary_photos_idempotency
ON diary_photos(diary_id, client_request_id)
WHERE client_request_id IS NOT NULL;

