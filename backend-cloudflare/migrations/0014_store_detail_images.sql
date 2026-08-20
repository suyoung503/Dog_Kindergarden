-- 크롤링/수집으로 보강하는 가게 상세 정보
-- 대표 이미지는 stores.image_url에 저장하고, 추가 이미지는 store_images에 여러 장 저장한다.

ALTER TABLE stores ADD COLUMN image_url TEXT;

CREATE TABLE IF NOT EXISTS store_images (
  image_id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER NOT NULL,
  image_url TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(store_id, image_url)
);

CREATE INDEX IF NOT EXISTS idx_store_images_store_id ON store_images(store_id);
