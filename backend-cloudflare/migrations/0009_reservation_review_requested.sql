-- 이용일 다음날 리뷰 요청 자동 메시지의 중복 발송 방지 플래그
ALTER TABLE reservations ADD COLUMN review_requested INTEGER DEFAULT 0;
