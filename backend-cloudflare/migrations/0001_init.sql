CREATE TABLE IF NOT EXISTS stores (
  store_id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  status TEXT DEFAULT '영업',
  latitude REAL,
  longitude REAL,
  open_time TEXT,
  pickup INTEGER DEFAULT 0,
  playground INTEGER DEFAULT 0,
  large_dog INTEGER DEFAULT 0,
  price_info TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pets (
  pet_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  breed TEXT,
  age INTEGER,
  weight REAL,
  gender TEXT,
  note TEXT,
  image_url TEXT
);

CREATE TABLE IF NOT EXISTS reservations (
  reservation_id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  pet_id INTEGER NOT NULL,
  store_id INTEGER NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  reservation_type TEXT NOT NULL,
  status TEXT DEFAULT 'REQUEST',
  request_message TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS diaries (
  diary_id INTEGER PRIMARY KEY AUTOINCREMENT,
  reservation_id INTEGER NOT NULL,
  store_id INTEGER,
  content TEXT NOT NULL,
  media_type TEXT,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS chat_messages (
  message_id INTEGER PRIMARY KEY AUTOINCREMENT,
  room_id INTEGER NOT NULL,
  sender_id INTEGER NOT NULL,
  sender_name TEXT,
  message_type TEXT DEFAULT 'TEXT',
  content TEXT NOT NULL,
  created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO stores (name, address, phone, status, latitude, longitude, pickup, playground, large_dog, price_info)
SELECT '맡겨멍 강남 유치원', '서울 강남구 테헤란로', '02-0000-0000', '영업', 37.501, 127.039, 1, 1, 1, '데이케어 3만원~'
WHERE NOT EXISTS (SELECT 1 FROM stores WHERE name='맡겨멍 강남 유치원');

INSERT INTO pets (user_id, name, breed, age, weight, gender, note)
SELECT 1, '초코', '말티푸', 3, 5.2, '남아', '닭고기 알러지 있음'
WHERE NOT EXISTS (SELECT 1 FROM pets WHERE user_id=1 AND name='초코');

INSERT INTO diaries (reservation_id, store_id, content, media_type)
SELECT 1, 1, '초코가 친구들과 잘 놀고 산책도 완료했어요.', 'IMAGE'
WHERE NOT EXISTS (SELECT 1 FROM diaries WHERE reservation_id=1);

INSERT INTO chat_messages (room_id, sender_id, sender_name, message_type, content)
SELECT 1, 0, '맡겨멍', 'AUTO', '예약 요청이 완료되었습니다.'
WHERE NOT EXISTS (SELECT 1 FROM chat_messages WHERE room_id=1);
