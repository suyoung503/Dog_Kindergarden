-- 주간 가게 상세정보 갱신 순서를 관리한다.
-- 예약된 크롤러는 가장 오래 확인하지 않은 큐레이션 가게부터 처리한다.

ALTER TABLE stores ADD COLUMN details_checked_at TEXT;

CREATE INDEX IF NOT EXISTS idx_stores_details_checked_at
ON stores(is_curated, details_checked_at);
