-- 채팅방 시스템 안내와 알림 이동 목적을 함께 보존한다. 기존 AUTO 메시지는 미분류 채팅으로 유지한다.
ALTER TABLE chat_messages ADD COLUMN event_type TEXT;
ALTER TABLE chat_messages ADD COLUMN reservation_id INTEGER;
ALTER TABLE chat_messages ADD COLUMN diary_id INTEGER;
