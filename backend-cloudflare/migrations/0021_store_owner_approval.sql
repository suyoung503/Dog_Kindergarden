-- 운영자 계정과 사장님 가게 등록 승인 대기열.
-- is_admin은 사장님 역할과 분리하며, 실제 운영자 계정에만 수동으로 부여한다.
ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS store_owner_applications (
  application_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  store_id INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
  reviewed_by INTEGER,
  applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (store_id) REFERENCES stores(store_id) ON DELETE CASCADE,
  FOREIGN KEY (reviewed_by) REFERENCES users(user_id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_store_owner_applications_pending_user_store
  ON store_owner_applications (user_id, store_id)
  WHERE status = 'PENDING';

CREATE UNIQUE INDEX IF NOT EXISTS idx_store_owner_applications_pending_store
  ON store_owner_applications (store_id)
  WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_store_owner_applications_status
  ON store_owner_applications (status, application_id DESC);
