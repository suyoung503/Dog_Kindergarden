-- 공공데이터 가게(백엔드 store_id 없음)에 붙는 펫 특화 리뷰
-- store_key = 이름|주소 로 식별. 체크박스 플래그가 곧 필터 데이터가 됨.
CREATE TABLE IF NOT EXISTS pet_reviews (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_key TEXT NOT NULL,            -- "상호명|도로명주소"
  store_name TEXT,
  user_name TEXT DEFAULT '익명',
  rating REAL NOT NULL,              -- 1.0 ~ 5.0
  revisit INTEGER DEFAULT 0,         -- 재방문 의향
  cctv INTEGER DEFAULT 0,            -- CCTV 실시간 공유
  pickup INTEGER DEFAULT 0,          -- 픽업/드랍
  large_dog INTEGER DEFAULT 0,       -- 대형견 가능
  separation_care INTEGER DEFAULT 0, -- 분리불안 케어
  content TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_pet_reviews_store_key ON pet_reviews (store_key);
