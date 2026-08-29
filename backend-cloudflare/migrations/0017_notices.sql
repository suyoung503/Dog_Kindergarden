-- 앱 전체 공지사항 — 개발자가 DB에 직접 INSERT해서 운영(앱 내 작성 화면 없음)
CREATE TABLE IF NOT EXISTS notices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
