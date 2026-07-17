-- 구 reviews 테이블 제거.
-- 리뷰 기능은 0003_pet_reviews.sql의 pet_reviews 테이블(/api/pet-reviews)로 완전히 대체됐고,
-- reviews는 index.ts·iOS 어디에서도 참조되지 않는 죽은 테이블(배포 DB 0행)이라 드롭한다.
DROP TABLE IF EXISTS reviews;
