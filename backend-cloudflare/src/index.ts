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
  is_owner?: boolean;
  isOwner?: boolean;
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

type StoreClaimBody = {
  user_id?: number;
  userId?: number;
  store_key?: string;
  storeKey?: string;
  store_name?: string;
  storeName?: string;
  store_address?: string;
  storeAddress?: string;
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

// 사장님-가게 연결: 가게 상세의 "내 가게로 등록" — store_key 업서트 후 owner_id 지정
app.post("/api/stores/claim", async (c) => {
  const body = await c.req.json<StoreClaimBody>();
  const userId = body.user_id ?? body.userId;
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  if (!userId || !storeKey)
    return c.json({ message: "user_id/store_key is required" }, 400);

  const storeId = await resolveStoreId(c.env.DB, {
    storeKey,
    storeName: body.store_name ?? body.storeName ?? "",
    storeAddress: body.store_address ?? body.storeAddress ?? "",
  });

  const store = await c.env.DB.prepare(
    `SELECT owner_id FROM stores WHERE store_id = ?`,
  )
    .bind(storeId)
    .first<{ owner_id: number | null }>();
  if (store?.owner_id && store.owner_id !== userId)
    return c.json({ message: "already claimed by another owner" }, 409);

  await c.env.DB.prepare(`UPDATE stores SET owner_id = ? WHERE store_id = ?`)
    .bind(userId, storeId)
    .run();
  return c.json({ store_id: storeId, owner_id: userId }, 201);
});

// 사장님이 등록한 내 가게 목록
app.get("/api/owners/:id/stores", async (c) => {
  const ownerId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `SELECT store_id, store_key, name, address FROM stores WHERE owner_id = ? ORDER BY store_id DESC`,
  )
    .bind(ownerId)
    .all();
  return c.json(results);
});

// 내 가게 등록 해제 — 본인 소유일 때만 owner_id를 비운다 (잘못 등록 시 복구 경로)
app.delete("/api/owners/:id/stores/:storeId", async (c) => {
  const ownerId = Number(c.req.param("id"));
  const storeId = Number(c.req.param("storeId"));
  await c.env.DB.prepare(
    `UPDATE stores SET owner_id = NULL WHERE store_id = ? AND owner_id = ?`,
  )
    .bind(storeId, ownerId)
    .run();
  return c.json({ ok: true });
});

// 사장님 문의함: 내 가게로 온 채팅방 목록 (메시지가 1개 이상 있는 방만, 손님 닉네임 포함)
app.get("/api/owners/:id/chatrooms", async (c) => {
  const ownerId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.room_id, r.store_id, s.name AS store_name,
           u.nickname AS customer_name,
           m.content AS last_message, m.created_at AS last_time
    FROM chat_rooms r
    JOIN stores s ON s.store_id = r.store_id AND s.owner_id = ?
    LEFT JOIN users u ON u.user_id = r.user_id
    LEFT JOIN chat_messages m ON m.message_id = (
      SELECT MAX(message_id) FROM chat_messages WHERE room_id = r.room_id
    )
    WHERE EXISTS (SELECT 1 FROM chat_messages m2 WHERE m2.room_id = r.room_id)
    ORDER BY m.message_id DESC
  `,
  )
    .bind(ownerId)
    .all();
  return c.json(results);
});

app.post("/api/reservations", async (c) => {
  const body = await c.req.json<ReservationBody>();
  // 값 누락 시 user 1로 조용히 귀속되던 폴백 제거 — 사용자별 데이터 분리
  const userId = body.user_id ?? body.userId;
  const petId = body.pet_id ?? body.petId;
  if (!userId || !petId)
    return c.json({ message: "user_id/pet_id is required" }, 400);
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
           p.name AS pet_name,
           r.start_date, r.end_date, r.reservation_type, r.status, r.request_message, r.created_at
    FROM reservations r
    LEFT JOIN stores s ON s.store_id = r.store_id
    LEFT JOIN pets p ON p.pet_id = r.pet_id
    WHERE r.user_id = ?
    ORDER BY r.reservation_id DESC
  `,
  )
    .bind(userId)
    .all();
  return c.json(results);
});

// 예약 취소 — 상태를 CANCELED로 변경.
// 사장님 취소(by_owner)면 고객이 상태 변경을 알 수 있게 채팅방에 자동 메시지를 남긴다
// (고객 본인 취소는 바디 없이 호출되므로 메시지를 보내지 않는다)
type ReservationCancelBody = {
  by_owner?: boolean;
  byOwner?: boolean;
};

app.patch("/api/reservations/:id/cancel", async (c) => {
  const reservationId = Number(c.req.param("id"));
  const body = await c.req
    .json<ReservationCancelBody>()
    .catch(() => ({}) as ReservationCancelBody);
  const byOwner = body.by_owner ?? body.byOwner ?? false;

  await c.env.DB.prepare(
    `UPDATE reservations SET status = 'CANCELED' WHERE reservation_id = ?`,
  )
    .bind(reservationId)
    .run();

  if (byOwner) {
    const target = await c.env.DB.prepare(
      `
      SELECT cr.room_id, COALESCE(r.store_name, s.name) AS store_name, r.start_date
      FROM reservations r
      LEFT JOIN stores s ON s.store_id = r.store_id
      JOIN chat_rooms cr ON cr.user_id = r.user_id AND cr.store_id = r.store_id
      WHERE r.reservation_id = ?
    `,
    )
      .bind(reservationId)
      .first<{ room_id: number; store_name: string; start_date: string }>();
    if (target) {
      await c.env.DB.prepare(
        `
        INSERT INTO chat_messages (room_id, sender_id, sender_name, message_type, content)
        VALUES (?, 0, '맡겨멍', 'AUTO', ?)
      `,
      )
        .bind(
          target.room_id,
          `가게 사정으로 ${target.store_name} 예약(${target.start_date})이 취소되었어요. 예약 내역에서 확인해주세요`,
        )
        .run();
    }
  }
  return c.json({ ok: true });
});

// 사장님 모드 — 확정 대기 중인(REQUEST) 예약 전체 조회
// 사장님이 받은 예약 요청 — 내 가게(owner_id)로 온 REQUEST만
app.get("/api/owners/:id/reservations/pending", async (c) => {
  const ownerId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.reservation_id, r.user_id, r.pet_id, r.store_id,
           COALESCE(r.store_name, s.name) AS store_name, s.store_type,
           p.name AS pet_name, p.breed AS pet_breed, p.age AS pet_age,
           p.weight AS pet_weight, p.gender AS pet_gender, p.note AS pet_note,
           u.nickname AS user_name, u.phone AS user_phone, u.address AS user_address,
           r.start_date, r.end_date, r.reservation_type, r.status, r.request_message, r.created_at
    FROM reservations r
    JOIN stores s ON s.store_id = r.store_id AND s.owner_id = ?
    LEFT JOIN pets p ON p.pet_id = r.pet_id
    LEFT JOIN users u ON u.user_id = r.user_id
    WHERE r.status = 'REQUEST'
    ORDER BY r.reservation_id DESC
  `,
  )
    .bind(ownerId)
    .all();
  return c.json(results);
});

// 사장님 알림장 — 내 가게(owner_id)로 온 확정(CONFIRMED) 예약(맡은 아이들)
app.get("/api/owners/:id/reservations/confirmed", async (c) => {
  const ownerId = Number(c.req.param("id"));
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.reservation_id, r.user_id, r.pet_id, r.store_id,
           COALESCE(r.store_name, s.name) AS store_name, s.store_type,
           p.name AS pet_name, p.breed AS pet_breed, p.age AS pet_age,
           p.weight AS pet_weight, p.gender AS pet_gender, p.note AS pet_note,
           u.nickname AS user_name, u.phone AS user_phone, u.address AS user_address,
           r.start_date, r.end_date, r.reservation_type, r.status, r.request_message, r.created_at
    FROM reservations r
    JOIN stores s ON s.store_id = r.store_id AND s.owner_id = ?
    LEFT JOIN pets p ON p.pet_id = r.pet_id
    LEFT JOIN users u ON u.user_id = r.user_id
    WHERE r.status = 'CONFIRMED'
    ORDER BY r.reservation_id DESC
  `,
  )
    .bind(ownerId)
    .all();
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

// MARK: - 알림장(diary)
// 예약 1건에 타임라인 엔트리 여러 개. 사진(diary_photos)은 R2 활성화 후 채워지며 지금은 항상 빈 배열.

type DiaryBody = { content?: string };
type DiaryRow = {
  diary_id: number;
  reservation_id: number;
  store_id: number | null;
  content: string;
  created_at: string;
};
type DiaryPhotoOut = { photo_id: number; url: string };

// 타임라인 조회 — 엔트리를 시간순으로, 각 엔트리에 사진 배열을 매달아 반환
app.get("/api/reservations/:id/diaries", async (c) => {
  const reservationId = Number(c.req.param("id"));
  const { results: entries } = await c.env.DB.prepare(
    `SELECT diary_id, reservation_id, store_id, content, created_at
     FROM diaries WHERE reservation_id = ? ORDER BY diary_id ASC`,
  )
    .bind(reservationId)
    .all<DiaryRow>();

  const { results: photos } = await c.env.DB.prepare(
    `SELECT p.photo_id, p.diary_id, p.r2_key
     FROM diary_photos p
     JOIN diaries d ON d.diary_id = p.diary_id
     WHERE d.reservation_id = ?
     ORDER BY p.sort_order ASC, p.photo_id ASC`,
  )
    .bind(reservationId)
    .all<{ photo_id: number; diary_id: number; r2_key: string }>();

  const byDiary = new Map<number, DiaryPhotoOut[]>();
  for (const ph of photos) {
    const arr = byDiary.get(ph.diary_id) ?? [];
    arr.push({ photo_id: ph.photo_id, url: `/api/diaries/photos/${ph.r2_key}` });
    byDiary.set(ph.diary_id, arr);
  }
  return c.json(
    entries.map((e) => ({ ...e, photos: byDiary.get(e.diary_id) ?? [] })),
  );
});

// 엔트리 생성 — 성공 시 보호자 채팅방에 새 알림장 도착 자동 메시지(sender 0)
app.post("/api/reservations/:id/diaries", async (c) => {
  const reservationId = Number(c.req.param("id"));
  const body = await c.req.json<DiaryBody>().catch(() => ({}) as DiaryBody);
  const content = body.content?.trim();
  if (!content) return c.json({ message: "content is required" }, 400);

  const r = await c.env.DB.prepare(
    `SELECT r.user_id, r.store_id, COALESCE(r.store_name, s.name) AS store_name, p.name AS pet_name
     FROM reservations r
     LEFT JOIN stores s ON s.store_id = r.store_id
     LEFT JOIN pets p ON p.pet_id = r.pet_id
     WHERE r.reservation_id = ?`,
  )
    .bind(reservationId)
    .first<{
      user_id: number;
      store_id: number;
      store_name: string;
      pet_name: string | null;
    }>();
  if (!r) return c.json({ message: "reservation not found" }, 404);

  const inserted = await c.env.DB.prepare(
    `INSERT INTO diaries (reservation_id, store_id, content) VALUES (?, ?, ?)`,
  )
    .bind(reservationId, r.store_id, content)
    .run();
  const diaryId = inserted.meta.last_row_id;

  const room = await c.env.DB.prepare(
    `SELECT room_id FROM chat_rooms WHERE user_id = ? AND store_id = ?`,
  )
    .bind(r.user_id, r.store_id)
    .first<{ room_id: number }>();
  if (room) {
    const petName = r.pet_name ?? "우리 아이";
    await c.env.DB.prepare(
      `INSERT INTO chat_messages (room_id, sender_id, sender_name, message_type, content)
       VALUES (?, 0, '맡겨멍', 'AUTO', ?)`,
    )
      .bind(
        room.room_id,
        `${petName}의 새 알림장이 도착했어요\n예약 내역에서 확인해주세요`,
      )
      .run();
  }

  const created = await c.env.DB.prepare(
    `SELECT diary_id, reservation_id, store_id, content, created_at FROM diaries WHERE diary_id = ?`,
  )
    .bind(diaryId)
    .first<DiaryRow>();
  if (!created) return c.json({ message: "insert failed" }, 500);
  return c.json({ ...created, photos: [] as DiaryPhotoOut[] });
});

// 엔트리 수정 — 글만 갱신(자동 메시지 없음). 사진 편집은 R2 도입 시 추가.
app.patch("/api/diaries/:diaryId", async (c) => {
  const diaryId = Number(c.req.param("diaryId"));
  const body = await c.req.json<DiaryBody>().catch(() => ({}) as DiaryBody);
  const content = body.content?.trim();
  if (!content) return c.json({ message: "content is required" }, 400);

  await c.env.DB.prepare(`UPDATE diaries SET content = ? WHERE diary_id = ?`)
    .bind(content, diaryId)
    .run();

  const updated = await c.env.DB.prepare(
    `SELECT diary_id, reservation_id, store_id, content, created_at FROM diaries WHERE diary_id = ?`,
  )
    .bind(diaryId)
    .first<DiaryRow>();
  if (!updated) return c.json({ message: "diary not found" }, 404);
  return c.json({ ...updated, photos: [] as DiaryPhotoOut[] });
});

// 엔트리 삭제(자동 메시지 없음) — 사진 행도 함께 정리(R2 객체 삭제는 R2 도입 시 추가)
app.delete("/api/diaries/:diaryId", async (c) => {
  const diaryId = Number(c.req.param("diaryId"));
  await c.env.DB.prepare(`DELETE FROM diary_photos WHERE diary_id = ?`)
    .bind(diaryId)
    .run();
  await c.env.DB.prepare(`DELETE FROM diaries WHERE diary_id = ?`)
    .bind(diaryId)
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

  const senderId = body.sender_id ?? body.senderId;
  if (senderId === undefined)
    return c.json({ message: "sender_id is required" }, 400);
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
  const rawUserId = c.req.query("user_id");
  if (!rawUserId) return c.json({ message: "user_id is required" }, 400);
  const userId = Number(rawUserId);
  const storeKey = c.req.query("store_key") ?? "";
  const roomId = await findRoomId(c.env.DB, userId, storeKey);
  return c.json({ room_id: roomId });
});

// 문의 방 get-or-create (첫 메시지 전송 시 호출) — 자동 메시지 없음
app.post("/api/chatrooms", async (c) => {
  const body = await c.req.json<ChatRoomBody>();
  const userId = body.user_id ?? body.userId;
  if (!userId) return c.json({ message: "user_id is required" }, 400);
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
    SELECT r.room_id, r.store_id, s.name AS store_name, s.store_type,
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

// MARK: - 안 읽은 채팅 (홈 종 아이콘 빨간 점)

// 읽음 처리 — 방을 열람한 시점의 마지막 메시지까지 읽음으로 기록
type ChatReadBody = {
  user_id?: number;
  userId?: number;
};

app.post("/api/chatrooms/:id/read", async (c) => {
  const roomId = Number(c.req.param("id"));
  const body = await c.req.json<ChatReadBody>();
  const userId = body.user_id ?? body.userId;
  if (!userId) return c.json({ message: "user_id is required" }, 400);

  await c.env.DB.prepare(
    `
    INSERT INTO chat_room_reads (room_id, user_id, last_read_message_id)
    VALUES (?, ?, (SELECT COALESCE(MAX(message_id), 0) FROM chat_messages WHERE room_id = ?))
    ON CONFLICT(room_id, user_id) DO UPDATE SET last_read_message_id = excluded.last_read_message_id
  `,
  )
    .bind(roomId, userId, roomId)
    .run();
  return c.json({ ok: true });
});

// 안 읽은 메시지 수 — 손님 시점(내가 손님인 방들의 상대·자동 메시지)은 모든 계정 공통.
// 사장님 계정은 손님 역할도 겸하므로(다른 가게에 예약·문의 가능) 내 가게로 온 손님 메시지를
// 합산한다(자동 메시지 sender 0은 사장님 화면에선 내 말풍선이라 사장님 몫에선 제외)
app.get("/api/users/:id/unread-count", async (c) => {
  const userId = Number(c.req.param("id"));
  const user = await c.env.DB.prepare(
    `SELECT is_owner FROM users WHERE user_id = ?`,
  )
    .bind(userId)
    .first<{ is_owner: number | null }>();

  const asCustomer = await c.env.DB.prepare(
    `
    SELECT COUNT(*) AS unread
    FROM chat_messages m
    JOIN chat_rooms r ON r.room_id = m.room_id AND r.user_id = ?
    LEFT JOIN chat_room_reads rd ON rd.room_id = m.room_id AND rd.user_id = ?
    WHERE m.sender_id != ?
      AND m.message_id > COALESCE(rd.last_read_message_id, 0)
  `,
  )
    .bind(userId, userId, userId)
    .first<{ unread: number }>();
  let unread = asCustomer?.unread ?? 0;

  if ((user?.is_owner ?? 0) === 1) {
    const asOwner = await c.env.DB.prepare(
      `
      SELECT COUNT(*) AS unread
      FROM chat_messages m
      JOIN chat_rooms r ON r.room_id = m.room_id AND r.user_id != ?
      JOIN stores s ON s.store_id = r.store_id AND s.owner_id = ?
      LEFT JOIN chat_room_reads rd ON rd.room_id = m.room_id AND rd.user_id = ?
      WHERE m.sender_id != ? AND m.sender_id != 0
        AND m.message_id > COALESCE(rd.last_read_message_id, 0)
    `,
    )
      .bind(userId, userId, userId, userId)
      .first<{ unread: number }>();
    unread += asOwner?.unread ?? 0;
  }

  return c.json({ unread });
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
  const isOwner = (body.is_owner ?? body.isOwner ?? false) ? 1 : 0;

  if (!kakao_id || !nickname)
    return c.json({ message: "kakao_id and nickname are required" }, 400);

  const existing = await c.env.DB.prepare(
    `SELECT user_id, kakao_id, nickname, email, phone, address, is_owner FROM users WHERE kakao_id = ?`,
  )
    .bind(kakao_id)
    .first<{
      user_id: number;
      kakao_id: string;
      nickname: string;
      email: string | null;
      phone: string | null;
      address: string | null;
      is_owner: number | null;
    }>();

  if (existing) {
    // 역할은 최초 가입 시 계정에 귀속 — 같은 카카오 계정으로 다른 역할 가입 불가 (탈퇴 전까지)
    if ((existing.is_owner ?? 0) !== isOwner)
      return c.json(
        {
          message: "already registered with a different role",
          is_owner: existing.is_owner ?? 0,
        },
        409,
      );
    return c.json(existing);
  }

  const result = await c.env.DB.prepare(
    `INSERT INTO users (kakao_id, nickname, email, is_owner) VALUES (?, ?, ?, ?)`,
  )
    .bind(kakao_id, nickname, email ?? null, isOwner)
    .run();

  const created = await c.env.DB.prepare(
    `SELECT user_id, kakao_id, nickname, email, phone, address, is_owner FROM users WHERE user_id = ?`,
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

// MARK: - 리뷰 요청 자동 메시지 (이용일 다음날, Cron Trigger)

// KST 기준 어제 — 신형 start_date("2026-07-12 (일) 14:00")는 연·월·일 정확 대조(iso),
// 구형("토 7/12 14:00", 연도 없음)은 월/일 문자열 대조(monthDay)로 계속 처리한다
function kstYesterday(): { iso: string; monthDay: string } {
  const kst = new Date(Date.now() + 9 * 60 * 60 * 1000 - 24 * 60 * 60 * 1000);
  const month = kst.getUTCMonth() + 1;
  const day = kst.getUTCDate();
  const iso = `${kst.getUTCFullYear()}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
  return { iso, monthDay: `${month}/${day}` };
}

type ReviewRequestTarget = {
  reservation_id: number;
  room_id: number;
  store_name: string;
};

// 어제가 이용일이었던 확정(CONFIRMED) 예약의 채팅방에 리뷰 요청 자동 메시지를 1회 보낸다
async function sendReviewRequests(db: D1Database): Promise<number> {
  const { iso, monthDay } = kstYesterday();
  const { results } = await db
    .prepare(
      `
    SELECT r.reservation_id, c.room_id, s.name AS store_name
    FROM reservations r
    JOIN stores s ON s.store_id = r.store_id
    JOIN chat_rooms c ON c.user_id = r.user_id AND c.store_id = r.store_id
    WHERE r.status = 'CONFIRMED'
      AND r.review_requested = 0
      AND (r.start_date LIKE ? OR r.start_date LIKE ?)
  `,
    )
    .bind(`${iso}%`, `% ${monthDay} %`)
    .all<ReviewRequestTarget>();

  for (const target of results) {
    await db
      .prepare(
        `
      INSERT INTO chat_messages (room_id, sender_id, sender_name, message_type, content)
      VALUES (?, 0, '맡겨멍', 'AUTO', ?)
    `,
      )
      .bind(
        target.room_id,
        `어제 ${target.store_name} 이용은 어떠셨나요? 가게 상세에서 리뷰를 남겨주시면 다른 보호자들에게 큰 도움이 돼요`,
      )
      .run();
    await db
      .prepare(
        `UPDATE reservations SET review_requested = 1 WHERE reservation_id = ?`,
      )
      .bind(target.reservation_id)
      .run();
  }
  return results.length;
}

// 데모·테스트용 수동 트리거 — 실서비스에선 매일 KST 18시 Cron이 자동 실행
app.post("/api/internal/review-requests", async (c) => {
  const sent = await sendReviewRequests(c.env.DB);
  return c.json({ sent });
});

export default {
  fetch: app.fetch,
  scheduled: async (
    _event: ScheduledEvent,
    env: Bindings,
    _ctx: ExecutionContext,
  ) => {
    await sendReviewRequests(env.DB);
  },
};
