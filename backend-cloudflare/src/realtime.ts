import { DurableObject } from "cloudflare:workers";
import type { MiddlewareHandler } from "hono";

export type RealtimeBindings = {
  DB: D1Database;
  USER_REALTIME: DurableObjectNamespace;
};
type RealtimeVariables = {
  authUserId: number;
  authTokenHash: string;
  authIsOwner: boolean;
  authIsAdmin: boolean;
};
type Change = {
  type: "change";
  event_id: string;
  scope: "chat" | "reservation" | "diary" | "owner_application" | "support";
  application_id?: number;
  conversation_id?: number;
  room_id?: number;
  reservation_id?: number;
};
type Audience = { user_id: number; owner_id: number | null; room_id?: number; reservation_id?: number };
type SocketSession = { userId: number; tokenHash: string };
const SESSION_CHECK_MS = 30_000;

// 클라이언트가 지정한 사용자/쿼리가 아니라 인증 미들웨어의 세션만 전달한다.
export function connectRealtime(env: RealtimeBindings, userId: number, tokenHash: string, request: Request): Promise<Response> {
  if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
    return Promise.resolve(new Response("WebSocket upgrade required", { status: 426, headers: { Upgrade: "websocket" } }));
  }
  return userObject(env, userId).fetch(new Request("https://realtime.internal/connect", {
    headers: { Upgrade: "websocket", "X-Realtime-User": String(userId), "X-Realtime-Session": tokenHash },
  }));
}

function userObject(env: RealtimeBindings, userId: number): DurableObjectStub {
  return env.USER_REALTIME.get(env.USER_REALTIME.idFromName(`user:${userId}`));
}

// DO는 외부 라우트가 없는 binding 전용이다. 사용자별 이름 + 영속 identity를 함께 확인한다.
export class UserRealtime extends DurableObject<RealtimeBindings> {
  private userId?: number;

  constructor(ctx: DurableObjectState, env: RealtimeBindings) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => { this.userId = await ctx.storage.get<number>("userId"); });
  }

  private async isValid(session: SocketSession): Promise<boolean> {
    if (session.userId !== this.userId || !session.tokenHash) return false;
    return !!await this.env.DB.prepare(
      `SELECT 1 AS valid FROM auth_sessions a JOIN users u ON u.user_id = a.user_id
       WHERE a.token_hash = ? AND a.user_id = ? AND u.deleted_at IS NULL
       AND unixepoch(a.expires_at) > unixepoch('now')`,
    ).bind(session.tokenHash, session.userId).first();
  }

  async fetch(request: Request): Promise<Response> {
    const userId = Number(request.headers.get("X-Realtime-User"));
    if (!Number.isSafeInteger(userId) || userId <= 0) return new Response("forbidden", { status: 403 });
    if (this.userId === undefined) {
      this.userId = userId;
      await this.ctx.storage.put("userId", userId);
    }
    if (userId !== this.userId) return new Response("forbidden", { status: 403 });
    const path = new URL(request.url).pathname;
    if (path === "/connect") {
      const session = { userId, tokenHash: request.headers.get("X-Realtime-Session") ?? "" };
      if (!await this.isValid(session)) return new Response("invalid session", { status: 401 });
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return new Response("upgrade required", { status: 426 });
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment(session);
      server.send(JSON.stringify({ type: "ready" }));
      await this.scheduleCheck();
      return new Response(null, { status: 101, webSocket: client });
    }
    if (request.method !== "POST") return new Response("not found", { status: 404 });
    if (path === "/revoke") {
      const tokenHash = request.headers.get("X-Realtime-Session");
      for (const ws of this.ctx.getWebSockets()) {
        const session = ws.deserializeAttachment() as SocketSession;
        if (!tokenHash || session.tokenHash === tokenHash) ws.close(4401, "session invalidated");
      }
      return new Response(null, { status: 204 });
    }
    if (path === "/publish") {
      const event = await request.text();
      // 유효성 검사는 모든 전송 직전에 한다. 만료·다른 기기 로그아웃 후 정보가 새지 않는다.
      for (const ws of this.ctx.getWebSockets()) {
        if (!await this.isValid(ws.deserializeAttachment() as SocketSession)) {
          ws.close(4401, "session invalidated");
          continue;
        }
        try { ws.send(event); } catch { ws.close(1011, "send failed"); }
      }
      return new Response(null, { status: 204 });
    }
    return new Response("not found", { status: 404 });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (!await this.isValid(ws.deserializeAttachment() as SocketSession)) {
      ws.close(4401, "session invalidated");
      return;
    }
    if (message === "ping") ws.send(JSON.stringify({ type: "pong" }));
    else ws.close(1008, "unsupported message");
  }

  webSocketError(ws: WebSocket): void { ws.close(1011, "connection error"); }
  webSocketClose(ws: WebSocket): void { ws.close(1000, "closed"); }

  private async scheduleCheck(): Promise<void> {
    if (this.ctx.getWebSockets().length && await this.ctx.storage.getAlarm() === null) {
      await this.ctx.storage.setAlarm(Date.now() + SESSION_CHECK_MS);
    }
  }

  async alarm(): Promise<void> {
    for (const ws of this.ctx.getWebSockets()) {
      if (!await this.isValid(ws.deserializeAttachment() as SocketSession)) ws.close(4401, "session invalidated");
    }
    await this.scheduleCheck();
  }
}

async function revoke(env: RealtimeBindings, userId: number, tokenHash?: string): Promise<void> {
  await userObject(env, userId).fetch(new Request("https://realtime.internal/revoke", {
    method: "POST", headers: { "X-Realtime-User": String(userId), ...(tokenHash ? { "X-Realtime-Session": tokenHash } : {}) },
  }));
}

async function audience(db: D1Database, kind: string, id: number): Promise<Audience | null> {
  if (!Number.isSafeInteger(id) || id <= 0) return null;
  if (kind === "chat") {
    return db.prepare(`SELECT r.user_id, s.owner_id, r.room_id FROM chat_rooms r
      JOIN stores s ON s.store_id = r.store_id WHERE r.room_id = ?`).bind(id).first<Audience>();
  }
  const source = kind === "diary" ? "JOIN diaries d ON d.reservation_id = r.reservation_id"
    : kind === "photo" ? "JOIN diaries d ON d.reservation_id = r.reservation_id JOIN diary_photos p ON p.diary_id = d.diary_id" : "";
  const column = kind === "diary" ? "d.diary_id" : kind === "photo" ? "p.photo_id" : "r.reservation_id";
  return db.prepare(`SELECT r.user_id, s.owner_id, r.reservation_id, cr.room_id FROM reservations r
    JOIN stores s ON s.store_id = r.store_id ${source}
    LEFT JOIN chat_rooms cr ON cr.user_id = r.user_id AND cr.store_id = r.store_id
    WHERE ${column} = ?`).bind(id).first<Audience>();
}

async function publish(env: RealtimeBindings, userIds: number[], event: Change): Promise<void> {
  await Promise.all([...new Set(userIds)].map(userId => userObject(env, userId).fetch(new Request("https://realtime.internal/publish", {
    method: "POST", headers: { "X-Realtime-User": String(userId) }, body: JSON.stringify(event),
  }))));
}

async function activeAdminIds(db: D1Database): Promise<number[]> {
  const { results } = await db.prepare(`SELECT user_id FROM users WHERE is_admin = 1 AND deleted_at IS NULL`).all<{ user_id: number }>();
  return results.map(row => row.user_id);
}

// 인증 다음에 등록한다. 삭제 전 audience를 확보하되 성공한 쓰기 후에만 invalidation을 보낸다.
export const realtimeChanges: MiddlewareHandler<{ Bindings: RealtimeBindings; Variables: RealtimeVariables }> = async (c, next) => {
  const method = c.req.method;
  const path = c.req.path;
  const reservation = path.match(/^\/api\/reservations\/(\d+)\/(cancel|confirm|diaries)$/);
  const chat = path.match(/^\/api\/chatrooms\/(\d+)\/messages$/);
  const diary = path.match(/^\/api\/diaries\/(\d+)(\/photos)?$/);
  const photo = path.match(/^\/api\/diary-photos\/(\d+)$/);
  const rejectingApplication = method === "PATCH" && /^\/api\/owner-applications\/\d+\/reject$/.test(path);
  const claimingStore = method === "POST" && path === "/api/stores/claim";
  const support = path.match(/^\/api\/support\/conversations\/(\d+)\/messages$/);
  const creatingReservation = method === "POST" && path === "/api/reservations";
  const creatingRoom = method === "POST" && path === "/api/chatrooms";
  const logout = method === "POST" && path === "/api/auth/logout";
  const deletingAccount = method === "DELETE" && /^\/api\/users\/\d+\/account$/.test(path);
  const writing = ["POST", "PATCH", "DELETE"].includes(method);
  if (!writing || !(reservation || chat || diary || photo || creatingReservation || creatingRoom || claimingStore || rejectingApplication || support || logout || deletingAccount)) {
    await next();
    return;
  }
  let target: Audience | null = null;
  try {
    target = reservation ? await audience(c.env.DB, "reservation", Number(reservation[1]))
      : chat ? await audience(c.env.DB, "chat", Number(chat[1]))
      : diary ? await audience(c.env.DB, "diary", Number(diary[1]))
      : photo ? await audience(c.env.DB, "photo", Number(photo[1])) : null;
  } catch (error) {
    console.error("realtime audience lookup failed", error);
  }
  await next();
  if (!c.res.ok) return;
  try {
    if (logout || deletingAccount) {
      await revoke(c.env, c.get("authUserId"), logout ? c.get("authTokenHash") : undefined);
      return;
    }
    if (rejectingApplication) {
      const body = await c.res.clone().json() as { rejection_id?: number; unchanged?: boolean };
      if (body.unchanged || !body.rejection_id) return;
      // 응답/payload의 사용자 ID는 신뢰하지 않고 실제 durable 이벤트의 신청자를 따른다.
      const rejection = await c.env.DB.prepare(`SELECT e.user_id, e.application_id
        FROM owner_application_rejections e
        JOIN users u ON u.user_id = e.user_id AND u.deleted_at IS NULL
        WHERE e.rejection_id = ? AND e.application_id = ?`)
        .bind(body.rejection_id, Number(path.split("/")[3]))
        .first<{ user_id: number; application_id: number }>();
      if (!rejection) return;
      await publish(c.env, [rejection.user_id], {
        type: "change", event_id: `owner_application_rejected:${body.rejection_id}`,
        scope: "owner_application", application_id: rejection.application_id,
      });
      return;
    }
    if (claimingStore) {
      // 200인 기존 PENDING 재요청·이미 승인된 가게는 새 알림이 아니다.
      if (c.res.status !== 201) return;
      const body = await c.res.clone().json() as { application_id?: number };
      const application = await c.env.DB.prepare(`SELECT a.application_id FROM store_owner_applications a
        JOIN users u ON u.user_id = a.user_id AND u.deleted_at IS NULL
        WHERE a.application_id = ? AND a.user_id = ? AND a.status = 'PENDING'`)
        .bind(body.application_id ?? 0, c.get("authUserId")).first<{ application_id: number }>();
      if (!application) return;
      await publish(c.env, await activeAdminIds(c.env.DB), {
        type: "change", event_id: crypto.randomUUID(), scope: "owner_application", application_id: application.application_id,
      });
      return;
    }
    if (support) {
      if (method !== "POST" || c.res.status !== 201) return;
      const body = await c.res.clone().json() as { message_id?: number };
      // URL·payload의 사용자/역할 대신 실제 저장된 메시지와 대화 소유자를 따른다.
      const message = await c.env.DB.prepare(`SELECT sm.sender_role, sc.user_id, sc.conversation_id
        FROM support_messages sm JOIN support_conversations sc ON sc.conversation_id = sm.conversation_id
        JOIN users u ON u.user_id = sc.user_id AND u.deleted_at IS NULL
        WHERE sm.message_id = ? AND sm.conversation_id = ? AND sm.sender_id = ?`)
        .bind(body.message_id ?? 0, Number(support[1]), c.get("authUserId"))
        .first<{ sender_role: string; user_id: number; conversation_id: number }>();
      if (!message) return;
      const recipients = message.sender_role === "USER" ? await activeAdminIds(c.env.DB) : [message.user_id];
      await publish(c.env, recipients, {
        type: "change", event_id: crypto.randomUUID(), scope: "support", conversation_id: message.conversation_id,
      });
      return;
    }
    if (creatingReservation || creatingRoom) {
      const body = await c.res.clone().json() as { reservation_id?: number; room_id?: number };
      target = await audience(c.env.DB, creatingReservation ? "reservation" : "chat", Number(creatingReservation ? body.reservation_id : body.room_id));
    }
    if (!target) return;
    const scope = diary || photo || reservation?.[2] === "diaries" ? "diary" : reservation || creatingReservation ? "reservation" : "chat";
    const event: Change = {
      type: "change", event_id: crypto.randomUUID(), scope,
      ...(target.room_id ? { room_id: target.room_id } : {}),
      ...(target.reservation_id ? { reservation_id: target.reservation_id } : {}),
    };
    const userIds = [...new Set([target.user_id, target.owner_id].filter((id): id is number => !!id))];
    await publish(c.env, userIds, event);
  } catch (error) {
    // DB 쓰기의 성공을 WebSocket 전송 실패로 뒤집지 않는다. 재연결/복귀 시 영속 피드로 복구한다.
    console.error("realtime invalidation failed", error);
  }
};
