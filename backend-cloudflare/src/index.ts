import { Hono } from "hono";
import { cors } from "hono/cors";
import { refreshStaleStoreDetails } from "./storeDetailRefresh";

const REVIEW_REQUEST_CRON = "0 9 * * *";
const STORE_DETAIL_REFRESH_CRON = "17 */4 * * *";

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
  user_id?: number;
  userId?: number;
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

type ReviewEligibility = {
  eligible: boolean;
  reason:
    | "eligible"
    | "already_reviewed"
    | "no_completed_reservation"
    | "partner_required";
  reservation_id: number | null;
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

type SupportMessageBody = {
  content?: string;
};

type KakaoAuthBody = {
  access_token?: string;
  accessToken?: string;
  is_owner?: boolean;
  isOwner?: boolean;
};

type DevAuthBody = {
  nickname?: string;
  identity?: string;
  is_owner?: boolean;
  isOwner?: boolean;
  is_admin?: boolean;
  isAdmin?: boolean;
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

type StoreDetailImportBody = {
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
  open_time?: string;
  openTime?: string;
  price_info?: string;
  priceInfo?: string;
  image_url?: string;
  imageUrl?: string;
  image_urls?: string[];
  imageUrls?: string[];
  pickup?: boolean | number;
  playground?: boolean | number;
  large_dog?: boolean | number;
  largeDog?: boolean | number;
};

type CreatePetBody = {
  name: string;
  breed?: string;
  age?: number;
  weight?: number;
  gender?: string;
  note?: string;
  image_url?: string;
  imageUrl?: string;
};

// @cloudflare/workers-types 미설치 환경(로컬 node_modules 손상)에서도 타입체크가 되도록
// Workers AI 바인딩에서 실제로 쓰는 부분만 최소 타입으로 직접 선언한다.
type WorkersAiBinding = {
  run: (
    model: string,
    input: { image: number[]; prompt: string; max_tokens?: number },
  ) => Promise<{ description?: string; response?: string }>;
};

type Bindings = {
  DB: D1Database;
  APP_NAME: string;
  AI: WorkersAiBinding;
  INTERNAL_API_KEY?: string;
  ALLOW_DEV_AUTH?: string;
  NAVER_PLACE_REFRESH_ENABLED?: string;
  EXPOSE_UNVERIFIED_STORE_DETAILS?: string;
  NAVER_API_HUB_CLIENT_ID?: string;
  NAVER_API_HUB_CLIENT_SECRET?: string;
  KAKAO_REST_API_KEY?: string;
  DATA_GO_KR_SERVICE_KEY?: string;
};

type Variables = {
  authUserId: number;
  authIsOwner: boolean;
  authIsAdmin: boolean;
  authTokenHash: string;
};

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();
app.use(
  "*",
  cors({
    allowHeaders: ["Content-Type", "Authorization", "X-Internal-Key"],
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  }),
);

const SESSION_DAYS = 30;

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

async function createSession(
  db: D1Database,
  userId: number,
): Promise<{ token: string; expiresAt: string }> {
  const random = new Uint8Array(32);
  crypto.getRandomValues(random);
  const token = toBase64Url(random);
  const tokenHash = await hashToken(token);
  const expiresAt = new Date(
    Date.now() + SESSION_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();

  await db
    .prepare(
      `INSERT INTO auth_sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)`,
    )
    .bind(tokenHash, userId, expiresAt)
    .run();
  return { token, expiresAt };
}

function isPublicAPI(method: string, path: string): boolean {
  if (method === "OPTIONS") return true;
  if (method === "POST" && path === "/api/auth/kakao") return true;
  if (method === "POST" && path === "/api/auth/dev") return true;
  if (method !== "GET") return false;
  if (path === "/api/stores" || path === "/api/stores/detail") return true;
  if (path === "/api/notices" || /^\/api\/notices\/\d+$/.test(path)) return true;
  if (path === "/api/pet-reviews" || path === "/api/pet-reviews/tags") return true;
  return false;
}

function isInternalAPI(path: string): boolean {
  return path.startsWith("/api/internal/") || path.startsWith("/api/admin/");
}

app.use("/api/*", async (c, next) => {
  const path = c.req.path;
  const method = c.req.method.toUpperCase();

  if (isPublicAPI(method, path)) {
    await next();
    return;
  }

  if (isInternalAPI(path)) {
    const configured = c.env.INTERNAL_API_KEY;
    const supplied = c.req.header("X-Internal-Key");
    if (!configured) return c.json({ message: "internal API is disabled" }, 503);
    if (!supplied || supplied !== configured)
      return c.json({ message: "unauthorized" }, 401);
    await next();
    return;
  }

  const authorization = c.req.header("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return c.json({ message: "authentication required" }, 401);

  const tokenHash = await hashToken(match[1]);
  const session = await c.env.DB.prepare(
    `SELECT s.user_id, u.is_owner, u.is_admin
     FROM auth_sessions s
     JOIN users u ON u.user_id = s.user_id
     WHERE s.token_hash = ?
       AND u.deleted_at IS NULL
       AND unixepoch(s.expires_at) > unixepoch('now')`,
  )
    .bind(tokenHash)
    .first<{
      user_id: number;
      is_owner: number | null;
      is_admin: number | null;
    }>();
  if (!session) return c.json({ message: "invalid or expired session" }, 401);

  c.set("authUserId", session.user_id);
  c.set("authIsOwner", (session.is_owner ?? 0) === 1);
  c.set("authIsAdmin", (session.is_admin ?? 0) === 1);
  c.set("authTokenHash", tokenHash);
  await next();
});

function sameUser(authUserId: number, requestedUserId: number): boolean {
  return Number.isInteger(requestedUserId) && requestedUserId === authUserId;
}

async function hasActiveSupportAdmin(db: D1Database): Promise<boolean> {
  const row = await db.prepare(
    `SELECT 1 AS available
     FROM users
     WHERE is_admin = 1 AND deleted_at IS NULL
     LIMIT 1`,
  ).first<{ available: number }>();
  return row?.available === 1;
}

async function canAccessSupportConversation(
  db: D1Database,
  conversationId: number,
  authUserId: number,
  authIsAdmin: boolean,
): Promise<boolean> {
  if (!Number.isInteger(conversationId) || conversationId <= 0) return false;
  if (authIsAdmin) {
    const row = await db.prepare(
      `SELECT conversation_id FROM support_conversations WHERE conversation_id = ?`,
    ).bind(conversationId).first();
    return Boolean(row);
  }
  const row = await db.prepare(
    `SELECT conversation_id
     FROM support_conversations
     WHERE conversation_id = ? AND user_id = ?`,
  ).bind(conversationId, authUserId).first();
  return Boolean(row);
}

type StoreCapabilityRow = {
  store_id: number;
  owner_id: number | null;
  partner_status: string;
  is_partner: number;
  can_book: number;
  can_chat: number;
  can_diary: number;
  can_review: number;
};

async function findStoreCapabilities(
  db: D1Database,
  opts: { storeId?: number; storeKey?: string },
): Promise<StoreCapabilityRow | null> {
  const storeId = opts.storeId;
  const storeKey = (opts.storeKey ?? "").trim();
  if (!storeId && !storeKey) return null;
  return db.prepare(
    `SELECT s.store_id, s.owner_id, s.partner_status,
            c.is_partner, c.can_book, c.can_chat, c.can_diary, c.can_review
     FROM stores s
     JOIN store_capabilities c ON c.store_id = s.store_id
     WHERE ${storeId ? "s.store_id = ?" : "s.store_key = ?"}
     LIMIT 1`,
  )
    .bind(storeId ?? storeKey)
    .first<StoreCapabilityRow>();
}

function storeAPIResponse(
  row: Record<string, unknown>,
  images: unknown[] = [],
  exposeUnverifiedDetails = false,
): Record<string, unknown> {
  const isPartner = Number(row.is_partner ?? 0) === 1;
  const canExposeDetails = isPartner && exposeUnverifiedDetails;
  return {
    ...row,
    open_time: canExposeDetails ? row.open_time : null,
    pickup: canExposeDetails ? row.pickup : null,
    playground: canExposeDetails ? row.playground : null,
    large_dog: canExposeDetails ? row.large_dog : null,
    price_info: canExposeDetails ? row.price_info : null,
    image_url: canExposeDetails ? row.image_url : null,
    images: canExposeDetails ? images : [],
    is_partner: isPartner,
    can_book: Number(row.can_book ?? 0) === 1,
    can_chat: Number(row.can_chat ?? 0) === 1,
    can_diary: Number(row.can_diary ?? 0) === 1,
    can_review: Number(row.can_review ?? 0) === 1,
  };
}

type EnrichmentStoreRow = {
  store_id: number;
  name: string;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  is_partner: number;
};

type PlaceEnrichment = {
  road_address: string;
  address: string;
  phone: string;
  place_url: string;
};

type BlogEnrichment = {
  title: string;
  snippet: string;
  link: string;
  blogger: string;
  date: string;
};

async function findEnrichmentStore(
  db: D1Database,
  storeKey: string,
): Promise<EnrichmentStoreRow | null> {
  return db.prepare(
    `SELECT s.store_id, s.name, s.address, s.latitude, s.longitude, c.is_partner
     FROM stores s
     JOIN store_capabilities c ON c.store_id = s.store_id
     WHERE s.store_key = ?
     LIMIT 1`,
  )
    .bind(storeKey)
    .first<EnrichmentStoreRow>();
}

async function readEnrichmentCache<T>(
  db: D1Database,
  storeId: number,
  kind: "PLACE" | "BLOGS",
): Promise<T | null> {
  const row = await db.prepare(
    `SELECT payload FROM store_enrichment_cache
     WHERE store_id = ? AND kind = ?
       AND unixepoch(expires_at) > unixepoch('now')`,
  )
    .bind(storeId, kind)
    .first<{ payload: string }>();
  if (!row) return null;
  try {
    return JSON.parse(row.payload) as T;
  } catch {
    await db.prepare(
      `DELETE FROM store_enrichment_cache WHERE store_id = ? AND kind = ?`,
    )
      .bind(storeId, kind)
      .run();
    return null;
  }
}

async function writeEnrichmentCache(
  db: D1Database,
  storeId: number,
  kind: "PLACE" | "BLOGS",
  payload: unknown,
  ttlSeconds: number,
): Promise<void> {
  await db.prepare(
    `INSERT INTO store_enrichment_cache
       (store_id, kind, payload, fetched_at, expires_at)
     VALUES (?, ?, ?, CURRENT_TIMESTAMP, datetime('now', ?))
     ON CONFLICT(store_id, kind) DO UPDATE SET
       payload = excluded.payload,
       fetched_at = excluded.fetched_at,
       expires_at = excluded.expires_at`,
  )
    .bind(storeId, kind, JSON.stringify(payload), `+${ttlSeconds} seconds`)
    .run();
}

function stripSearchHTML(value: string): string {
  let result = value.replace(/<[^>]+>/g, "");
  const entities: Record<string, string> = {
    "&amp;": "&",
    "&lt;": "<",
    "&gt;": ">",
    "&quot;": '"',
    "&#39;": "'",
    "&nbsp;": " ",
  };
  for (const [encoded, decoded] of Object.entries(entities)) {
    result = result.replaceAll(encoded, decoded);
  }
  return result.trim();
}

function distanceMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const dLat = (lat2 - lat1) * 111_000;
  const dLon = (lon2 - lon1) * 88_800;
  return Math.sqrt(dLat * dLat + dLon * dLon);
}

async function fetchNaverPlace(
  env: Bindings,
  store: EnrichmentStoreRow,
): Promise<Pick<PlaceEnrichment, "road_address" | "address"> | null> {
  const id = env.NAVER_API_HUB_CLIENT_ID;
  const secret = env.NAVER_API_HUB_CLIENT_SECRET;
  if (!id || !secret || store.latitude === null || store.longitude === null)
    return null;

  const region = (store.address ?? "").split(/\s+/).slice(0, 2).join(" ");
  const queries = [region ? `${region} ${store.name}` : store.name, store.name];
  for (const query of [...new Set(queries)]) {
    const url = new URL("https://naverapihub.apigw.ntruss.com/search/v1/local");
    url.searchParams.set("query", query);
    url.searchParams.set("display", "5");
    try {
      const response = await fetch(url.toString(), {
        headers: {
          "X-NCP-APIGW-API-KEY-ID": id,
          "X-NCP-APIGW-API-KEY": secret,
        },
        signal: AbortSignal.timeout(8_000),
      });
      if (!response.ok) continue;
      const body = await response.json<{
        items?: Array<{
          roadAddress?: string;
          address?: string;
          mapx?: string;
          mapy?: string;
        }>;
      }>();
      const nearest = (body.items ?? [])
        .map((item) => {
          const longitude = Number(item.mapx ?? "") / 1e7;
          const latitude = Number(item.mapy ?? "") / 1e7;
          return {
            item,
            distance: Number.isFinite(latitude) && Number.isFinite(longitude)
              ? distanceMeters(store.latitude!, store.longitude!, latitude, longitude)
              : Number.POSITIVE_INFINITY,
          };
        })
        .filter((candidate) => candidate.distance <= 3_000)
        .sort((a, b) => a.distance - b.distance)[0];
      if (nearest) {
        return {
          road_address: nearest.item.roadAddress ?? "",
          address: nearest.item.address ?? "",
        };
      }
    } catch {
      // 공급자 오류·요청 URL·Secret은 응답이나 로그로 전달하지 않는다.
    }
  }
  return null;
}

async function fetchKakaoPlace(
  env: Bindings,
  store: EnrichmentStoreRow,
): Promise<PlaceEnrichment | null> {
  const key = env.KAKAO_REST_API_KEY;
  if (!key || store.latitude === null || store.longitude === null) return null;
  const headers = { Authorization: `KakaoAK ${key}` };
  try {
    const keywordURL = new URL("https://dapi.kakao.com/v2/local/search/keyword.json");
    keywordURL.searchParams.set("query", store.name);
    keywordURL.searchParams.set("x", String(store.longitude));
    keywordURL.searchParams.set("y", String(store.latitude));
    keywordURL.searchParams.set("radius", "1000");
    keywordURL.searchParams.set("sort", "distance");
    const keywordResponse = await fetch(keywordURL.toString(), {
      headers,
      signal: AbortSignal.timeout(8_000),
    });
    if (keywordResponse.ok) {
      const body = await keywordResponse.json<{
        documents?: Array<{
          address_name?: string;
          road_address_name?: string;
          phone?: string;
          place_url?: string;
        }>;
      }>();
      const first = body.documents?.[0];
      if (first) {
        return {
          road_address: first.road_address_name ?? "",
          address: first.address_name ?? "",
          phone: first.phone ?? "",
          place_url: first.place_url ?? "",
        };
      }
    }

    const coordURL = new URL("https://dapi.kakao.com/v2/local/geo/coord2address.json");
    coordURL.searchParams.set("x", String(store.longitude));
    coordURL.searchParams.set("y", String(store.latitude));
    const coordResponse = await fetch(coordURL.toString(), {
      headers,
      signal: AbortSignal.timeout(8_000),
    });
    if (!coordResponse.ok) return null;
    const coord = await coordResponse.json<{
      documents?: Array<{
        road_address?: { address_name?: string } | null;
        address?: { address_name?: string } | null;
      }>;
    }>();
    const first = coord.documents?.[0];
    if (!first) return null;
    return {
      road_address: first.road_address?.address_name ?? "",
      address: first.address?.address_name ?? "",
      phone: "",
      place_url: "",
    };
  } catch {
    return null;
  }
}

async function fetchNaverBlogs(
  env: Bindings,
  store: EnrichmentStoreRow,
): Promise<BlogEnrichment[] | null> {
  const id = env.NAVER_API_HUB_CLIENT_ID;
  const secret = env.NAVER_API_HUB_CLIENT_SECRET;
  if (!id || !secret) return null;
  const region = (store.address ?? "").split(/\s+/).slice(0, 2).join(" ");
  const url = new URL("https://naverapihub.apigw.ntruss.com/search/v1/blog");
  url.searchParams.set("query", region ? `${region} ${store.name}` : store.name);
  url.searchParams.set("display", "5");
  url.searchParams.set("sort", "sim");
  try {
    const response = await fetch(url.toString(), {
      headers: {
        "X-NCP-APIGW-API-KEY-ID": id,
        "X-NCP-APIGW-API-KEY": secret,
      },
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok) return null;
    const body = await response.json<{
      items?: Array<{
        title?: string;
        link?: string;
        description?: string;
        bloggername?: string;
        postdate?: string;
      }>;
    }>();
    const mapped = (body.items ?? []).map((item) => ({
      title: stripSearchHTML(item.title ?? ""),
      snippet: stripSearchHTML(item.description ?? ""),
      link: item.link ?? "",
      blogger: stripSearchHTML(item.bloggername ?? ""),
      date: (item.postdate ?? "").replace(/^(\d{4})(\d{2})(\d{2})$/, "$1.$2.$3"),
    }));
    const fullMatches = mapped.filter((post) => post.snippet.includes(store.name));
    if (fullMatches.length > 0) return fullMatches;
    const coreName = store.name.trim().split(/\s+/)[0] ?? "";
    if (coreName.length < 2) return [];
    return mapped.filter((post) => post.snippet.includes(coreName));
  } catch {
    return null;
  }
}

async function canAccessRoom(
  db: D1Database,
  roomId: number,
  userId: number,
): Promise<boolean> {
  const room = await db.prepare(
    `SELECT 1 AS allowed
     FROM chat_rooms r
     JOIN stores s ON s.store_id = r.store_id
     WHERE r.room_id = ?
       AND s.partner_status = 'ACTIVE'
       AND s.owner_id IS NOT NULL
       AND (r.user_id = ? OR s.owner_id = ?)
     LIMIT 1`,
  )
    .bind(roomId, userId, userId)
    .first<{ allowed: number }>();
  return Boolean(room);
}

async function reservationAccess(
  db: D1Database,
  reservationId: number,
  userId: number,
): Promise<{
  isCustomer: boolean;
  isStoreOwner: boolean;
  isActivePartner: boolean;
  status: string;
} | null> {
  const row = await db.prepare(
    `SELECT r.user_id, r.status, s.owner_id, s.partner_status
     FROM reservations r
     LEFT JOIN stores s ON s.store_id = r.store_id
     WHERE r.reservation_id = ?`,
  )
    .bind(reservationId)
    .first<{
      user_id: number;
      status: string;
      owner_id: number | null;
      partner_status: string;
    }>();
  if (!row) return null;
  return {
    isCustomer: row.user_id === userId,
    isStoreOwner: row.owner_id === userId && row.partner_status === "ACTIVE",
    status: row.status,
    isActivePartner: row.partner_status === "ACTIVE" && row.owner_id !== null,
  };
}

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
    .prepare(
      `SELECT store_id FROM stores
       WHERE store_key = ? AND partner_status = 'ACTIVE' AND owner_id IS NOT NULL`,
    )
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

// 공지사항 목록 — 본문 제외, 최신순
app.get("/api/notices", async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT id, title, created_at FROM notices ORDER BY created_at DESC`,
  ).all();
  return c.json(results);
});

// 공지사항 상세
app.get("/api/notices/:id", async (c) => {
  const id = Number(c.req.param("id"));
  const notice = await c.env.DB.prepare(
    `SELECT id, title, body, created_at FROM notices WHERE id = ?`,
  )
    .bind(id)
    .first();
  if (!notice) return c.json({ message: "notice not found" }, 404);
  return c.json(notice);
});

// 지도 핀 소스 — 선별(is_curated) 서울 가게만 반환. 가격정보 유무와 무관하게 유치원/호텔이면 포함.
app.get("/api/stores", async (c) => {
  const { results } = await c.env.DB.prepare(
    `
    SELECT s.store_id, store_key, name, address, phone, status, latitude, longitude,
           open_time, pickup, playground, large_dog, price_info, image_url, store_type, category,
           partner_status, c.is_partner, c.can_book, c.can_chat, c.can_diary, c.can_review
    FROM stores s
    JOIN store_capabilities c ON c.store_id = s.store_id
    WHERE is_curated = 1
    ORDER BY s.store_id DESC
  `,
  ).all();
  const exposeUnverifiedDetails = c.env.EXPOSE_UNVERIFIED_STORE_DETAILS === "true";
  return c.json(
    results.map((row) =>
      storeAPIResponse(row as Record<string, unknown>, [], exposeUnverifiedDetails),
    ),
  );
});

// 가게 상세 보강 정보 조회 — 앱 상세 화면에서 store_key로 호출
app.get("/api/stores/detail", async (c) => {
  const storeKey = (c.req.query("storeKey") ?? c.req.query("store_key") ?? "").trim();
  if (!storeKey) return c.json({ message: "storeKey is required" }, 400);

  const store = await c.env.DB.prepare(
    `
    SELECT s.store_id, store_key, name, address, phone, status, latitude, longitude,
           open_time, pickup, playground, large_dog, price_info, image_url, store_type, category,
           partner_status, c.is_partner, c.can_book, c.can_chat, c.can_diary, c.can_review
    FROM stores s
    JOIN store_capabilities c ON c.store_id = s.store_id
    WHERE store_key = ?
  `,
  )
    .bind(storeKey)
    .first();

  if (!store) return c.json(null);

  const exposeUnverifiedDetails = c.env.EXPOSE_UNVERIFIED_STORE_DETAILS === "true";
  const images = Number((store as Record<string, unknown>).is_partner ?? 0) === 1
    && exposeUnverifiedDetails
    ? (await c.env.DB.prepare(
      `SELECT image_id, image_url, sort_order
       FROM store_images
       WHERE store_id = ?
       ORDER BY sort_order ASC, image_id ASC`,
    )
      .bind((store as { store_id: number }).store_id)
      .all()).results
    : [];

  return c.json(
    storeAPIResponse(
      store as Record<string, unknown>,
      images,
      exposeUnverifiedDetails,
    ),
  );
});

// 외부 장소 API의 서버 중계. 사용자가 임의 검색어를 전달하지 못하게 D1 storeKey만 받는다.
app.get("/api/store-enrichment/place", async (c) => {
  const storeKey = (c.req.query("storeKey") ?? c.req.query("store_key") ?? "").trim();
  if (!storeKey) return c.json({ message: "storeKey is required" }, 400);
  const store = await findEnrichmentStore(c.env.DB, storeKey);
  if (!store) return c.json({ message: "store not found" }, 404);
  if (store.is_partner !== 1)
    return c.json(
      { message: "partner store required", code: "PARTNER_REQUIRED" },
      403,
    );

  const cached = await readEnrichmentCache<PlaceEnrichment>(
    c.env.DB,
    store.store_id,
    "PLACE",
  );
  if (cached) return c.json(cached);
  if (
    (!c.env.NAVER_API_HUB_CLIENT_ID || !c.env.NAVER_API_HUB_CLIENT_SECRET)
    && !c.env.KAKAO_REST_API_KEY
  ) {
    return c.json({ message: "place enrichment is not configured" }, 503);
  }

  const [naver, kakao] = await Promise.all([
    fetchNaverPlace(c.env, store),
    fetchKakaoPlace(c.env, store),
  ]);
  if (!naver && !kakao)
    return c.json({ message: "place enrichment unavailable" }, 502);
  const result: PlaceEnrichment = {
    road_address: naver?.road_address || kakao?.road_address || "",
    address: naver?.address || kakao?.address || "",
    phone: kakao?.phone ?? "",
    place_url: kakao?.place_url ?? "",
  };
  await writeEnrichmentCache(c.env.DB, store.store_id, "PLACE", result, 86_400);
  return c.json(result);
});

app.get("/api/store-enrichment/blogs", async (c) => {
  const storeKey = (c.req.query("storeKey") ?? c.req.query("store_key") ?? "").trim();
  if (!storeKey) return c.json({ message: "storeKey is required" }, 400);
  const store = await findEnrichmentStore(c.env.DB, storeKey);
  if (!store) return c.json({ message: "store not found" }, 404);
  if (store.is_partner !== 1)
    return c.json(
      { message: "partner store required", code: "PARTNER_REQUIRED" },
      403,
    );

  const cached = await readEnrichmentCache<BlogEnrichment[]>(
    c.env.DB,
    store.store_id,
    "BLOGS",
  );
  if (cached) return c.json(cached);
  if (!c.env.NAVER_API_HUB_CLIENT_ID || !c.env.NAVER_API_HUB_CLIENT_SECRET)
    return c.json({ message: "blog enrichment is not configured" }, 503);

  const posts = await fetchNaverBlogs(c.env, store);
  if (posts === null)
    return c.json({ message: "blog enrichment unavailable" }, 502);
  await writeEnrichmentCache(c.env.DB, store.store_id, "BLOGS", posts, 900);
  return c.json(posts);
});

function flagValue(value: boolean | number | undefined): number | null {
  if (value === undefined) return null;
  if (typeof value === "boolean") return value ? 1 : 0;
  return value ? 1 : 0;
}

// 로컬/관리자용 상세 데이터 업서트.
// 크롤링 스크립트가 store_key 기준으로 대표 이미지, 추가 이미지, 가격/태그를 저장한다.
app.post("/api/admin/stores/import", async (c) => {
  const body = await c.req.json<StoreDetailImportBody>();
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  if (!storeKey) return c.json({ message: "store_key is required" }, 400);

  const storeName = body.store_name ?? body.storeName ?? "";
  const storeAddress = body.store_address ?? body.storeAddress ?? "";
  const storeType = body.store_type ?? body.storeType ?? null;
  const openTime = body.open_time ?? body.openTime ?? null;
  const priceInfo = body.price_info ?? body.priceInfo ?? null;
  const imageUrl = body.image_url ?? body.imageUrl ?? null;
  const imageUrls = body.image_urls ?? body.imageUrls ?? [];

  const storeId = await resolveStoreId(c.env.DB, {
    storeKey,
    storeName,
    storeAddress,
  });

  await c.env.DB.prepare(
    `
    UPDATE stores SET
      name = COALESCE(NULLIF(?, ''), name),
      address = COALESCE(NULLIF(?, ''), address),
      phone = COALESCE(NULLIF(?, ''), phone),
      store_type = COALESCE(NULLIF(?, ''), store_type),
      latitude = COALESCE(?, latitude),
      longitude = COALESCE(?, longitude),
      open_time = COALESCE(NULLIF(?, ''), open_time),
      price_info = COALESCE(NULLIF(?, ''), price_info),
      image_url = COALESCE(NULLIF(?, ''), image_url),
      pickup = COALESCE(?, pickup),
      playground = COALESCE(?, playground),
      large_dog = COALESCE(?, large_dog)
    WHERE store_id = ?
  `,
  )
    .bind(
      storeName,
      storeAddress,
      body.phone ?? "",
      storeType ?? "",
      body.latitude ?? null,
      body.longitude ?? null,
      openTime ?? "",
      priceInfo ?? "",
      imageUrl ?? "",
      flagValue(body.pickup),
      flagValue(body.playground),
      flagValue(body.large_dog ?? body.largeDog),
      storeId,
    )
    .run();

  const allImages = [imageUrl, ...imageUrls]
    .filter((url): url is string => typeof url === "string" && url.trim().length > 0)
    .map((url) => url.trim());

  for (const [index, url] of allImages.entries()) {
    await c.env.DB.prepare(
      `
      INSERT OR IGNORE INTO store_images (store_id, image_url, sort_order)
      VALUES (?, ?, ?)
    `,
    )
      .bind(storeId, url, index)
      .run();
  }

  return c.json({ store_id: storeId, imported: true, image_count: allImages.length }, 201);
});

// 사장님 가게 등록 요청. owner_id는 여기서 바꾸지 않고 운영자 승인 시에만 연결한다.
app.post("/api/stores/claim", async (c) => {
  const body = await c.req.json<StoreClaimBody>();
  const userId = c.get("authUserId");
  const requestedUserId = body.user_id ?? body.userId;
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  if (requestedUserId !== undefined && !sameUser(userId, requestedUserId))
    return c.json({ message: "forbidden" }, 403);
  if (!c.get("authIsOwner"))
    return c.json({ message: "owner role required" }, 403);
  if (!storeKey)
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
  if (store?.owner_id === userId)
    return c.json({ store_id: storeId, owner_id: userId, status: "APPROVED" });

  const existing = await c.env.DB.prepare(
    `SELECT application_id, status
     FROM store_owner_applications
     WHERE user_id = ? AND store_id = ? AND status = 'PENDING'
     LIMIT 1`,
  )
    .bind(userId, storeId)
    .first<{ application_id: number; status: string }>();
  if (existing) {
    await c.env.DB.prepare(
      `UPDATE stores SET partner_status = 'PENDING'
       WHERE store_id = ? AND owner_id IS NULL AND partner_status <> 'ACTIVE'`,
    )
      .bind(storeId)
      .run();
    return c.json({
      application_id: existing.application_id,
      store_id: storeId,
      owner_id: null,
      status: existing.status,
    });
  }

  const otherPending = await c.env.DB.prepare(
    `SELECT application_id FROM store_owner_applications
     WHERE store_id = ? AND status = 'PENDING' LIMIT 1`,
  )
    .bind(storeId)
    .first<{ application_id: number }>();
  if (otherPending)
    return c.json({ message: "store approval is already pending" }, 409);

  const [inserted] = await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO store_owner_applications (user_id, store_id) VALUES (?, ?)`,
    ).bind(userId, storeId),
    c.env.DB.prepare(
      `UPDATE stores SET partner_status = 'PENDING',
                         partner_approved_at = NULL,
                         partner_approved_by = NULL
       WHERE store_id = ? AND owner_id IS NULL`,
    ).bind(storeId),
  ]);
  return c.json(
    {
      application_id: inserted.meta.last_row_id,
      store_id: storeId,
      owner_id: null,
      status: "PENDING",
    },
    201,
  );
});

// 사장님 본인의 가게 등록 요청 이력
app.get("/api/users/:id/store-owner-applications", async (c) => {
  const userId = Number(c.req.param("id"));
  if (!sameUser(c.get("authUserId"), userId) || !c.get("authIsOwner"))
    return c.json({ message: "forbidden" }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT a.application_id, a.user_id, a.store_id, a.status,
            a.applied_at, a.reviewed_at,
            s.store_key, s.name AS store_name, s.address AS store_address
     FROM store_owner_applications a
     JOIN stores s ON s.store_id = a.store_id
     WHERE a.user_id = ?
     ORDER BY a.application_id DESC`,
  )
    .bind(userId)
    .all();
  return c.json(results);
});

// 운영자 전용: 가게 등록 요청 목록. 사용자 연락처는 이 응답에서만 노출한다.
app.get("/api/owner-applications", async (c) => {
  if (!c.get("authIsAdmin")) return c.json({ message: "forbidden" }, 403);
  const requestedStatus = (c.req.query("status") ?? "PENDING").toUpperCase();
  const status = ["PENDING", "APPROVED", "REJECTED"].includes(requestedStatus)
    ? requestedStatus
    : "PENDING";
  const { results } = await c.env.DB.prepare(
    `SELECT a.application_id, a.user_id, a.store_id, a.status,
            a.applied_at, a.reviewed_at,
            u.nickname, u.email, u.phone, u.address, u.is_owner,
            s.store_key, s.name AS store_name, s.address AS store_address
     FROM store_owner_applications a
     JOIN users u ON u.user_id = a.user_id
     JOIN stores s ON s.store_id = a.store_id
     WHERE a.status = ?
     ORDER BY a.application_id ASC`,
  )
    .bind(status)
    .all();
  return c.json(results);
});

app.get("/api/owner-applications/pending-count", async (c) => {
  if (!c.get("authIsAdmin")) return c.json({ message: "forbidden" }, 403);
  const row = await c.env.DB.prepare(
    `SELECT COUNT(*) AS count FROM store_owner_applications WHERE status = 'PENDING'`,
  ).first<{ count: number }>();
  return c.json({ count: row?.count ?? 0 });
});

app.patch("/api/owner-applications/:id/approve", async (c) => {
  if (!c.get("authIsAdmin")) return c.json({ message: "forbidden" }, 403);
  const applicationId = Number(c.req.param("id"));
  const application = await c.env.DB.prepare(
    `SELECT a.user_id, a.store_id, a.status, u.is_owner, s.owner_id
     FROM store_owner_applications a
     JOIN users u ON u.user_id = a.user_id
     JOIN stores s ON s.store_id = a.store_id
     WHERE a.application_id = ?`,
  )
    .bind(applicationId)
    .first<{
      user_id: number;
      store_id: number;
      status: string;
      is_owner: number;
      owner_id: number | null;
    }>();
  if (!application) return c.json({ message: "application not found" }, 404);
  if (application.status === "APPROVED")
    return c.json({ ok: true, unchanged: true });
  if (application.status !== "PENDING")
    return c.json({ message: "application is not pending" }, 409);
  if ((application.is_owner ?? 0) !== 1)
    return c.json({ message: "applicant is not an owner account" }, 409);
  if (application.owner_id && application.owner_id !== application.user_id)
    return c.json({ message: "store already has another owner" }, 409);

  const [storeUpdate, applicationUpdate] = await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE stores
       SET owner_id = ?, partner_status = 'ACTIVE',
           partner_approved_at = CURRENT_TIMESTAMP, partner_approved_by = ?
       WHERE store_id = ?
         AND (owner_id IS NULL OR owner_id = ?)
         AND EXISTS (
           SELECT 1 FROM store_owner_applications
           WHERE application_id = ? AND status = 'PENDING'
         )`,
    ).bind(
      application.user_id,
      c.get("authUserId"),
      application.store_id,
      application.user_id,
      applicationId,
    ),
    c.env.DB.prepare(
      `UPDATE store_owner_applications
       SET status = 'APPROVED', reviewed_by = ?, reviewed_at = CURRENT_TIMESTAMP
       WHERE application_id = ?
         AND status = 'PENDING'
         AND EXISTS (
           SELECT 1 FROM stores
           WHERE store_id = ? AND owner_id = ?
         )`,
    ).bind(
      c.get("authUserId"),
      applicationId,
      application.store_id,
      application.user_id,
    ),
  ]);
  if ((storeUpdate.meta.changes ?? 0) === 0 || (applicationUpdate.meta.changes ?? 0) === 0)
    return c.json({ message: "approval state changed" }, 409);
  return c.json({
    ok: true,
    application_id: applicationId,
    store_id: application.store_id,
    owner_id: application.user_id,
    status: "APPROVED",
  });
});

app.patch("/api/owner-applications/:id/reject", async (c) => {
  if (!c.get("authIsAdmin")) return c.json({ message: "forbidden" }, 403);
  const applicationId = Number(c.req.param("id"));
  const rejected = await c.env.DB.prepare(
    `UPDATE store_owner_applications
     SET status = 'REJECTED', reviewed_by = ?, reviewed_at = CURRENT_TIMESTAMP
     WHERE application_id = ? AND status = 'PENDING'`,
  )
    .bind(c.get("authUserId"), applicationId)
    .run();
  if ((rejected.meta.changes ?? 0) === 0) {
    const existing = await c.env.DB.prepare(
      `SELECT status FROM store_owner_applications WHERE application_id = ?`,
    )
      .bind(applicationId)
      .first<{ status: string }>();
    if (!existing) return c.json({ message: "application not found" }, 404);
    if (existing.status === "REJECTED")
      return c.json({ ok: true, unchanged: true });
    return c.json({ message: "application is not pending" }, 409);
  }
  await c.env.DB.prepare(
    `UPDATE stores
     SET partner_status = 'NONE', partner_approved_at = NULL, partner_approved_by = NULL
     WHERE store_id = (
       SELECT store_id FROM store_owner_applications WHERE application_id = ?
     ) AND owner_id IS NULL AND partner_status = 'PENDING'`,
  )
    .bind(applicationId)
    .run();
  return c.json({ ok: true, status: "REJECTED" });
});

// 사장님이 등록한 내 가게 목록
app.get("/api/owners/:id/stores", async (c) => {
  const ownerId = Number(c.req.param("id"));
  if (!sameUser(c.get("authUserId"), ownerId) || !c.get("authIsOwner"))
    return c.json({ message: "forbidden" }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT store_id, store_key, name, address, partner_status
     FROM stores
     WHERE owner_id = ? AND partner_status = 'ACTIVE'
     ORDER BY store_id DESC`,
  )
    .bind(ownerId)
    .all();
  return c.json(results);
});

// 내 가게 등록 해제 — 본인 소유일 때만 owner_id를 비운다 (잘못 등록 시 복구 경로)
app.delete("/api/owners/:id/stores/:storeId", async (c) => {
  const ownerId = Number(c.req.param("id"));
  const storeId = Number(c.req.param("storeId"));
  if (!sameUser(c.get("authUserId"), ownerId) || !c.get("authIsOwner"))
    return c.json({ message: "forbidden" }, 403);
  const released = await c.env.DB.prepare(
    `UPDATE stores
     SET owner_id = NULL, partner_status = 'TERMINATED',
         partner_approved_at = NULL, partner_approved_by = NULL
     WHERE store_id = ? AND owner_id = ? AND partner_status = 'ACTIVE'`,
  )
    .bind(storeId, ownerId)
    .run();
  if ((released.meta.changes ?? 0) === 0)
    return c.json({ message: "active partner store not found" }, 404);
  return c.json({ ok: true });
});

// 사장님 문의함: 내 가게로 온 채팅방 목록 (메시지가 1개 이상 있는 방만, 손님 닉네임 포함)
app.get("/api/owners/:id/chatrooms", async (c) => {
  const ownerId = Number(c.req.param("id"));
  if (!sameUser(c.get("authUserId"), ownerId) || !c.get("authIsOwner"))
    return c.json({ message: "forbidden" }, 403);
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.room_id, r.store_id, s.name AS store_name,
           u.nickname AS customer_name,
           m.content AS last_message, m.created_at AS last_time
    FROM chat_rooms r
    JOIN stores s ON s.store_id = r.store_id
      AND s.owner_id = ? AND s.partner_status = 'ACTIVE'
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
  const userId = c.get("authUserId");
  const requestedUserId = body.user_id ?? body.userId;
  const petId = body.pet_id ?? body.petId;
  if (requestedUserId !== undefined && !sameUser(userId, requestedUserId))
    return c.json({ message: "forbidden" }, 403);
  if (!petId)
    return c.json({ message: "user_id/pet_id is required" }, 400);
  const startDate = body.start_date ?? body.startDate;
  const endDate = body.end_date ?? body.endDate;
  const reservationType =
    body.reservation_type ?? body.reservationType ?? "NORMAL";
  const requestMessage = body.request_message ?? body.requestMessage ?? "";
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  const storeName = body.store_name ?? body.storeName ?? "";

  if (!startDate || !endDate)
    return c.json({ message: "start_date/end_date is required" }, 400);

  const ownedPet = await c.env.DB.prepare(
    `SELECT 1 AS found FROM pets WHERE pet_id = ? AND user_id = ?`,
  )
    .bind(petId, userId)
    .first<{ found: number }>();
  if (!ownedPet) return c.json({ message: "pet does not belong to user" }, 403);

  // 일반 업체는 서버에서 예약 생성을 차단한다. 클라이언트 UI 우회도 허용하지 않는다.
  const storeAccess = await findStoreCapabilities(c.env.DB, {
    storeId: body.store_id ?? body.storeId,
    storeKey,
  });
  if (!storeAccess || storeAccess.can_book !== 1)
    return c.json(
      { message: "partner store required", code: "PARTNER_REQUIRED" },
      403,
    );
  const storeId = storeAccess.store_id;
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
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
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

  const access = await reservationAccess(
    c.env.DB,
    reservationId,
    c.get("authUserId"),
  );
  if (!access) return c.json({ message: "reservation not found" }, 404);
  if (byOwner) {
    if (!c.get("authIsOwner") || !access.isStoreOwner)
      return c.json({ message: "forbidden" }, 403);
  } else if (!access.isCustomer) {
    return c.json({ message: "forbidden" }, 403);
  }
  if (access.status === "CANCELED") return c.json({ ok: true, unchanged: true });
  if (access.status !== "REQUEST" && access.status !== "CONFIRMED")
    return c.json({ message: "invalid reservation status" }, 409);

  const canceled = await c.env.DB.prepare(
    `UPDATE reservations
     SET status = 'CANCELED', canceled_at = CURRENT_TIMESTAMP, canceled_by = ?
     WHERE reservation_id = ? AND status IN ('REQUEST', 'CONFIRMED')`,
  )
    .bind(byOwner ? "OWNER" : "USER", reservationId)
    .run();
  if ((canceled.meta.changes ?? 0) === 0)
    return c.json({ message: "reservation state changed" }, 409);

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
  if (!sameUser(c.get("authUserId"), ownerId) || !c.get("authIsOwner"))
    return c.json({ message: "forbidden" }, 403);
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.reservation_id, r.user_id, r.pet_id, r.store_id,
           COALESCE(r.store_name, s.name) AS store_name, s.store_type,
           p.name AS pet_name, p.breed AS pet_breed, p.age AS pet_age,
           p.weight AS pet_weight, p.gender AS pet_gender, p.note AS pet_note,
           u.nickname AS user_name, u.phone AS user_phone, u.address AS user_address,
           r.start_date, r.end_date, r.reservation_type, r.status, r.request_message, r.created_at
    FROM reservations r
    JOIN stores s ON s.store_id = r.store_id
      AND s.owner_id = ? AND s.partner_status = 'ACTIVE'
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
  if (!sameUser(c.get("authUserId"), ownerId) || !c.get("authIsOwner"))
    return c.json({ message: "forbidden" }, 403);
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.reservation_id, r.user_id, r.pet_id, r.store_id,
           COALESCE(r.store_name, s.name) AS store_name, s.store_type,
           p.name AS pet_name, p.breed AS pet_breed, p.age AS pet_age,
           p.weight AS pet_weight, p.gender AS pet_gender, p.note AS pet_note,
           u.nickname AS user_name, u.phone AS user_phone, u.address AS user_address,
           r.start_date, r.end_date, r.reservation_type, r.status, r.request_message, r.created_at
    FROM reservations r
    JOIN stores s ON s.store_id = r.store_id
      AND s.owner_id = ? AND s.partner_status = 'ACTIVE'
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

// 예약 확정 — 상태 변경 + 고객 채팅방에 확정 안내 자동 메시지
app.patch("/api/reservations/:id/confirm", async (c) => {
  const reservationId = Number(c.req.param("id"));
  const access = await reservationAccess(
    c.env.DB,
    reservationId,
    c.get("authUserId"),
  );
  if (!access) return c.json({ message: "reservation not found" }, 404);
  if (!c.get("authIsOwner") || !access.isStoreOwner)
    return c.json({ message: "forbidden" }, 403);
  if (access.status === "CONFIRMED")
    return c.json({ ok: true, unchanged: true });
  if (access.status !== "REQUEST")
    return c.json({ message: "only requested reservations can be confirmed" }, 409);

  const confirmed = await c.env.DB.prepare(
    `UPDATE reservations
     SET status = 'CONFIRMED', confirmed_at = CURRENT_TIMESTAMP
     WHERE reservation_id = ? AND status = 'REQUEST'`,
  )
    .bind(reservationId)
    .run();
  if ((confirmed.meta.changes ?? 0) === 0)
    return c.json({ message: "reservation state changed" }, 409);

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
        `${target.store_name} 예약(${target.start_date})이 확정되었어요. 예약 내역에서 확인해주세요`,
      )
      .run();
  }
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
  const access = await reservationAccess(
    c.env.DB,
    reservationId,
    c.get("authUserId"),
  );
  if (!access) return c.json({ message: "reservation not found" }, 404);
  if (!access.isActivePartner)
    return c.json(
      { message: "partner store required", code: "PARTNER_REQUIRED" },
      403,
    );
  if (!access.isCustomer && !access.isStoreOwner)
    return c.json({ message: "forbidden" }, 403);
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
  const access = await reservationAccess(
    c.env.DB,
    reservationId,
    c.get("authUserId"),
  );
  if (!access) return c.json({ message: "reservation not found" }, 404);
  if (!c.get("authIsOwner") || !access.isStoreOwner)
    return c.json({ message: "forbidden" }, 403);
  if (access.status !== "CONFIRMED")
    return c.json({ message: "confirmed reservation required" }, 409);
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
  const diary = await c.env.DB.prepare(
    `SELECT reservation_id FROM diaries WHERE diary_id = ?`,
  )
    .bind(diaryId)
    .first<{ reservation_id: number }>();
  if (!diary) return c.json({ message: "diary not found" }, 404);
  const access = await reservationAccess(
    c.env.DB,
    diary.reservation_id,
    c.get("authUserId"),
  );
  if (!access || !c.get("authIsOwner") || !access.isStoreOwner)
    return c.json({ message: "forbidden" }, 403);
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
  const diary = await c.env.DB.prepare(
    `SELECT reservation_id FROM diaries WHERE diary_id = ?`,
  )
    .bind(diaryId)
    .first<{ reservation_id: number }>();
  if (!diary) return c.json({ message: "diary not found" }, 404);
  const access = await reservationAccess(
    c.env.DB,
    diary.reservation_id,
    c.get("authUserId"),
  );
  if (!access || !c.get("authIsOwner") || !access.isStoreOwner)
    return c.json({ message: "forbidden" }, 403);
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
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
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

// MARK: - 고객센터 1:1 문의
// 가게 채팅과 완전히 분리한다. 일반 사용자는 자신의 단일 대화만, is_admin=1 운영자는
// 전체 문의 목록과 각 대화만 열람·답장할 수 있다.

app.get("/api/support/conversation", async (c) => {
  if (c.get("authIsAdmin")) return c.json({ message: "forbidden" }, 403);
  const userId = c.get("authUserId");
  const adminAvailable = await hasActiveSupportAdmin(c.env.DB);
  const conversation = await c.env.DB.prepare(
    `SELECT conversation_id, user_id, status, created_at, updated_at
     FROM support_conversations
     WHERE user_id = ?`,
  ).bind(userId).first();
  return c.json({
    admin_available: adminAvailable,
    conversation: conversation ?? null,
  });
});

app.post("/api/support/conversation", async (c) => {
  if (c.get("authIsAdmin")) return c.json({ message: "forbidden" }, 403);
  if (!(await hasActiveSupportAdmin(c.env.DB))) {
    return c.json(
      {
        message: "현재 문의를 받을 운영자 계정이 없습니다.",
        code: "SUPPORT_ADMIN_UNAVAILABLE",
      },
      503,
    );
  }

  const userId = c.get("authUserId");
  const inserted = await c.env.DB.prepare(
    `INSERT OR IGNORE INTO support_conversations (user_id) VALUES (?)`,
  ).bind(userId).run();
  const conversation = await c.env.DB.prepare(
    `SELECT conversation_id, user_id, status, created_at, updated_at
     FROM support_conversations
     WHERE user_id = ?`,
  ).bind(userId).first();
  if (!conversation)
    return c.json({ message: "failed to open support conversation" }, 500);
  return c.json(conversation, (inserted.meta.changes ?? 0) > 0 ? 201 : 200);
});

app.get("/api/support/conversations", async (c) => {
  if (!c.get("authIsAdmin")) return c.json({ message: "forbidden" }, 403);
  const { results } = await c.env.DB.prepare(
    `SELECT sc.conversation_id, sc.user_id, sc.status,
            sc.created_at, sc.updated_at,
            u.nickname AS user_name, u.email AS user_email,
            (
              SELECT sm.content FROM support_messages sm
              WHERE sm.conversation_id = sc.conversation_id
              ORDER BY sm.message_id DESC LIMIT 1
            ) AS last_message,
            (
              SELECT sm.created_at FROM support_messages sm
              WHERE sm.conversation_id = sc.conversation_id
              ORDER BY sm.message_id DESC LIMIT 1
            ) AS last_message_at
     FROM support_conversations sc
     JOIN users u ON u.user_id = sc.user_id
     WHERE u.deleted_at IS NULL
     ORDER BY COALESCE(last_message_at, sc.updated_at) DESC, sc.conversation_id DESC`,
  ).all();
  return c.json(results);
});

app.get("/api/support/conversations/:id/messages", async (c) => {
  const conversationId = Number(c.req.param("id"));
  if (!(await canAccessSupportConversation(
    c.env.DB,
    conversationId,
    c.get("authUserId"),
    c.get("authIsAdmin"),
  ))) return c.json({ message: "forbidden" }, 403);

  const { results } = await c.env.DB.prepare(
    `SELECT message_id, conversation_id, sender_id, sender_role, content, created_at
     FROM support_messages
     WHERE conversation_id = ?
     ORDER BY message_id ASC`,
  ).bind(conversationId).all();
  return c.json(results);
});

app.post("/api/support/conversations/:id/messages", async (c) => {
  const conversationId = Number(c.req.param("id"));
  const authUserId = c.get("authUserId");
  const authIsAdmin = c.get("authIsAdmin");
  if (!(await canAccessSupportConversation(
    c.env.DB,
    conversationId,
    authUserId,
    authIsAdmin,
  ))) return c.json({ message: "forbidden" }, 403);
  if (!authIsAdmin && !(await hasActiveSupportAdmin(c.env.DB))) {
    return c.json(
      {
        message: "현재 문의를 받을 운영자 계정이 없습니다.",
        code: "SUPPORT_ADMIN_UNAVAILABLE",
      },
      503,
    );
  }

  const body = await c.req.json<SupportMessageBody>().catch(() => ({}));
  const content = body.content?.trim() ?? "";
  if (!content) return c.json({ message: "content is required" }, 400);
  if (content.length > 4000)
    return c.json({ message: "content is too long" }, 400);

  const inserted = await c.env.DB.prepare(
    `INSERT INTO support_messages
       (conversation_id, sender_id, sender_role, content)
     VALUES (?, ?, ?, ?)`,
  ).bind(
    conversationId,
    authUserId,
    authIsAdmin ? "ADMIN" : "USER",
    content,
  ).run();
  await c.env.DB.prepare(
    `UPDATE support_conversations
     SET updated_at = CURRENT_TIMESTAMP, status = 'OPEN'
     WHERE conversation_id = ?`,
  ).bind(conversationId).run();
  const message = await c.env.DB.prepare(
    `SELECT message_id, conversation_id, sender_id, sender_role, content, created_at
     FROM support_messages WHERE message_id = ?`,
  ).bind(inserted.meta.last_row_id).first();
  return c.json(message, 201);
});

app.get("/api/chatrooms/:id/messages", async (c) => {
  const roomId = Number(c.req.param("id"));
  if (!(await canAccessRoom(c.env.DB, roomId, c.get("authUserId"))))
    return c.json({ message: "forbidden" }, 403);
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
  const authUserId = c.get("authUserId");
  if (!(await canAccessRoom(c.env.DB, roomId, authUserId)))
    return c.json({ message: "forbidden" }, 403);

  const requestedSenderId = body.sender_id ?? body.senderId;
  if (requestedSenderId !== undefined && requestedSenderId !== authUserId)
    return c.json({ message: "forbidden" }, 403);
  const senderId = authUserId;
  const user = await c.env.DB.prepare(
    `SELECT nickname FROM users WHERE user_id = ?`,
  )
    .bind(authUserId)
    .first<{ nickname: string | null }>();
  const senderName = user?.nickname ?? "나";
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
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
  const storeKey = c.req.query("store_key") ?? "";
  const storeAccess = await findStoreCapabilities(c.env.DB, { storeKey });
  if (!storeAccess || storeAccess.can_chat !== 1)
    return c.json(
      { message: "partner store required", code: "PARTNER_REQUIRED" },
      403,
    );
  const roomId = await findRoomId(c.env.DB, userId, storeKey);
  return c.json({ room_id: roomId });
});

// 문의 방 get-or-create (첫 메시지 전송 시 호출) — 자동 메시지 없음
app.post("/api/chatrooms", async (c) => {
  const body = await c.req.json<ChatRoomBody>();
  const userId = c.get("authUserId");
  const requestedUserId = body.user_id ?? body.userId;
  if (requestedUserId !== undefined && !sameUser(userId, requestedUserId))
    return c.json({ message: "forbidden" }, 403);
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  const storeName = body.store_name ?? body.storeName ?? "";

  const storeAccess = await findStoreCapabilities(c.env.DB, {
    storeId: body.store_id ?? body.storeId,
    storeKey,
  });
  if (!storeAccess || storeAccess.can_chat !== 1)
    return c.json(
      { message: "partner store required", code: "PARTNER_REQUIRED" },
      403,
    );
  const storeId = storeAccess.store_id;
  const roomId = await getOrCreateRoom(c.env.DB, userId, storeId);

  return c.json(
    { room_id: roomId, store_id: storeId, store_name: storeName },
    201,
  );
});

// 내 채팅방 목록 (메시지가 1개 이상 있는 방만)
app.get("/api/users/:id/chatrooms", async (c) => {
  const userId = Number(c.req.param("id"));
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
  const { results } = await c.env.DB.prepare(
    `
    SELECT r.room_id, r.store_id, s.name AS store_name, s.store_type,
           m.content AS last_message, m.created_at AS last_time
    FROM chat_rooms r
    JOIN stores s ON s.store_id = r.store_id
      AND s.partner_status = 'ACTIVE' AND s.owner_id IS NOT NULL
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
  const userId = c.get("authUserId");
  const requestedUserId = body.user_id ?? body.userId;
  if (requestedUserId !== undefined && !sameUser(userId, requestedUserId))
    return c.json({ message: "forbidden" }, 403);
  if (!(await canAccessRoom(c.env.DB, roomId, userId)))
    return c.json({ message: "forbidden" }, 403);

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
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
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
    JOIN stores s ON s.store_id = r.store_id
      AND s.partner_status = 'ACTIVE' AND s.owner_id IS NOT NULL
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
      JOIN stores s ON s.store_id = r.store_id
        AND s.owner_id = ? AND s.partner_status = 'ACTIVE'
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

// MARK: - 통합 알림 피드 (설계: docs/superpowers/specs/2026-07-18-push-notifications-design.md)
// 중복 방지 불변식: 채팅 메시지를 남기는 이벤트(알림장·예약 확정·사장님 취소·리뷰 요청 등)는 채팅 축으로만,
// 메시지가 없는 이벤트(새 요청·고객 취소)는 예약 축으로만 들어간다 — 이벤트당 알림 1회.

type NotificationCursor = {
  message_id?: number;
  request_id?: number;
  support_message_id?: number;
  owner_application_id?: number;
  canceled_at?: string;
};

type NotificationItem = {
  type:
    | "chat"
    | "reservation_request"
    | "reservation_canceled"
    | "support"
    | "owner_application";
  title: string;
  body: string;
  room_id?: number;
  reservation_id?: number;
  conversation_id?: number;
  application_id?: number;
  as_owner?: boolean;
  store_type?: string;
};

app.get("/api/users/:id/notifications", async (c) => {
  const userId = Number(c.req.param("id"));
  if (!userId) return c.json({ message: "user id required" }, 400);
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
  const rawCursor = c.req.query("cursor");

  const user = await c.env.DB.prepare(`SELECT is_owner FROM users WHERE user_id = ?`)
    .bind(userId)
    .first<{ is_owner: number | null }>();
  const isOwner = (user?.is_owner ?? 0) === 1;

  // 다음 커서 스냅샷 — 이벤트 유무와 무관하게 항상 현재 최신값
  const maxMsg = await c.env.DB.prepare(
    `SELECT COALESCE(MAX(message_id), 0) AS v FROM chat_messages`,
  ).first<{ v: number }>();
  const maxRes = await c.env.DB.prepare(
    `SELECT COALESCE(MAX(reservation_id), 0) AS v FROM reservations`,
  ).first<{ v: number }>();
  const maxSupport = await c.env.DB.prepare(
    `SELECT COALESCE(MAX(message_id), 0) AS v FROM support_messages`,
  ).first<{ v: number }>();
  const maxOwnerApplication = await c.env.DB.prepare(
    `SELECT COALESCE(MAX(application_id), 0) AS v FROM store_owner_applications`,
  ).first<{ v: number }>();
  const now = await c.env.DB.prepare(`SELECT CURRENT_TIMESTAMP AS v`).first<{ v: string }>();
  const nextCursor: NotificationCursor = {
    message_id: maxMsg?.v ?? 0,
    request_id: maxRes?.v ?? 0,
    support_message_id: maxSupport?.v ?? 0,
    owner_application_id: maxOwnerApplication?.v ?? 0,
    canceled_at: now?.v ?? "",
  };

  // 첫 호출(커서 없음): 과거 이벤트를 알림으로 쏟지 않도록 커서만 내려준다
  if (!rawCursor) return c.json({ notifications: [], cursor: nextCursor });

  let cursor: NotificationCursor;
  try {
    cursor = JSON.parse(rawCursor) as NotificationCursor;
  } catch {
    return c.json({ message: "invalid cursor" }, 400);
  }
  const afterMessage = cursor.message_id ?? 0;
  const afterRequest = cursor.request_id ?? 0;
  // 기존 앱이 저장한 커서에는 신규 축 필드가 없다. 이때 0부터 읽으면 배포 직후
  // 과거 문의·신청이 한꺼번에 알림으로 쏟아지므로 현재 최댓값에서 시작한다.
  const afterSupportMessage = cursor.support_message_id ?? (maxSupport?.v ?? 0);
  const afterOwnerApplication = cursor.owner_application_id ?? (maxOwnerApplication?.v ?? 0);
  const afterCanceled = cursor.canceled_at ?? "";

  const items: NotificationItem[] = [];

  // ── 채팅 축 ① 내가 손님인 방의 상대·시스템 메시지 — 방별 최신 1건 + 건수
  //    (SQLite: MAX() 집계 시 bare 컬럼은 최댓값 행의 값을 취한다)
  const asCustomer = await c.env.DB.prepare(
    `
    SELECT m.room_id, m.content, m.sender_id, s.name AS store_name, s.store_type,
           COUNT(*) AS cnt, MAX(m.message_id) AS last_id
    FROM chat_messages m
    JOIN chat_rooms r ON r.room_id = m.room_id AND r.user_id = ?
    JOIN stores s ON s.store_id = r.store_id
      AND s.partner_status = 'ACTIVE' AND s.owner_id IS NOT NULL
    WHERE m.sender_id != ? AND m.message_id > ?
    GROUP BY m.room_id
  `,
  )
    .bind(userId, userId, afterMessage)
    .all<{
      room_id: number;
      content: string;
      sender_id: number;
      store_name: string | null;
      store_type: string | null;
      cnt: number;
    }>();
  for (const row of asCustomer.results) {
    items.push({
      type: "chat",
      title: row.sender_id === 0 ? "맡겨멍" : (row.store_name ?? "채팅"),
      body: row.cnt > 1 ? `${row.content} 외 ${row.cnt - 1}건` : row.content,
      room_id: row.room_id,
      as_owner: false,
      store_type: row.store_type ?? undefined,
    });
  }

  // ── 채팅 축 ② (사장님) 내 가게 방의 손님 메시지 — sender 0 제외, 내가 손님인 방 제외
  if (isOwner) {
    const asOwnerRows = await c.env.DB.prepare(
      `
      SELECT m.room_id, m.content, u.nickname AS customer_name,
             COUNT(*) AS cnt, MAX(m.message_id) AS last_id
      FROM chat_messages m
      JOIN chat_rooms r ON r.room_id = m.room_id AND r.user_id != ?
      JOIN stores s ON s.store_id = r.store_id
        AND s.owner_id = ? AND s.partner_status = 'ACTIVE'
      LEFT JOIN users u ON u.user_id = r.user_id
      WHERE m.sender_id != ? AND m.sender_id != 0 AND m.message_id > ?
      GROUP BY m.room_id
    `,
    )
      .bind(userId, userId, userId, afterMessage)
      .all<{ room_id: number; content: string; customer_name: string | null; cnt: number }>();
    for (const row of asOwnerRows.results) {
      items.push({
        type: "chat",
        title: row.customer_name ?? "보호자",
        body: row.cnt > 1 ? `${row.content} 외 ${row.cnt - 1}건` : row.content,
        room_id: row.room_id,
        as_owner: true,
      });
    }
  }

  // ── 예약 축 (사장님) 새 예약 요청
  if (isOwner) {
    const requests = await c.env.DB.prepare(
      `
      SELECT r.reservation_id, COALESCE(r.store_name, s.name) AS store_name,
             p.name AS pet_name, r.reservation_type
      FROM reservations r
      JOIN stores s ON s.store_id = r.store_id
        AND s.owner_id = ? AND s.partner_status = 'ACTIVE'
      LEFT JOIN pets p ON p.pet_id = r.pet_id
      WHERE r.status = 'REQUEST' AND r.reservation_id > ?
      ORDER BY r.reservation_id
    `,
    )
      .bind(userId, afterRequest)
      .all<{ reservation_id: number; store_name: string | null; pet_name: string | null; reservation_type: string | null }>();
    for (const row of requests.results) {
      items.push({
        type: "reservation_request",
        title: "새 예약 요청",
        body: `${row.pet_name ?? "강아지"} 보호자의 ${row.reservation_type ?? "예약"} 요청 — ${row.store_name ?? ""}`,
        reservation_id: row.reservation_id,
      });
    }
  }

  // ── 예약 축 (사장님) 고객 취소 — canceled_by='USER'만 (사장님 본인 취소 제외)
  if (isOwner && afterCanceled) {
    const canceled = await c.env.DB.prepare(
      `
      SELECT r.reservation_id, COALESCE(r.store_name, s.name) AS store_name,
             p.name AS pet_name, r.start_date
      FROM reservations r
      JOIN stores s ON s.store_id = r.store_id
        AND s.owner_id = ? AND s.partner_status = 'ACTIVE'
      LEFT JOIN pets p ON p.pet_id = r.pet_id
      WHERE r.canceled_by = 'USER' AND r.canceled_at IS NOT NULL AND r.canceled_at > ?
      ORDER BY r.canceled_at
    `,
    )
      .bind(userId, afterCanceled)
      .all<{ reservation_id: number; store_name: string | null; pet_name: string | null; start_date: string }>();
    for (const row of canceled.results) {
      items.push({
        type: "reservation_canceled",
        title: "예약 취소",
        body: `${row.pet_name ?? "강아지"} 보호자가 ${row.start_date} 예약을 취소했어요 — ${row.store_name ?? ""}`,
        reservation_id: row.reservation_id,
      });
    }
  }

  // ── 고객센터 축: 일반 사용자는 운영자 답장, 운영자는 모든 사용자의 새 문의를 받는다.
  if (c.get("authIsAdmin")) {
    const supportMessages = await c.env.DB.prepare(
      `
      SELECT sm.conversation_id, sm.content, u.nickname AS user_name,
             COUNT(*) AS cnt, MAX(sm.message_id) AS last_id
      FROM support_messages sm
      JOIN support_conversations sc ON sc.conversation_id = sm.conversation_id
      JOIN users u ON u.user_id = sc.user_id AND u.deleted_at IS NULL
      WHERE sm.sender_role = 'USER' AND sm.message_id > ?
      GROUP BY sm.conversation_id
    `,
    )
      .bind(afterSupportMessage)
      .all<{ conversation_id: number; content: string; user_name: string | null; cnt: number }>();
    for (const row of supportMessages.results) {
      items.push({
        type: "support",
        title: row.user_name ?? "고객 문의",
        body: row.cnt > 1 ? `${row.content} 외 ${row.cnt - 1}건` : row.content,
        conversation_id: row.conversation_id,
      });
    }

    const ownerApplications = await c.env.DB.prepare(
      `
      SELECT a.application_id, u.nickname, s.name AS store_name
      FROM store_owner_applications a
      JOIN users u ON u.user_id = a.user_id AND u.deleted_at IS NULL
      JOIN stores s ON s.store_id = a.store_id
      WHERE a.status = 'PENDING' AND a.application_id > ?
      ORDER BY a.application_id
    `,
    )
      .bind(afterOwnerApplication)
      .all<{ application_id: number; nickname: string | null; store_name: string | null }>();
    for (const row of ownerApplications.results) {
      items.push({
        type: "owner_application",
        title: "새 가게 등록 요청",
        body: `${row.nickname ?? "사장님"} · ${row.store_name ?? "가게"}`,
        application_id: row.application_id,
      });
    }
  } else {
    const supportReplies = await c.env.DB.prepare(
      `
      SELECT sm.conversation_id, sm.content,
             COUNT(*) AS cnt, MAX(sm.message_id) AS last_id
      FROM support_messages sm
      JOIN support_conversations sc ON sc.conversation_id = sm.conversation_id
        AND sc.user_id = ?
      WHERE sm.sender_role = 'ADMIN' AND sm.message_id > ?
      GROUP BY sm.conversation_id
    `,
    )
      .bind(userId, afterSupportMessage)
      .all<{ conversation_id: number; content: string; cnt: number }>();
    for (const row of supportReplies.results) {
      items.push({
        type: "support",
        title: "맡겨멍 고객센터",
        body: row.cnt > 1 ? `${row.content} 외 ${row.cnt - 1}건` : row.content,
        conversation_id: row.conversation_id,
      });
    }
  }

  return c.json({ notifications: items, cursor: nextCursor });
});

// MARK: - 펫 특화 리뷰 (공공데이터 가게용, store_key = "이름|주소")

// 현재 예약 상태에는 COMPLETED가 없으므로, 확정(CONFIRMED)된 예약 중 이용 종료일이
// 한국 시간 기준 이용일이 지난 예약만 실제 이용 완료로 본다.
async function getReviewEligibility(
  db: D1Database,
  userId: number,
  storeKey: string,
): Promise<ReviewEligibility> {
  const capabilities = await findStoreCapabilities(db, { storeKey });
  if (!capabilities || capabilities.can_review !== 1) {
    return {
      eligible: false,
      reason: "partner_required",
      reservation_id: null,
    };
  }
  const available = await db
    .prepare(
      `
      SELECT r.reservation_id
      FROM reservations r
      JOIN stores s ON s.store_id = r.store_id
      LEFT JOIN pet_reviews pr ON pr.reservation_id = r.reservation_id
      WHERE r.user_id = ?
        AND s.store_key = ?
        AND s.partner_status = 'ACTIVE'
        AND s.owner_id IS NOT NULL
        AND r.status = 'CONFIRMED'
        AND date(substr(r.end_date, 1, 10)) < date('now', '+9 hours')
        AND pr.id IS NULL
      ORDER BY substr(r.end_date, 1, 10) DESC, r.reservation_id DESC
      LIMIT 1
      `,
    )
    .bind(userId, storeKey)
    .first<{ reservation_id: number }>();

  if (available) {
    return {
      eligible: true,
      reason: "eligible",
      reservation_id: available.reservation_id,
    };
  }

  const completed = await db
    .prepare(
      `
      SELECT 1 AS found
      FROM reservations r
      JOIN stores s ON s.store_id = r.store_id
      WHERE r.user_id = ?
        AND s.store_key = ?
        AND s.partner_status = 'ACTIVE'
        AND s.owner_id IS NOT NULL
        AND r.status = 'CONFIRMED'
        AND date(substr(r.end_date, 1, 10)) < date('now', '+9 hours')
      LIMIT 1
      `,
    )
    .bind(userId, storeKey)
    .first<{ found: number }>();

  return {
    eligible: false,
    reason: completed ? "already_reviewed" : "no_completed_reservation",
    reservation_id: null,
  };
}

// 리뷰 작성 버튼 노출 여부를 서버 데이터로 판단한다.
app.get("/api/pet-reviews/eligibility", async (c) => {
  const userId = Number(c.req.query("userId"));
  const storeKey = (c.req.query("storeKey") ?? "").trim();
  if (!Number.isInteger(userId) || userId <= 0 || !storeKey) {
    return c.json({ message: "userId and storeKey are required" }, 400);
  }
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);

  const eligibility = await getReviewEligibility(c.env.DB, userId, storeKey);
  return c.json({
    eligible: eligibility.eligible,
    reason: eligibility.reason,
  });
});

app.post("/api/pet-reviews", async (c) => {
  const body = await c.req.json<PetReviewBody>();
  const userId = Number(body.user_id ?? body.userId);
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  if (!Number.isInteger(userId) || userId <= 0 || !storeKey) {
    return c.json({ message: "user_id and store_key are required" }, 400);
  }
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);

  const storeName = body.store_name ?? body.storeName ?? "";
  const rating = Number(body.rating ?? 5);
  if (!Number.isFinite(rating) || rating < 1 || rating > 5) {
    return c.json({ message: "rating must be between 1 and 5" }, 400);
  }

  const eligibility = await getReviewEligibility(c.env.DB, userId, storeKey);
  if (!eligibility.eligible || !eligibility.reservation_id) {
    const status = eligibility.reason === "already_reviewed" ? 409 : 403;
    return c.json(
      {
        message:
          eligibility.reason === "already_reviewed"
            ? "review already submitted for completed reservations"
            : eligibility.reason === "partner_required"
              ? "partner store required"
              : "a completed reservation is required",
        reason: eligibility.reason,
      },
      status,
    );
  }

  // 표시 이름은 클라이언트 입력을 신뢰하지 않고 가입 계정에서 가져온다.
  const user = await c.env.DB.prepare(
    `SELECT nickname FROM users WHERE user_id = ?`,
  )
    .bind(userId)
    .first<{ nickname: string | null }>();
  if (!user) return c.json({ message: "user not found" }, 404);

  const b = (v: unknown) => (v ? 1 : 0);

  const result = await c.env.DB.prepare(
    `
    INSERT INTO pet_reviews
      (store_key, store_name, user_id, reservation_id, user_name, rating,
       revisit, cctv, pickup, large_dog, separation_care, content)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `,
  )
    .bind(
      storeKey,
      storeName,
      userId,
      eligibility.reservation_id,
      user.nickname ?? body.user_name ?? body.userName ?? "보호자",
      rating,
      b(body.revisit),
      b(body.cctv),
      b(body.pickup),
      b(body.large_dog),
      b(body.separation_care),
      body.content ?? "",
    )
    .run();

  return c.json(
    {
      id: result.meta.last_row_id,
      verified: true,
    },
    201,
  );
});

// 특정 가게 리뷰 목록 + 요약(집계)
app.get("/api/pet-reviews", async (c) => {
  const storeKey = c.req.query("storeKey") ?? "";
  if (!storeKey) return c.json({ message: "storeKey is required" }, 400);

  const { results } = await c.env.DB.prepare(
    `
    SELECT pr.id, pr.store_key, pr.store_name, pr.user_name, pr.rating, pr.revisit,
           pr.cctv, pr.pickup, pr.large_dog, pr.separation_care, pr.content, pr.created_at,
           1 AS verified
    FROM pet_reviews pr
    JOIN stores s ON s.store_key = pr.store_key
    WHERE pr.store_key = ? AND pr.reservation_id IS NOT NULL
      AND s.partner_status = 'ACTIVE' AND s.owner_id IS NOT NULL
    ORDER BY pr.id DESC
  `,
  )
    .bind(storeKey)
    .all();

  const summary = await c.env.DB.prepare(
    `
    SELECT COUNT(*) AS count, AVG(pr.rating) AS avg_rating,
           SUM(pr.cctv) AS cctv, SUM(pr.pickup) AS pickup,
           SUM(pr.large_dog) AS large_dog, SUM(pr.separation_care) AS separation_care
    FROM pet_reviews pr
    JOIN stores s ON s.store_key = pr.store_key
    WHERE pr.store_key = ? AND pr.reservation_id IS NOT NULL
      AND s.partner_status = 'ACTIVE' AND s.owner_id IS NOT NULL
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
    SELECT pr.store_key,
           COUNT(*) AS count, AVG(pr.rating) AS avg_rating,
           SUM(pr.cctv) AS cctv, SUM(pr.pickup) AS pickup,
           SUM(pr.large_dog) AS large_dog, SUM(pr.separation_care) AS separation_care
    FROM pet_reviews pr
    JOIN stores s ON s.store_key = pr.store_key
    WHERE pr.reservation_id IS NOT NULL
      AND s.partner_status = 'ACTIVE' AND s.owner_id IS NOT NULL
    GROUP BY pr.store_key
  `,
  ).all();
  return c.json(results);
});

// MARK: - 인증

type AuthUserRow = {
  user_id: number;
  kakao_id: string;
  nickname: string;
  email: string | null;
  phone: string | null;
  address: string | null;
  is_owner: number | null;
  is_admin: number | null;
};

async function findOrCreateUser(
  db: D1Database,
  kakaoId: string,
  nickname: string,
  email: string | null,
  isOwner: number,
): Promise<{ user: AuthUserRow; created: boolean; roleConflict: boolean }> {
  const existing = await db.prepare(
    `SELECT user_id, kakao_id, nickname, email, phone, address, is_owner, is_admin
     FROM users WHERE kakao_id = ?`,
  )
    .bind(kakaoId)
    .first<AuthUserRow>();
  if (existing) {
    return {
      user: existing,
      created: false,
      roleConflict: (existing.is_owner ?? 0) !== isOwner,
    };
  }

  const result = await db.prepare(
    `INSERT INTO users (kakao_id, nickname, email, is_owner) VALUES (?, ?, ?, ?)`,
  )
    .bind(kakaoId, nickname, email, isOwner)
    .run();
  const created = await db.prepare(
    `SELECT user_id, kakao_id, nickname, email, phone, address, is_owner, is_admin
     FROM users WHERE user_id = ?`,
  )
    .bind(result.meta.last_row_id)
    .first<AuthUserRow>();
  if (!created) throw new Error("failed to create user");
  return { user: created, created: true, roleConflict: false };
}

async function authResponse(
  db: D1Database,
  user: AuthUserRow,
): Promise<Record<string, unknown>> {
  await db
    .prepare(`DELETE FROM auth_sessions WHERE unixepoch(expires_at) <= unixepoch('now')`)
    .run();
  const session = await createSession(db, user.user_id);
  return {
    ...user,
    session_token: session.token,
    session_expires_at: session.expiresAt,
  };
}

// 카카오 액세스 토큰은 서버가 카카오 사용자 API로 직접 검증한다.
app.post("/api/auth/kakao", async (c) => {
  const body = await c.req.json<KakaoAuthBody>();
  const accessToken = (body.access_token ?? body.accessToken ?? "").trim();
  const isOwner = (body.is_owner ?? body.isOwner ?? false) ? 1 : 0;
  if (!accessToken) return c.json({ message: "access_token is required" }, 400);

  const kakaoResponse = await fetch("https://kapi.kakao.com/v2/user/me", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!kakaoResponse.ok)
    return c.json({ message: "invalid kakao access token" }, 401);

  const kakaoUser = await kakaoResponse.json<{
    id?: number;
    properties?: { nickname?: string };
    kakao_account?: {
      email?: string;
      profile?: { nickname?: string };
    };
  }>();
  if (!kakaoUser.id) return c.json({ message: "kakao user id missing" }, 401);

  const nickname =
    kakaoUser.kakao_account?.profile?.nickname ??
    kakaoUser.properties?.nickname ??
    "보호자";
  const result = await findOrCreateUser(
    c.env.DB,
    String(kakaoUser.id),
    nickname,
    kakaoUser.kakao_account?.email ?? null,
    isOwner,
  );
  if (result.roleConflict)
    return c.json(
      {
        message: "already registered with a different role",
        is_owner: result.user.is_owner ?? 0,
      },
      409,
    );

  return c.json(
    await authResponse(c.env.DB, result.user),
    result.created ? 201 : 200,
  );
});

// 로컬 wrangler에서만 사용하는 개발 계정. 운영에는 ALLOW_DEV_AUTH를 설정하지 않는다.
app.post("/api/auth/dev", async (c) => {
  if (c.env.ALLOW_DEV_AUTH !== "true")
    return c.json({ message: "not found" }, 404);
  const body = await c.req.json<DevAuthBody>().catch(() => ({}) as DevAuthBody);
  const isOwner = (body.is_owner ?? body.isOwner ?? false) ? 1 : 0;
  const isAdmin = (body.is_admin ?? body.isAdmin ?? false) ? 1 : 0;
  const identity =
    body.identity?.trim().replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 40) ||
    (isOwner ? "owner" : "guardian");
  const result = await findOrCreateUser(
    c.env.DB,
    `dev-local-${identity}`,
    body.nickname?.trim() || (isOwner ? "테스트사장님" : "테스트"),
    null,
    isOwner,
  );
  if (result.roleConflict)
    return c.json(
      {
        message: "already registered with a different role",
        is_owner: result.user.is_owner ?? 0,
      },
      409,
    );
  if ((result.user.is_admin ?? 0) !== isAdmin) {
    await c.env.DB.prepare(`UPDATE users SET is_admin = ? WHERE user_id = ?`)
      .bind(isAdmin, result.user.user_id)
      .run();
    result.user.is_admin = isAdmin;
  }
  return c.json(
    await authResponse(c.env.DB, result.user),
    result.created ? 201 : 200,
  );
});

app.post("/api/auth/logout", async (c) => {
  await c.env.DB.prepare(`DELETE FROM auth_sessions WHERE token_hash = ?`)
    .bind(c.get("authTokenHash"))
    .run();
  return c.json({ ok: true });
});

// 회원 탈퇴 — 진행 중 예약이 없을 때만 개인정보를 삭제하고 보존 데이터는 익명화한다.
// 예약/리뷰 식별용 숫자 user_id는 참조 무결성을 위해 남지만, 외부 계정 식별자와 프로필은 제거한다.
app.delete("/api/users/:id/account", async (c) => {
  const userId = Number(c.req.param("id"));
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);

  const activeAsCustomer = await c.env.DB.prepare(
    `SELECT COUNT(*) AS count
     FROM reservations
     WHERE user_id = ?
       AND status IN ('REQUEST', 'CONFIRMED')
       AND (
         date(substr(end_date, 1, 10)) >= date('now', '+9 hours')
         OR date(substr(end_date, 1, 10)) IS NULL
       )`,
  )
    .bind(userId)
    .first<{ count: number }>();
  const activeAsOwner = await c.env.DB.prepare(
    `SELECT COUNT(*) AS count
     FROM reservations r
     JOIN stores s ON s.store_id = r.store_id
     WHERE s.owner_id = ?
       AND s.partner_status = 'ACTIVE'
       AND r.status IN ('REQUEST', 'CONFIRMED')
       AND (
         date(substr(r.end_date, 1, 10)) >= date('now', '+9 hours')
         OR date(substr(r.end_date, 1, 10)) IS NULL
       )`,
  )
    .bind(userId)
    .first<{ count: number }>();
  const customerCount = activeAsCustomer?.count ?? 0;
  const ownerCount = activeAsOwner?.count ?? 0;
  if (customerCount > 0 || ownerCount > 0) {
    return c.json(
      {
        message: "active reservations must be completed or canceled before account deletion",
        code: "ACTIVE_RESERVATIONS",
        active_reservations: customerCount,
        active_owned_reservations: ownerCount,
      },
      409,
    );
  }

  const deletedAt = new Date().toISOString();
  const results = await c.env.DB.batch([
    // 보호자 데이터: 반려견·찜·알림장·개인 채팅은 삭제한다.
    c.env.DB.prepare(
      `DELETE FROM diary_photos
       WHERE diary_id IN (
         SELECT d.diary_id FROM diaries d
         JOIN reservations r ON r.reservation_id = d.reservation_id
         WHERE r.user_id = ?
       )`,
    ).bind(userId),
    c.env.DB.prepare(
      `DELETE FROM diaries
       WHERE reservation_id IN (SELECT reservation_id FROM reservations WHERE user_id = ?)`,
    ).bind(userId),
    c.env.DB.prepare(
      `DELETE FROM chat_room_reads
       WHERE user_id = ?
          OR room_id IN (SELECT room_id FROM chat_rooms WHERE user_id = ?)`,
    ).bind(userId, userId),
    c.env.DB.prepare(
      `DELETE FROM chat_messages
       WHERE room_id IN (SELECT room_id FROM chat_rooms WHERE user_id = ?)`,
    ).bind(userId),
    c.env.DB.prepare(`DELETE FROM chat_rooms WHERE user_id = ?`).bind(userId),
    c.env.DB.prepare(
      `DELETE FROM support_messages
       WHERE conversation_id IN (
         SELECT conversation_id FROM support_conversations WHERE user_id = ?
       )`,
    ).bind(userId),
    c.env.DB.prepare(`DELETE FROM support_conversations WHERE user_id = ?`).bind(userId),
    c.env.DB.prepare(`DELETE FROM favorites WHERE user_id = ?`).bind(userId),
    c.env.DB.prepare(`DELETE FROM pets WHERE user_id = ?`).bind(userId),

    // 거래·후기 이력은 개인정보와 연결되지 않도록 익명화해 최소 정보만 보존한다.
    c.env.DB.prepare(
      `UPDATE reservations SET request_message = NULL WHERE user_id = ?`,
    ).bind(userId),
    c.env.DB.prepare(
      `UPDATE pet_reviews
       SET user_id = NULL, user_name = '익명', content = ''
       WHERE user_id = ?`,
    ).bind(userId),
    c.env.DB.prepare(
      `UPDATE chat_messages
       SET sender_name = '탈퇴한 사용자', content = '삭제된 메시지입니다.'
       WHERE sender_id = ?`,
    ).bind(userId),

    // 사장님 탈퇴: 진행 예약이 없는 것이 확인된 뒤 가게 연결을 해제한다.
    c.env.DB.prepare(
      `UPDATE stores
       SET owner_id = NULL, partner_status = 'TERMINATED',
           partner_approved_at = NULL, partner_approved_by = NULL
       WHERE owner_id = ?`,
    ).bind(userId),
    c.env.DB.prepare(
      `UPDATE store_owner_applications
       SET status = 'REJECTED', reviewed_at = CURRENT_TIMESTAMP
       WHERE user_id = ? AND status = 'PENDING'`,
    ).bind(userId),

    // 현재 기기뿐 아니라 같은 계정의 모든 기기 세션을 즉시 폐기한다.
    c.env.DB.prepare(`DELETE FROM auth_sessions WHERE user_id = ?`).bind(userId),
    c.env.DB.prepare(
      `UPDATE users
       SET kakao_id = 'deleted:' || user_id || ':' || lower(hex(randomblob(16))),
           nickname = '탈퇴한 사용자', email = NULL, phone = NULL, address = NULL,
           is_owner = 0, is_admin = 0, deleted_at = ?
       WHERE user_id = ? AND deleted_at IS NULL`,
    ).bind(deletedAt, userId),
  ]);

  const userUpdate = results.at(-1);
  if (!userUpdate || (userUpdate.meta.changes ?? 0) !== 1)
    return c.json({ message: "user not found" }, 404);
  return c.json({ ok: true, deleted_at: deletedAt });
});

// 유저 프로필 수정 (닉네임, 전화번호, 주소)
app.put("/api/users/:id", async (c) => {
  const userId = Number(c.req.param("id"));
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
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
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
  const body = await c.req.json<CreatePetBody>();

  if (!body.name) return c.json({ message: "name is required" }, 400);

  const imageUrl = (body.image_url ?? body.imageUrl ?? "").trim() || null;
  if (
    imageUrl &&
    (!/^data:image\/(jpeg|png);base64,[A-Za-z0-9+/=]+$/.test(imageUrl) ||
      imageUrl.length > 1_050_000)
  ) {
    return c.json({ message: "invalid pet image" }, 400);
  }

  const result = await c.env.DB.prepare(
    `INSERT INTO pets (user_id, name, breed, age, weight, gender, note, image_url)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      userId,
      body.name,
      body.breed ?? null,
      body.age ?? null,
      body.weight ?? null,
      body.gender ?? null,
      body.note ?? null,
      imageUrl,
    )
    .run();

  const created = await c.env.DB.prepare(
    `SELECT pet_id, user_id, name, breed, age, weight, gender, note, image_url FROM pets WHERE pet_id = ?`,
  )
    .bind(result.meta.last_row_id)
    .first();

  return c.json(created, 201);
});

// 강아지 삭제
app.delete("/api/pets/:petId", async (c) => {
  const petId = Number(c.req.param("petId"));
  const deleted = await c.env.DB.prepare(
    `DELETE FROM pets WHERE pet_id = ? AND user_id = ?`,
  )
    .bind(petId, c.get("authUserId"))
    .run();
  if ((deleted.meta.changes ?? 0) === 0)
    return c.json({ message: "pet not found" }, 404);
  return c.json({ ok: true });
});

// MARK: - 찜한 가게 (favorites)

// 찜 추가: store_key로 stores upsert 후 (user_id, store_id) 등록.
// 찜 시점에 알게 된 전화·유형·좌표는 비어 있는 컬럼만 채움 (기존 값 보존)
app.post("/api/favorites", async (c) => {
  const body = await c.req.json<FavoriteBody>();
  const userId = c.get("authUserId");
  const requestedUserId = body.user_id ?? body.userId;
  const storeKey = (body.store_key ?? body.storeKey ?? "").trim();
  if (requestedUserId !== undefined && !sameUser(userId, requestedUserId))
    return c.json({ message: "forbidden" }, 403);
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
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
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
  if (!sameUser(c.get("authUserId"), userId))
    return c.json({ message: "forbidden" }, 403);
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
      AND s.partner_status = 'ACTIVE'
      AND s.owner_id IS NOT NULL
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

// 데이터 정비용 임시 엔드포인트 — 네이버 플레이스 업체사진이 가격표인지 비전 모델로 판별하고,
// 가격표면 텍스트를 추출한다 (crawl-results 가격 이미지 스캔 스크립트 전용).
app.post("/api/internal/vision-price-ocr", async (c) => {
  const body = await c.req.json<{ image_url?: string; model?: string }>();
  const imageUrl = (body.image_url ?? "").trim();
  if (!imageUrl) return c.json({ error: "image_url이 필요합니다" }, 400);
  // llava-1.5-7b-hf는 프롬프트를 그대로 되풀이하거나 없는 가격을 지어내는 사례가 확인되어(2026-08-09) 기본값 교체.
  const model = body.model ?? "@cf/meta/llama-3.2-11b-vision-instruct";

  const imageRes = await fetch(imageUrl);
  if (!imageRes.ok) return c.json({ error: "이미지 다운로드 실패" }, 502);
  const bytes = Array.from(new Uint8Array(await imageRes.arrayBuffer()));

  const result = await c.env.AI.run(model, {
    image: bytes,
    prompt:
      "이 이미지가 반려동물 유치원/호텔의 요금표(가격표) 사진인가요? 요금표이면 다른 설명 없이 '가격표:' 다음에 이미지에 실제로 적힌 서비스명과 가격만 콤마로 구분해 나열하세요(예시나 가상의 숫자를 만들지 마세요). 요금표가 아니면 다른 말 없이 '요금표 아님'이라고만 답하세요. 두 경우를 섞어서 답하지 마세요.",
    max_tokens: 512,
  });

  return c.json({ result: result.description ?? result.response ?? "" });
});

export default {
  fetch: app.fetch,
  scheduled: async (
    event: ScheduledEvent,
    env: Bindings,
    _ctx: ExecutionContext,
  ) => {
    if (event.cron === STORE_DETAIL_REFRESH_CRON) {
      if (env.NAVER_PLACE_REFRESH_ENABLED !== "true") {
        console.log("store detail refresh disabled pending source-rights review");
        return;
      }
      const result = await refreshStaleStoreDetails(env.DB, 8);
      console.log("weekly store detail refresh", result);
      return;
    }

    if (event.cron === REVIEW_REQUEST_CRON) {
      await sendReviewRequests(env.DB);
    }
  },
};
