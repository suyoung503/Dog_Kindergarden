-- 가게 채팅과 분리된 고객센터 1:1 문의 대화.
-- 일반 사용자는 한 개의 문의 대화를 가지며, is_admin=1 운영자만 전체 문의에 답장한다.
CREATE TABLE IF NOT EXISTS support_conversations (
  conversation_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'CLOSED')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS support_messages (
  message_id INTEGER PRIMARY KEY AUTOINCREMENT,
  conversation_id INTEGER NOT NULL,
  sender_id INTEGER NOT NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('USER', 'ADMIN')),
  content TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (conversation_id) REFERENCES support_conversations(conversation_id) ON DELETE CASCADE,
  FOREIGN KEY (sender_id) REFERENCES users(user_id)
);

CREATE INDEX IF NOT EXISTS idx_support_conversations_updated
  ON support_conversations (updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_messages_conversation
  ON support_messages (conversation_id, message_id);
