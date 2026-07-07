-- 찜한 가게: (사용자 + 가게) 조합당 1개
CREATE TABLE IF NOT EXISTS favorites (
  favorite_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  store_id INTEGER NOT NULL,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, store_id)
);

-- 가게 유형 ("호텔" | "유치원") — 공공데이터 상호명으로 추정한 값을 찜 시점에 저장
ALTER TABLE stores ADD COLUMN store_type TEXT;
