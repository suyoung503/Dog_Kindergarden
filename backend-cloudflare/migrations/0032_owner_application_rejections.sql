-- 배포 이후 최초 PENDING → REJECTED 전이만 기록한다. 과거 상태를 backfill하지 않는다.
CREATE TABLE owner_application_rejections (
  rejection_id INTEGER PRIMARY KEY AUTOINCREMENT,
  application_id INTEGER NOT NULL UNIQUE REFERENCES store_owner_applications(application_id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  store_name TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_owner_application_rejections_user ON owner_application_rejections(user_id, rejection_id);
