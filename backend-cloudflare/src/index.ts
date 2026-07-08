import { Hono } from "hono";
import { cors } from "hono/cors";

type ReservationBody = {
  user_id?: number;
  userId?: number;
  pet_id?: number;
  petId?: number;
  store_id?: number;
  storeId?: number;
  store_key?: string;
  storeKey?: string;
  store_name?: string;
  storeName?: string;
  store_address?: string;
  storeAddress?: string;
  start_date?: string;
  startDate?: string;
  end_date?: string;
  endDate?: string;
  reservation_type?: string;
  reservationType?: string;
  request_message?: string;
  requestMessage?: string;
  store_type?: string;
  storeType?: string;
};

type ReviewBody = {
  reservation_id?: number;
  reservationId?: number;
  user_id?: number;
  userId?: number;
  store_id?: number;
  storeId?: number;
  rating?: number;
  revisit?: boolean;
  content?: string;
};

type PetReviewBody = {
  store_key?: string;
  storeKey?: string;
  store_name?: string;
  storeName?: string;
  user_name?: string;
  userName?: string;
  rating?: number;
  revisit?: boolean;
  cctv?: boolean;
  pickup?: boolean;
  large_dog?: boolean;
  separation_care?: boolean;
  content?: string;
};

type ChatMessageBody = {
  sender_id?: number;
  senderId?: number;
  sender_name?: string;
  senderName?: string;
  message_type?: string;
  messageType?: string;
  content?: string;
};

type ChatRoomBody = {
  user_id?: number;
  userId?: number;
  store_id?: number;
  storeId?: number;
  store_key?: string;
  storeKey?: string;
  store_name?: string;
  storeName?: string;
  store_address?: string;
  storeAddress?: string;
};

type KakaoAuthBody = {
  kakao_id: string;
  nickname: string;
  email?: string;
};

type FavoriteBody = {
  user_id?: number;
  userId?: number;
  store_key?: string;
  storeKey?: string;
  store_name?: string;
  storeName?: string;
  store_address?: string;
  storeAddress?: string;
  phone?: string;
  store_type?: string;
  storeType?: string;
  latitude?: number;
  longitude?: number;
};

type UpdateUserBody = {
  nickname?: string;
  phone?: string;
  address?: string;
};

type CreatePetBody = {
  name: string;
  breed?: string;
  age?: number;
  weight?: number;
  gender?: string;
  note?: string;
};

type Bindings = {
  DB: D1Database;
  APP_NAME: string;
};

const app = new Hono<{ Bindings: Bindings }>();
app.use("*", cors());

// MARK: - 채팅방 공용 헬퍼

// 가게번호 확정: store_id가 오면 그대로, 없으면 store_key로 조회 → 없으면 신규 등록(자동 번호)
async function resolveStoreId(
  db: D1Database,
  opts: {
    storeId?: number;
    storeKey?: string;
    storeName?: string;
    storeAddress?: string;
  },
): Promise<number> {
  if (opts.storeId) return opts.storeId;
  const storeKey = (opts.storeKey ?? "").trim();
  if (!storeKey) return 1;

  const existing = await db
    .prepare(`SELECT store_id FROM stores WHERE store_key = ?`)
    .bind(storeKey)
    .first<{ store_id: number }>();
  if (existing) return existing.store_id;

  const ins = await db
    .prepare(`INSERT INTO stores (name, address, store_key) VALUES (?, ?, ?)`)
    .bind(opts.storeName ?? "", opts.storeAddress ?? "", storeKey)
    .run();
  return Number(ins.meta.last_row_id);
}

// (user_id, store_id) 방 조회 → 없으면 생성(자동 번호)
async function getOrCreateRoom(
  db: D1Database,
  userId: number,
  storeId: number,
): Promise<number> {
  const room = await db
    .prepare(`SELECT room_id FROM chat_rooms WHERE user_id = ? AND store_id = ?`)
    .bind(userId, storeId)
    .first<{ room_id: number }>();
  if (room) return room.room_id;

  const insRoom = await db
    .prepare(`INSERT INTO chat_rooms (user_id, store_id) VALUES (?, ?)`)
    .bind(userId, storeId)
    .run();
  return Number(insRoom.meta.last_row_id);
}

// 조회 전용: store가 있어야 방을 찾고, 없으면 null. 쓰기 없음.
async function findRoomId(
  db: D1Database,
  userId: number,
  storeKey: string,
): Promise<number | null> {
  const key = storeKey.trim();
  if (!key) return null;

  const store = await db
    .prepare(`SELECT store_id FROM stores WHERE store_key = ?`)
    .bind(key)
    .first<{ store_id: number }>();
  if (!store) return null;

  const room = await db
    .prepare(`SELECT room_id FROM chat_rooms WHERE user_id = ? AND store_id = ?`)
    .bind(userId, store.store_id)
    .first<{ room_id: number }>();
  return room ? room.room_id : null;
}

app.get("/", (c) => c.json({ ok: true, service: c.env.APP_NAME }));

app.get("/api/stores", async (c) => {
  const { results } = await c.env.DB.prepare(
    `
    SELECT store_id, name, address, phone, status, latitude, longitude, open_time, pickup, playground, large_dog, price_info
    FROM stores
    ORDER BY store_id DESC
  `,
  ).all();
  return c.json(results);
});

app.post("/api/reservations", async (c) => {
  const body = await c.req.json<ReservationBody>();
  const userId = body.user_id ?? body.userId ?? 1;
  const petId = body.pet_id ?? body.petId ?? 1;
  const startDate = body.start_date ?? body.startDate;
  const endDate = body.end_date ?? body.endDate;
  const reservationType =
    body.reservation_type ?? body.reservationType ?? "NORMAL";
  const requestMessage = body.request_message ?? body.requestMessage ?? "";
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  const storeName = body.store_name ?? body.storeName ?? "";
  const storeAddress = body.store_address ?? body.storeAddress ?? "";

  if (!startDate || !endDate)
    return c.json({ message: "start_date/end_date is required" }, 400);

  // 1) 가게번호 + 2) 방번호 확정 (공용 헬퍼)
  const storeId = await resolveStoreId(c.env.DB, {
    storeId: body.store_id ?? body.storeId,
    storeKey,
    storeName,
    storeAddress,
  });
  const roomId = await getOrCreateRoom(c.env.DB, userId, storeId);

  // 가게 유형(호텔/유치원) — 비어 있는 경우에만 채움 (기존 값 보존)
  const storeType = body.store_type ?? body.storeType ?? null;
  if (storeType) {
    await c.env.DB.prepare(
      `UPDATE stores SET store_type = COALESCE(NULLIF(store_type, ''), ?) WHERE store_id = ?`,
    )
      .bind(storeType, storeId)
      .run();
  }

  // 3) 예약 INSERT
  const result = await c.env.DB.prepare(
    `
    INSERT INTO reservations (user_id, pet_id, store_id, store_name, start_date, end_date, reservation_type, status, request_message)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'REQUEST', ?)
  `,
  )
    .bind(
      userId,
      petId,
      storeId,
      storeName,
      startDate,
      endDate,
      reservationType,
      requestMessage,
    )
    .run();

  const reservationId = Number(result.meta.last_row_id ?? 1);

  // 4) 확정된 방에 예약 완료 자동 메시지
  await c.env.DB.prepare(
    `
    INSERT INTO chat_messages (room_id, sender_id, sender_name, message_type, content)
    VALUES (?, 0, '맡겨멍', 'AUTO', '예약 요청이 완료되었습니다.')
  `,
  )
    .bind(roomId)
    .run();

  return c.json(
    { reservation_id: reservationId, room_id: roomId, status: "REQUEST" },
    201,
  );
});

// 내 예약 목록 (최신순, 가게 이름 포함)
app.get("/api/users/:id/reservations", async (c) => {
  const userId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.reservation_id, r.user_id, r.pet_id, r.store_id,
           COALESCE(r.store_name, s.name) AS store_name, s.store_type,
           r.start_date, r.end_date, r.reservation_type, r.status, r.request_message, r.created_at
    FROM reservations r
    LEFT JOIN stores s ON s.store_id = r.store_id
    WHERE r.user_id = ?
    ORDER BY r.reservation_id DESC
  `,
  )
    .bind(userId)
    .all();
  return c.json(results);
});

// 예약 취소 — 상태만 CANCELED로 변경
app.patch("/api/reservations/:id/cancel", async (c) => {
  const reservationId = Number(c.req.param("id"));
  await c.env.DB.prepare(
    `UPDATE reservations SET status = 'CANCELED' WHERE reservation_id = ?`,
  )
    .bind(reservationId)
    .run();
  return c.json({ ok: true });
});

// 사장님 모드 — 확정 대기 중인(REQUEST) 예약 전체 조회
app.get("/api/reservations/pending", async (c) => {
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.reservation_id, r.user_id, r.pet_id, r.store_id,
           COALESCE(r.store_name, s.name) AS store_name, s.store_type,
           p.name AS pet_name,
           r.start_date, r.end_date, r.reservation_type, r.status, r.request_message, r.created_at
    FROM reservations r
    LEFT JOIN stores s ON s.store_id = r.store_id
    LEFT JOIN pets p ON p.pet_id = r.pet_id
    WHERE r.status = 'REQUEST'
    ORDER BY r.reservation_id DESC
  `,
  ).all();
  return c.json(results);
});

// 예약 확정 — 상태만 CONFIRMED로 변경
app.patch("/api/reservations/:id/confirm", async (c) => {
  const reservationId = Number(c.req.param("id"));
  await c.env.DB.prepare(
    `UPDATE reservations SET status = 'CONFIRMED' WHERE reservation_id = ?`,
  )
    .bind(reservationId)
    .run();
  return c.json({ ok: true });
});

app.get("/api/users/:id/pets", async (c) => {
  const userId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT pet_id, user_id, name, breed, age, weight, gender, note, image_url
    FROM pets WHERE user_id = ? ORDER BY pet_id DESC
  `,
  )
    .bind(userId)
    .all();
  return c.json(results);
});

app.get("/api/diaries/:reservationId", async (c) => {
  const reservationId = Number(c.req.param("reservationId"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT diary_id, reservation_id, store_id, content, media_type, created_at
    FROM diaries WHERE reservation_id = ? ORDER BY diary_id DESC
  `,
  )
    .bind(reservationId)
    .all();
  return c.json(results);
});

app.get("/api/chatrooms/:id/messages", async (c) => {
  const roomId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT message_id, room_id, sender_id, sender_name, message_type, content, created_at
    FROM chat_messages WHERE room_id = ? ORDER BY message_id ASC
  `,
  )
    .bind(roomId)
    .all();
  return c.json(results);
});

app.post("/api/chatrooms/:id/messages", async (c) => {
  const roomId = Number(c.req.param("id"));
  const body = await c.req.json<ChatMessageBody>();

  const senderId = body.sender_id ?? body.senderId ?? 1;
  const senderName = body.sender_name ?? body.senderName ?? "나";
  const messageType = body.message_type ?? body.messageType ?? "TEXT";
  const content = body.content?.trim();

  if (!content) return c.json({ message: "content is required" }, 400);

  const result = await c.env.DB.prepare(
    `
    INSERT INTO chat_messages (room_id, sender_id, sender_name, message_type, content)
    VALUES (?, ?, ?, ?, ?)
  `,
  )
    .bind(roomId, senderId, senderName, messageType, content)
    .run();

  const row = await c.env.DB.prepare(
    `
    SELECT message_id, room_id, sender_id, sender_name, message_type, content, created_at
    FROM chat_messages WHERE message_id = ?
  `,
  )
    .bind(result.meta.last_row_id)
    .first();

  return c.json(row, 201);
});

// 문의 방 조회 전용 (쓰기 없음): 있으면 room_id, 없으면 null
app.get("/api/chatrooms/lookup", async (c) => {
  const userId = Number(c.req.query("user_id") ?? "1");
  const storeKey = c.req.query("store_key") ?? "";
  const roomId = await findRoomId(c.env.DB, userId, storeKey);
  return c.json({ room_id: roomId });
});

// 문의 방 get-or-create (첫 메시지 전송 시 호출) — 자동 메시지 없음
app.post("/api/chatrooms", async (c) => {
  const body = await c.req.json<ChatRoomBody>();
  const userId = body.user_id ?? body.userId ?? 1;
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  const storeName = body.store_name ?? body.storeName ?? "";
  const storeAddress = body.store_address ?? body.storeAddress ?? "";

  const storeId = await resolveStoreId(c.env.DB, {
    storeId: body.store_id ?? body.storeId,
    storeKey,
    storeName,
    storeAddress,
  });
  const roomId = await getOrCreateRoom(c.env.DB, userId, storeId);

  return c.json(
    { room_id: roomId, store_id: storeId, store_name: storeName },
    201,
  );
});

// 내 채팅방 목록 (메시지가 1개 이상 있는 방만)
app.get("/api/users/:id/chatrooms", async (c) => {
  const userId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.room_id, r.store_id, s.name AS store_name,
           m.content AS last_message, m.created_at AS last_time
    FROM chat_rooms r
    LEFT JOIN stores s ON s.store_id = r.store_id
    LEFT JOIN chat_messages m ON m.message_id = (
      SELECT MAX(message_id) FROM chat_messages WHERE room_id = r.room_id
    )
    WHERE r.user_id = ?
      AND EXISTS (SELECT 1 FROM chat_messages m2 WHERE m2.room_id = r.room_id)
    ORDER BY m.message_id DESC
  `,
  )
    .bind(userId)
    .all();
  return c.json(results);
});

app.post("/api/reviews", async (c) => {
  const body = await c.req.json<ReviewBody>();
  const reservationId = body.reservation_id ?? body.reservationId;
  const userId = body.user_id ?? body.userId ?? 1;
  const storeId = body.store_id ?? body.storeId;
  const rating = Number(body.rating ?? 5);
  const revisit = (body.revisit ?? false) ? 1 : 0;
  const content = body.content ?? "";

  if (!reservationId || !storeId)
    return c.json({ message: "reservation_id and store_id are required" }, 400);

  const result = await c.env.DB.prepare(
    `
    INSERT INTO reviews (reservation_id, user_id, store_id, rating, revisit, content)
    VALUES (?, ?, ?, ?, ?, ?)
  `,
  )
    .bind(reservationId, userId, storeId, rating, revisit, content)
    .run();

  return c.json({ review_id: result.meta.last_row_id }, 201);
});

app.get("/api/stores/:id/reviews", async (c) => {
  const storeId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT review_id, reservation_id, user_id, store_id, rating, revisit, content, created_at
    FROM reviews
    WHERE store_id = ?
    ORDER BY review_id DESC
  `,
  )
    .bind(storeId)
    .all();

  return c.json(results);
});

// MARK: - 펫 특화 리뷰 (공공데이터 가게용, store_key = "이름|주소")

app.post("/api/pet-reviews", async (c) => {
  const body = await c.req.json<PetReviewBody>();
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  if (!storeKey) return c.json({ message: "store_key is required" }, 400);

  const storeName = body.store_name ?? body.storeName ?? "";
  const userName = body.user_name ?? body.userName ?? "익명";
  const rating = Number(body.rating ?? 5);
  const b = (v: unknown) => (v ? 1 : 0);

  const result = await c.env.DB.prepare(
    `
    INSERT INTO pet_reviews
      (store_key, store_name, user_name, rating, revisit, cctv, pickup, large_dog, separation_care, content)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `,
  )
    .bind(
      storeKey,
      storeName,
      userName,
      rating,
      b(body.revisit),
      b(body.cctv),
      b(body.pickup),
      b(body.large_dog),
      b(body.separation_care),
      body.content ?? "",
    )
    .run();

  return c.json({ id: result.meta.last_row_id }, 201);
});

// 특정 가게 리뷰 목록 + 요약(집계)
app.get("/api/pet-reviews", async (c) => {
  const storeKey = c.req.query("storeKey") ?? "";
  if (!storeKey) return c.json({ message: "storeKey is required" }, 400);

  const { results } = await c.env.DB.prepare(
    `
    SELECT id, store_key, store_name, user_name, rating, revisit,
           cctv, pickup, large_dog, separation_care, content, created_at
    FROM pet_reviews WHERE store_key = ? ORDER BY id DESC
  `,
  )
    .bind(storeKey)
    .all();

  const summary = await c.env.DB.prepare(
    `
    SELECT COUNT(*) AS count, AVG(rating) AS avg_rating,
           SUM(cctv) AS cctv, SUM(pickup) AS pickup,
           SUM(large_dog) AS large_dog, SUM(separation_care) AS separation_care
    FROM pet_reviews WHERE store_key = ?
  `,
  )
    .bind(storeKey)
    .first();

  return c.json({ summary, reviews: results });
});

// 모든 가게의 태그 집계 (필터용)
app.get("/api/pet-reviews/tags", async (c) => {
  const { results } = await c.env.DB.prepare(
    `
    SELECT store_key,
           COUNT(*) AS count, AVG(rating) AS avg_rating,
           SUM(cctv) AS cctv, SUM(pickup) AS pickup,
           SUM(large_dog) AS large_dog, SUM(separation_care) AS separation_care
    FROM pet_reviews GROUP BY store_key
  `,
  ).all();
  return c.json(results);
});

// MARK: - 인증

// 카카오 로그인: kakao_id로 기존 유저 조회 또는 신규 생성
app.post("/api/auth/kakao", async (c) => {
  const body = await c.req.json<KakaoAuthBody>();
  const { kakao_id, nickname, email } = body;

  if (!kakao_id || !nickname)
    return c.json({ message: "kakao_id and nickname are required" }, 400);

  const existing = await c.env.DB.prepare(
    `SELECT user_id, kakao_id, nickname, email, phone, address FROM users WHERE kakao_id = ?`,
  )
    .bind(kakao_id)
    .first();

  if (existing) return c.json(existing);

  const result = await c.env.DB.prepare(
    `INSERT INTO users (kakao_id, nickname, email) VALUES (?, ?, ?)`,
  )
    .bind(kakao_id, nickname, email ?? null)
    .run();

  const created = await c.env.DB.prepare(
    `SELECT user_id, kakao_id, nickname, email, phone, address FROM users WHERE user_id = ?`,
  )
    .bind(result.meta.last_row_id)
    .first();

  return c.json(created, 201);
});

// 유저 프로필 수정 (닉네임, 전화번호, 주소)
app.put("/api/users/:id", async (c) => {
  const userId = Number(c.req.param("id"));
  const body = await c.req.json<UpdateUserBody>();

  const fields: string[] = [];
  const values: unknown[] = [];

  if (body.nickname !== undefined) { fields.push("nickname = ?"); values.push(body.nickname); }
  if (body.phone !== undefined)    { fields.push("phone = ?");    values.push(body.phone); }
  if (body.address !== undefined)  { fields.push("address = ?");  values.push(body.address); }

  if (fields.length === 0) return c.json({ message: "nothing to update" }, 400);

  values.push(userId);
  await c.env.DB.prepare(`UPDATE users SET ${fields.join(", ")} WHERE user_id = ?`)
    .bind(...values)
    .run();

  const updated = await c.env.DB.prepare(
    `SELECT user_id, kakao_id, nickname, email, phone, address FROM users WHERE user_id = ?`,
  )
    .bind(userId)
    .first();

  // 존재하지 않는 유저면 null(200) 대신 404로 명확히 실패시킴
  if (!updated) return c.json({ message: "user not found" }, 404);
  return c.json(updated);
});

// MARK: - 강아지

// 강아지 등록
app.post("/api/users/:id/pets", async (c) => {
  const userId = Number(c.req.param("id"));
  const body = await c.req.json<CreatePetBody>();

  if (!body.name) return c.json({ message: "name is required" }, 400);

  const result = await c.env.DB.prepare(
    `INSERT INTO pets (user_id, name, breed, age, weight, gender, note)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      userId,
      body.name,
      body.breed ?? null,
      body.age ?? null,
      body.weight ?? null,
      body.gender ?? null,
      body.note ?? null,
    )
    .run();

  const created = await c.env.DB.prepare(
    `SELECT pet_id, user_id, name, breed, age, weight, gender, note FROM pets WHERE pet_id = ?`,
  )
    .bind(result.meta.last_row_id)
    .first();

  return c.json(created, 201);
});

// 강아지 삭제
app.delete("/api/pets/:petId", async (c) => {
  const petId = Number(c.req.param("petId"));
  await c.env.DB.prepare(`DELETE FROM pets WHERE pet_id = ?`).bind(petId).run();
  return c.json({ ok: true });
});

// MARK: - 찜한 가게 (favorites)

// 찜 추가: store_key로 stores upsert 후 (user_id, store_id) 등록.
// 찜 시점에 알게 된 전화·유형·좌표는 비어 있는 컬럼만 채움 (기존 값 보존)
app.post("/api/favorites", async (c) => {
  const body = await c.req.json<FavoriteBody>();
  const userId = body.user_id ?? body.userId;
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  if (!userId) return c.json({ message: "user_id is required" }, 400);
  if (!storeKey) return c.json({ message: "store_key is required" }, 400);

  const storeId = await resolveStoreId(c.env.DB, {
    storeKey,
    storeName: body.store_name ?? body.storeName,
    storeAddress: body.store_address ?? body.storeAddress,
  });

  await c.env.DB.prepare(
    `
    UPDATE stores SET
      phone      = COALESCE(NULLIF(phone, ''), ?),
      store_type = COALESCE(NULLIF(store_type, ''), ?),
      latitude   = COALESCE(latitude, ?),
      longitude  = COALESCE(longitude, ?)
    WHERE store_id = ?
  `,
  )
    .bind(
      body.phone ?? null,
      body.store_type ?? body.storeType ?? null,
      body.latitude ?? null,
      body.longitude ?? null,
      storeId,
    )
    .run();

  await c.env.DB.prepare(
    `INSERT OR IGNORE INTO favorites (user_id, store_id) VALUES (?, ?)`,
  )
    .bind(userId, storeId)
    .run();

  return c.json({ store_id: storeId, favorited: true }, 201);
});

// 찜 해제
app.delete("/api/users/:userId/favorites/:storeId", async (c) => {
  const userId = Number(c.req.param("userId"));
  const storeId = Number(c.req.param("storeId"));
  await c.env.DB.prepare(
    `DELETE FROM favorites WHERE user_id = ? AND store_id = ?`,
  )
    .bind(userId, storeId)
    .run();
  return c.json({ ok: true });
});

// 찜 목록 (최근 찜한 순)
app.get("/api/users/:id/favorites", async (c) => {
  const userId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT s.store_id, s.store_key, s.name, s.address, s.phone,
           s.store_type, s.latitude, s.longitude
    FROM favorites f
    JOIN stores s ON s.store_id = f.store_id
    WHERE f.user_id = ?
    ORDER BY f.favorite_id DESC
  `,
  )
    .bind(userId)
    .all();
  return c.json(results);
});

export default app;
