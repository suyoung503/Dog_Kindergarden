-- 정리 조회의 datetime(COALESCE(...)) 조건과 같은 식을 인덱싱한다.
-- 기존 available_at 인덱스는 이 조건에서 사용되지 않아 대기열 전체를 스캔했다.
DROP INDEX IF EXISTS idx_diary_photo_deletion_available;

CREATE INDEX IF NOT EXISTS idx_diary_photo_deletion_due
ON diary_photo_deletion_queue(datetime(COALESCE(available_at, queued_at)), queued_at);
