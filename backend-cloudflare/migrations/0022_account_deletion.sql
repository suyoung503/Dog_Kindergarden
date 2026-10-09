-- 회원 탈퇴 시 사용자 행은 예약 등 운영 기록의 참조 무결성을 위해 익명 상태로 남긴다.
-- 카카오 식별자와 프로필 개인정보는 탈퇴 API에서 복구 불가능한 값으로 교체한다.
ALTER TABLE users ADD COLUMN deleted_at TEXT;

CREATE INDEX IF NOT EXISTS idx_users_deleted_at
  ON users (deleted_at);
