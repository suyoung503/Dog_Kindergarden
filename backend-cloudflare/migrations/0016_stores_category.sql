-- 네이버 플레이스 원본 카테고리(애견카페/반려견놀이터/애견놀이터 등) 보존용.
-- store_type은 앱 전역에서 "유치원"/"호텔" 단일값 비교로 쓰이므로 그대로 두고, 이 컬럼은 별도 정보로만 저장한다.
ALTER TABLE stores ADD COLUMN category TEXT;
