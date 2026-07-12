-- 안 읽은 채팅 표시(홈 종 아이콘 빨간 점)용 읽음 상태 추적
-- (방, 사용자)별로 마지막으로 읽은 message_id를 기록 — 손님·사장님이 같은 방을 각자 시점으로 읽는다
CREATE TABLE chat_room_reads (
  room_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  last_read_message_id INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (room_id, user_id)
);
