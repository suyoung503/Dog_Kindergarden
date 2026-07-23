-- 알림 피드용 예약 상태 전환 시각 (설계: docs/superpowers/specs/2026-07-18-push-notifications-design.md)
-- confirmed_at: 확정 시각 (고객 '예약 확정' 알림 커서)
-- canceled_at/canceled_by: 취소 시각·주체 (canceled_by='USER'만 사장님 '고객 취소' 알림 대상)
ALTER TABLE reservations ADD COLUMN confirmed_at TEXT;
ALTER TABLE reservations ADD COLUMN canceled_at TEXT;
ALTER TABLE reservations ADD COLUMN canceled_by TEXT;
