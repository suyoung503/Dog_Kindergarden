-- 역할(보호자/사장님)을 최초 가입 시 계정에 귀속 — 같은 카카오 계정으로 다른 역할 가입 불가
ALTER TABLE users ADD COLUMN is_owner INTEGER DEFAULT 0;
