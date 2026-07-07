-- 공공 API 가게 매칭용 키 ("이름|주소")
ALTER TABLE stores ADD COLUMN store_key TEXT;

-- 예약에 가게 이름 denormalize (표시용)
ALTER TABLE reservations ADD COLUMN store_name TEXT;

-- (사용자 + 가게) 조합당 채팅방 1개
CREATE TABLE IF NOT EXISTS chat_rooms (
  room_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  store_id INTEGER NOT NULL,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, store_id)
);

-- 시드 방: 기존 room_id=1 메시지/다이어리와 정합 (user 1 + store 1)
INSERT INTO chat_rooms (room_id, user_id, store_id)
SELECT 1, 1, 1
WHERE NOT EXISTS (SELECT 1 FROM chat_rooms WHERE room_id = 1);
