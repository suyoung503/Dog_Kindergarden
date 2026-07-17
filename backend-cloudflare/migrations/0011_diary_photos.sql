-- 알림장(diary) 사진 — 엔트리(diaries) 1건에 사진 여러 장을 매단다
-- 사진 저장(R2)은 계정 활성화 후 추가 예정이라 지금은 스키마만 준비(텍스트 타임라인 먼저 출시)
CREATE TABLE IF NOT EXISTS diary_photos (
  photo_id INTEGER PRIMARY KEY AUTOINCREMENT,
  diary_id INTEGER NOT NULL,
  r2_key TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_diary_photos_diary ON diary_photos(diary_id);
