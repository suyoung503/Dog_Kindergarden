-- R2 keys never leave the authenticated pet-photo API.
CREATE TABLE IF NOT EXISTS pet_photos (
  pet_id INTEGER PRIMARY KEY REFERENCES pets(pet_id) ON DELETE CASCADE,
  r2_key TEXT NOT NULL UNIQUE,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Pet and account deletion use the same durable R2 cleanup queue as diary photos.
CREATE TRIGGER IF NOT EXISTS queue_pet_photo_before_pet_delete
BEFORE DELETE ON pets
BEGIN
  INSERT OR IGNORE INTO diary_photo_deletion_queue (r2_key)
    SELECT r2_key FROM pet_photos WHERE pet_id = OLD.pet_id;
  DELETE FROM pet_photos WHERE pet_id = OLD.pet_id;
END;
