ALTER TABLE stores ADD COLUMN partner_status TEXT NOT NULL DEFAULT 'NONE'
  CHECK (partner_status IN ('NONE', 'PENDING', 'ACTIVE', 'SUSPENDED', 'TERMINATED'));
ALTER TABLE stores ADD COLUMN partner_approved_at TEXT;
ALTER TABLE stores ADD COLUMN partner_approved_by INTEGER REFERENCES users(user_id);

-- 과거 즉시 등록 방식으로 연결된 owner_id는 자동 인증하지 않는다.
-- 승인 이력이 없으면 기존 소유자를 신청 대기열로 옮기고 연결을 해제한다.
INSERT INTO store_owner_applications (user_id, store_id, status)
SELECT s.owner_id, s.store_id, 'PENDING'
FROM stores s
WHERE s.owner_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM store_owner_applications approved
    WHERE approved.store_id = s.store_id
      AND approved.user_id = s.owner_id
      AND approved.status = 'APPROVED'
  )
  AND NOT EXISTS (
    SELECT 1 FROM store_owner_applications pending
    WHERE pending.store_id = s.store_id AND pending.status = 'PENDING'
  );

UPDATE stores
SET owner_id = NULL,
    partner_status = 'PENDING'
WHERE owner_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM store_owner_applications approved
    WHERE approved.store_id = stores.store_id
      AND approved.user_id = stores.owner_id
      AND approved.status = 'APPROVED'
  );

-- 운영자 승인 이력과 현재 소유자가 일치하는 가게만 파트너로 승계한다.
UPDATE stores
SET partner_status = 'ACTIVE',
    partner_approved_at = COALESCE(
      (SELECT MAX(reviewed_at)
       FROM store_owner_applications a
       WHERE a.store_id = stores.store_id AND a.status = 'APPROVED'),
      CURRENT_TIMESTAMP
    ),
    partner_approved_by = (
      SELECT reviewed_by
      FROM store_owner_applications a
      WHERE a.store_id = stores.store_id AND a.status = 'APPROVED'
      ORDER BY application_id DESC
      LIMIT 1
    )
WHERE owner_id IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM store_owner_applications approved
    WHERE approved.store_id = stores.store_id
      AND approved.user_id = stores.owner_id
      AND approved.status = 'APPROVED'
  );

CREATE INDEX IF NOT EXISTS idx_stores_partner_status
  ON stores(partner_status, is_curated);

-- 기능 권한은 중복 저장하지 않고 파트너 상태에서 일관되게 계산한다.
CREATE VIEW store_capabilities AS
SELECT store_id,
       CASE WHEN partner_status = 'ACTIVE' AND owner_id IS NOT NULL THEN 1 ELSE 0 END AS is_partner,
       CASE WHEN partner_status = 'ACTIVE' AND owner_id IS NOT NULL THEN 1 ELSE 0 END AS can_book,
       CASE WHEN partner_status = 'ACTIVE' AND owner_id IS NOT NULL THEN 1 ELSE 0 END AS can_chat,
       CASE WHEN partner_status = 'ACTIVE' AND owner_id IS NOT NULL THEN 1 ELSE 0 END AS can_diary,
       CASE WHEN partner_status = 'ACTIVE' AND owner_id IS NOT NULL THEN 1 ELSE 0 END AS can_review
FROM stores;
