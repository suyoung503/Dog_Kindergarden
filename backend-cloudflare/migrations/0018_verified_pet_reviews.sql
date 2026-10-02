-- 리뷰 작성자를 실제 이용 완료 예약과 연결한다.
-- 기존 리뷰는 두 컬럼이 NULL인 레거시 데이터로 보존하되 앱 조회에서는 제외한다.
ALTER TABLE pet_reviews ADD COLUMN user_id INTEGER;
ALTER TABLE pet_reviews ADD COLUMN reservation_id INTEGER;

-- 한 번의 이용(예약)에는 리뷰 한 개만 작성할 수 있다.
CREATE UNIQUE INDEX IF NOT EXISTS idx_pet_reviews_reservation
  ON pet_reviews (reservation_id)
  WHERE reservation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_reservations_review_eligibility
  ON reservations (user_id, store_id, status, end_date);
