-- 가게 소유 사장님 (users.user_id) — 가게 상세의 "내 가게로 등록"으로 연결
ALTER TABLE stores ADD COLUMN owner_id INTEGER;
