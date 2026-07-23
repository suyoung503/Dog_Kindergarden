# 푸시 알림(서버 이벤트 피드 + 로컬 알림) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 원격 푸시(APNs) 불가 제약 아래, 서버 통합 이벤트 피드를 iOS가 폴링해 로컬 알림으로 발행하고 탭 시 관련 화면으로 딥링크한다.

**Architecture:** 백엔드에 `GET /api/users/:id/notifications`(opaque 커서 기반 증분 피드)를 신설하고, iOS `AppNotificationService`가 포그라운드 30초 폴링 + `BGAppRefreshTask`로 이를 소비해 `UNUserNotificationCenter` 로컬 알림으로 번역한다. 이벤트는 채팅 축(`chat_messages` 파생)과 예약 축(`reservations` + 0013 컬럼) 중 정확히 한 축으로만 들어가 푸시 1회를 보장한다.

**Tech Stack:** Cloudflare Workers(Hono, D1) / Swift 5.9, SwiftUI + Observation, UserNotifications, BackgroundTasks

**설계 문서:** `docs/superpowers/specs/2026-07-18-push-notifications-design.md` (승인됨 — 요구사항·불변식은 이 문서가 기준)

## Global Constraints

- **git 작업(add/commit/push)은 전부 사용자가 직접 실행한다.** 각 태스크의 커밋 스텝은 "커밋 명령을 텍스트로 제시하고 사용자 실행을 기다림"으로 수행한다. 커밋 메시지에 `Co-Authored-By` 트레일러 금지. 커밋 메시지는 한국어.
- 테스트 프레임워크 없음(프로젝트 컨벤션). 백엔드 검증 = `npx tsc --noEmit` + 마이그레이션 적용 + 배포 + curl 시나리오. iOS 검증 = `xcodebuild ... build` + 시뮬레이터.
- 백엔드 스키마 변경은 `migrations/` 번호 순 SQL로만 — 이번 파일은 `0013_reservation_status_times.sql`.
- wrangler 명령은 반드시 `backend-cloudflare/` 디렉토리에서 실행.
- TypeScript `any` 금지. iOS `userId`는 `AuthSession.userId` guard — `?? 1` 폴백 금지.
- 배포 URL: `https://matgyeomung-api.dog-kindergarden.workers.dev`. D1 이름: `dog_kindergarden_db`.
- 번들 ID: `net.suyoung.Dog-kindergarden`. BG 태스크 식별자: `net.suyoung.Dog-kindergarden.refresh`.
- index.ts export는 `{ fetch: app.fetch, scheduled }` 형태 — `export default app`으로 되돌리지 말 것.
- curl 테스트로 만든 일회용 데이터(예약·메시지)는 검증 후 삭제하되, 기존 실데이터는 건드리지 않는다.

---

### Task 1: 백엔드 — 마이그레이션 0013 + 확정/취소 시각 기록

**Files:**
- Create: `backend-cloudflare/migrations/0013_reservation_status_times.sql`
- Modify: `backend-cloudflare/src/index.ts` — confirm 핸들러(현재 479행 부근), cancel 핸들러(현재 387행 부근)

**Interfaces:**
- Consumes: 기존 `reservations` 테이블, `ReservationCancelBody`(`by_owner`/`byOwner` 겸용, 이미 존재)
- Produces: `reservations.confirmed_at TEXT`, `canceled_at TEXT`, `canceled_by TEXT('USER'|'OWNER')` — Task 2의 피드 쿼리가 사용

- [ ] **Step 1: 마이그레이션 파일 작성**

`backend-cloudflare/migrations/0013_reservation_status_times.sql`:

```sql
-- 알림 피드용 예약 상태 전환 시각 (설계: docs/superpowers/specs/2026-07-18-push-notifications-design.md)
-- confirmed_at: 확정 시각 (고객 '예약 확정' 알림 커서)
-- canceled_at/canceled_by: 취소 시각·주체 (canceled_by='USER'만 사장님 '고객 취소' 알림 대상)
ALTER TABLE reservations ADD COLUMN confirmed_at TEXT;
ALTER TABLE reservations ADD COLUMN canceled_at TEXT;
ALTER TABLE reservations ADD COLUMN canceled_by TEXT;
```

- [ ] **Step 2: confirm 핸들러에 시각 기록**

`src/index.ts`의 confirm 핸들러에서 UPDATE 문만 교체:

```ts
// 예약 확정 — 상태 변경 + 확정 시각 기록(알림 피드 커서용)
app.patch("/api/reservations/:id/confirm", async (c) => {
  const reservationId = Number(c.req.param("id"));
  await c.env.DB.prepare(
    `UPDATE reservations SET status = 'CONFIRMED', confirmed_at = CURRENT_TIMESTAMP WHERE reservation_id = ?`,
  )
    .bind(reservationId)
    .run();
  return c.json({ ok: true });
});
```

- [ ] **Step 3: cancel 핸들러에 시각·주체 기록**

cancel 핸들러의 UPDATE 문만 교체 (byOwner 분기·자동 메시지 로직은 그대로 둔다 — 고객 취소는 메시지 없이 컬럼 기록만이 알림 신호):

```ts
  await c.env.DB.prepare(
    `UPDATE reservations SET status = 'CANCELED', canceled_at = CURRENT_TIMESTAMP, canceled_by = ? WHERE reservation_id = ?`,
  )
    .bind(byOwner ? "OWNER" : "USER", reservationId)
    .run();
```

- [ ] **Step 4: 타입 검사**

Run (backend-cloudflare/): `npx tsc --noEmit`
Expected: 출력 없음(성공)

- [ ] **Step 5: 마이그레이션 적용 (로컬 → 원격)**

Run (backend-cloudflare/): `npx wrangler d1 migrations apply dog_kindergarden_db` 후 `npx wrangler d1 migrations apply dog_kindergarden_db --remote`
Expected: `0013_reservation_status_times.sql` 적용 성공

- [ ] **Step 6: 배포 + 컬럼 기록 확인**

Run (backend-cloudflare/): `npx wrangler deploy`
그다음 기존 REQUEST 상태 예약이 있으면 그대로, 없으면 curl로 임시 예약 생성(`POST /api/reservations` — 바디 필드는 `src/index.ts`의 `ReservationBody` 타입 참고, snake/camel 겸용) 후:

```bash
curl -sX PATCH "https://matgyeomung-api.dog-kindergarden.workers.dev/api/reservations/<id>/confirm"
npx wrangler d1 execute dog_kindergarden_db --remote --command "SELECT reservation_id, status, confirmed_at, canceled_at, canceled_by FROM reservations WHERE reservation_id = <id>"
```

Expected: `confirmed_at`에 타임스탬프. 취소도 같은 방식으로 `canceled_at`·`canceled_by='USER'`(바디 없이) / `'OWNER'`(`-d '{"by_owner":true}'`) 확인. 임시 데이터는 확인 후 원복(취소 처리로 충분).

- [ ] **Step 7: 커밋 명령 제시 (사용자 실행)**

```bash
git add backend-cloudflare/migrations/0013_reservation_status_times.sql backend-cloudflare/src/index.ts
git commit -m "feat: 예약 확정·취소 시각/주체 기록 — 알림 피드 커서용 (마이그레이션 0013)"
```

---

### Task 2: 백엔드 — 통합 알림 피드 `GET /api/users/:id/notifications`

**Files:**
- Modify: `backend-cloudflare/src/index.ts` — unread-count 핸들러(현재 766행 부근) 아래에 신설

**Interfaces:**
- Consumes: Task 1의 `confirmed_at`/`canceled_at`/`canceled_by`, 기존 unread-count의 채팅 스코프 로직
- Produces: 응답 `{ notifications: NotificationItem[], cursor: NotificationCursor }` — Task 3의 iOS 폴링이 소비. `NotificationItem = { type: "chat"|"reservation_request"|"reservation_confirmed"|"reservation_canceled", title, body, room_id?, reservation_id?, as_owner?, store_type? }`

- [ ] **Step 1: 타입 + 라우트 구현**

unread-count 핸들러 바로 아래에 추가:

```ts
// MARK: - 통합 알림 피드 (설계: docs/superpowers/specs/2026-07-18-push-notifications-design.md)
// 중복 방지 불변식: 채팅 메시지를 남기는 이벤트(알림장·사장님 취소·리뷰 요청 등)는 채팅 축으로만,
// 메시지가 없는 이벤트(새 요청·확정·고객 취소)는 예약 축으로만 들어간다 — 이벤트당 알림 1회.

type NotificationCursor = {
  message_id?: number;
  request_id?: number;
  confirmed_at?: string;
  canceled_at?: string;
};

type NotificationItem = {
  type: "chat" | "reservation_request" | "reservation_confirmed" | "reservation_canceled";
  title: string;
  body: string;
  room_id?: number;
  reservation_id?: number;
  as_owner?: boolean;
  store_type?: string;
};

app.get("/api/users/:id/notifications", async (c) => {
  const userId = Number(c.req.param("id"));
  if (!userId) return c.json({ message: "user id required" }, 400);
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
  const now = await c.env.DB.prepare(`SELECT CURRENT_TIMESTAMP AS v`).first<{ v: string }>();
  const nextCursor: NotificationCursor = {
    message_id: maxMsg?.v ?? 0,
    request_id: maxRes?.v ?? 0,
    confirmed_at: now?.v ?? "",
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
  const afterConfirmed = cursor.confirmed_at ?? "";
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
    LEFT JOIN stores s ON s.store_id = r.store_id
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
      JOIN stores s ON s.store_id = r.store_id AND s.owner_id = ?
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
      JOIN stores s ON s.store_id = r.store_id AND s.owner_id = ?
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

  // ── 예약 축 (고객) 예약 확정 — 확정 시스템 메시지는 없으므로 이 항목이 유일한 알림(1회 원칙)
  if (afterConfirmed) {
    const confirmed = await c.env.DB.prepare(
      `
      SELECT r.reservation_id, COALESCE(r.store_name, s.name) AS store_name, r.start_date
      FROM reservations r
      LEFT JOIN stores s ON s.store_id = r.store_id
      WHERE r.user_id = ? AND r.confirmed_at IS NOT NULL AND r.confirmed_at > ?
      ORDER BY r.confirmed_at
    `,
    )
      .bind(userId, afterConfirmed)
      .all<{ reservation_id: number; store_name: string | null; start_date: string }>();
    for (const row of confirmed.results) {
      items.push({
        type: "reservation_confirmed",
        title: "예약 확정",
        body: `${row.store_name ?? "가게"} 예약이 확정되었어요 — ${row.start_date}`,
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
      JOIN stores s ON s.store_id = r.store_id AND s.owner_id = ?
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

  return c.json({ notifications: items, cursor: nextCursor });
});
```

- [ ] **Step 2: 타입 검사**

Run (backend-cloudflare/): `npx tsc --noEmit`
Expected: 출력 없음(성공)

- [ ] **Step 3: 배포**

Run (backend-cloudflare/): `npx wrangler deploy`
Expected: `Deployed matgyeomung-api` + `schedule: 0 9 * * *` 유지 확인

- [ ] **Step 4: curl 시나리오 검증 (설계 문서의 8단계)**

`dev-simulator`(견주)·`dev-simulator-owner`(사장님) 계정의 user_id를 DB에서 조회한 뒤:

1. `curl -s ".../api/users/<uid>/notifications"` → `{"notifications":[],"cursor":{...}}` (커서만).
2. 받은 `cursor`를 URL 인코딩해 `?cursor=...`로 재호출 → 빈 목록.
3. 손님이 사장님 가게 방에 메시지 전송(`POST /api/chatrooms/:id/messages`) → 사장님 피드에 `type:"chat", as_owner:true` 항목 + `cursor.message_id` 증가.
4. 같은 방에 2건 더 전송 → 항목 1건에 `"... 외 2건"`.
5. 예약 요청 생성 → 사장님 피드에 `reservation_request`.
6. 확정(`PATCH .../confirm`) → 손님 피드에 `reservation_confirmed` 1건, 같은 응답에 이 예약 관련 `chat` 항목 없음(중복 없음 확인).
7. 고객 취소(`PATCH .../cancel` 바디 없음) → 사장님 피드에 `reservation_canceled`, 손님 방에 새 메시지 없음 확인.
8. 각 단계 후 받은 커서로 재호출 → 동일 이벤트 재등장 없음.

Expected: 위 8단계 모두 통과. 테스트로 만든 예약·메시지는 검증 후 삭제.

- [ ] **Step 5: 커밋 명령 제시 (사용자 실행)**

```bash
git add backend-cloudflare/src/index.ts
git commit -m "feat: 통합 알림 피드 GET /api/users/:id/notifications — 채팅·예약 이벤트 증분 조회(opaque 커서)"
```

---

### Task 3: iOS — `AppNotificationService` (폴링 + 로컬 알림 발행 + 커서)

**Files:**
- Create: `Dog_kindergarden/Dog_kindergarden/Views/Notification/AppNotificationService.swift`
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/RootView.swift` — 서비스 주입 + 폴링 task
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/Chat/ChatRoomView.swift` — 열려 있는 방 알림 억제용 `activeRoomId` 설정

**Interfaces:**
- Consumes: Task 2 응답 형식, `apiBaseURL`(ReviewService.swift 전역), `AuthSession.userId`
- Produces: `AppNotificationService.shared` 싱글턴 — `configure(userId:)`, `requestPermission()`, `pollLoop()`, `pollOnce()`, `var pendingDeepLink: NotificationDeepLink?`, `var activeRoomId: Int?`. `enum NotificationDeepLink: Equatable { case chat(roomId: Int, title: String, asOwner: Bool, storeType: String?), reservationList, ownerMode }` — Task 4·5가 사용

- [ ] **Step 1: 서비스 파일 작성**

`Views/Notification/AppNotificationService.swift` (Xcode에서 새 그룹 Notification 아래 추가):

```swift
import Foundation
import UserNotifications
import Observation

// 알림 피드 항목 — 서버 snake_case 그대로 (ChatService 패턴)
struct NotificationItemDTO: Decodable {
    let type: String
    let title: String
    let body: String
    let room_id: Int?
    let reservation_id: Int?
    let as_owner: Bool?
    let store_type: String?
}

// 알림 탭 딥링크 — RootView가 소비해 AppRouter로 이동
enum NotificationDeepLink: Equatable {
    case chat(roomId: Int, title: String, asOwner: Bool, storeType: String?)
    case reservationList
    case ownerMode
}

// 서버 이벤트 피드 폴링 → 로컬 알림 발행 (원격 푸시 불가 제약 우회 — 설계 문서 참고)
@Observable
@MainActor
final class AppNotificationService: NSObject {
    static let shared = AppNotificationService()

    var pendingDeepLink: NotificationDeepLink? = nil
    var activeRoomId: Int? = nil   // 열려 있는 채팅방 — 그 방의 chat 알림은 배너 생략
    private var userId: Int? = nil

    func configure(userId: Int?) {
        self.userId = userId
    }

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    // 포그라운드 폴링 루프 — 앱이 백그라운드로 가면 프로세스 서스펜드로 자연히 멈춘다
    func pollLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
    }

    func pollOnce() async {
        guard let userId else { return }
        var comps = URLComponents(string: "\(apiBaseURL)/api/users/\(userId)/notifications")!
        let cursorKey = "notification_cursor_\(userId)"
        if let cursor = UserDefaults.standard.string(forKey: cursorKey) {
            comps.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // 커서는 해석하지 않고 문자열 그대로 저장(opaque) — 다음 요청에 그대로 되돌려준다
        if let cursorDict = json["cursor"],
           let cursorData = try? JSONSerialization.data(withJSONObject: cursorDict),
           let cursorString = String(data: cursorData, encoding: .utf8) {
            UserDefaults.standard.set(cursorString, forKey: cursorKey)
        }

        guard let rawItems = json["notifications"],
              let itemsData = try? JSONSerialization.data(withJSONObject: rawItems),
              let items = try? JSONDecoder().decode([NotificationItemDTO].self, from: itemsData) else { return }
        for item in items { publish(item) }
    }

    private func publish(_ item: NotificationItemDTO) {
        if item.type == "chat", let roomId = item.room_id, roomId == activeRoomId { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.userInfo = [
            "type": item.type,
            "room_id": item.room_id ?? 0,
            "reservation_id": item.reservation_id ?? 0,
            "as_owner": item.as_owner ?? false,
            "title": item.title,
            "store_type": item.store_type ?? "",
        ]
        // identifier를 이벤트 대상 기준으로 고정 — 같은 방 재알림은 교체되어 알림 센터에 방당 1개 유지
        let idSeed = item.room_id ?? item.reservation_id ?? 0
        let request = UNNotificationRequest(
            identifier: "\(item.type)-\(idSeed)", content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 2: RootView 배선**

`RootView.swift` 수정 — 서비스 주입 + 기존 `.task(id: authSession.userId)` 확장:

```swift
struct RootView: View {
    @State private var router = AppRouter()
    @State private var boarding = BoardingStore()
    @State private var tagStore = TagStore()
    @State private var userProfile = UserProfile()
    @State private var authSession = AuthSession()
    @State private var notificationService = AppNotificationService.shared

    var body: some View {
        currentScreen
            .environment(router)
            .environment(boarding)
            .environment(tagStore)
            .environment(userProfile)
            .environment(authSession)
            .environment(notificationService)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: router.current)
            .task {
                await boarding.loadIfNeeded()
                await tagStore.load()
            }
            // 로그인/로그아웃/콜드 런치 세션 복원 시 계정별 상태 복원 + 알림 폴링 시작
            .task(id: authSession.userId) {
                router.setActiveUser(authSession.userId)
                notificationService.configure(userId: authSession.userId)
                // 계정 전환 시 이전 계정 알림 잔존 방지
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                guard authSession.userId != nil else { return }
                await notificationService.requestPermission()
                await notificationService.pollLoop()   // 로그아웃/계정 전환 시 task 취소로 종료
            }
    }
```

파일 상단에 `import UserNotifications` 추가.

- [ ] **Step 3: ChatRoomView에 activeRoomId 설정**

`ChatRoomView.swift`의 첫 번째 `.task`(configure/load 하는 곳) 끝에 추가하고, `.onDisappear` 신설:

```swift
            // 이 방을 보는 동안은 이 방의 채팅 알림 배너 생략 (3초 폴링으로 이미 화면에 보임)
            AppNotificationService.shared.activeRoomId = router.selectedRoomId
```

```swift
        .onDisappear { AppNotificationService.shared.activeRoomId = nil }
```

- [ ] **Step 4: 빌드 검증**

Run: `cd Dog_kindergarden && xcodebuild -workspace Dog_kindergarden.xcworkspace -scheme Dog_kindergarden -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 시뮬레이터 동작 확인**

시뮬레이터에서 `dev-simulator` 로그인 → 권한 프롬프트 허용 → 홈 대기 중 curl로 그 계정 방에 메시지 주입(sender는 상대) → 30초 내 배너 표시 확인. 열려 있는 채팅방의 메시지는 배너가 안 뜨는 것도 확인.
Expected: 배너 표시(제목=가게명/보호자명, 본문=메시지), 열린 방은 억제.

- [ ] **Step 6: 커밋 명령 제시 (사용자 실행)**

```bash
git add Dog_kindergarden/Dog_kindergarden/Views/Notification/AppNotificationService.swift Dog_kindergarden/Dog_kindergarden/Views/RootView.swift Dog_kindergarden/Dog_kindergarden/Views/Chat/ChatRoomView.swift Dog_kindergarden/Dog_kindergarden.xcodeproj/project.pbxproj
git commit -m "feat: 알림 피드 폴링 + 로컬 알림 발행 — AppNotificationService(30초 폴링, opaque 커서, 열린 방 억제)"
```

---

### Task 4: iOS — 알림 델리게이트 + 탭 딥링크

**Files:**
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/Notification/AppNotificationService.swift` — 델리게이트 채택
- Modify: `Dog_kindergarden/Dog_kindergarden/AppDelegate.swift` — 델리게이트 연결
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/RootView.swift` — pendingDeepLink 소비

**Interfaces:**
- Consumes: Task 3의 `AppNotificationService.shared`, `NotificationDeepLink`, 로컬 알림 `userInfo` 키(type/room_id/reservation_id/as_owner/title/store_type), `dogAvatarName(_:)`(EmojiIcon.swift 전역)
- Produces: 알림 탭 → `pendingDeepLink` 설정 → RootView `consumeDeepLink`가 `AppRouter`로 이동. 포그라운드 배너 표시(`willPresent`)

- [ ] **Step 1: 델리게이트 확장 추가**

`AppNotificationService.swift` 하단에 추가:

```swift
// 포그라운드 배너 표시 + 알림 탭 딥링크
extension AppNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String ?? ""
        let roomId = info["room_id"] as? Int ?? 0
        let asOwner = info["as_owner"] as? Bool ?? false
        let title = info["title"] as? String ?? "채팅"
        let storeType = info["store_type"] as? String ?? ""

        let link: NotificationDeepLink?
        switch type {
        case "chat" where roomId > 0:
            link = .chat(roomId: roomId, title: title, asOwner: asOwner,
                         storeType: storeType.isEmpty ? nil : storeType)
        case "reservation_confirmed":
            link = .reservationList
        case "reservation_request", "reservation_canceled":
            link = .ownerMode
        default:
            link = nil
        }
        guard let link else { return }
        await MainActor.run { AppNotificationService.shared.pendingDeepLink = link }
    }
}
```

- [ ] **Step 2: AppDelegate에서 델리게이트 연결**

`AppDelegate.swift`의 `didFinishLaunchingWithOptions`에 추가 (파일 상단 `import UserNotifications`):

```swift
        // 로컬 알림 포그라운드 표시·탭 딥링크 델리게이트
        UNUserNotificationCenter.current().delegate = AppNotificationService.shared
```

- [ ] **Step 3: RootView에서 딥링크 소비**

`RootView.swift`의 `currentScreen` 체인에 추가 + 소비 함수:

```swift
            // 알림 탭 딥링크 — 로그인 상태면 즉시, 콜드 스타트면 세션 복원 후 소비
            // (주의: iOS 16 타깃 — onChange 클로저는 단일 파라미터(새 값) 형태만 사용 가능)
            .onChange(of: notificationService.pendingDeepLink) { link in
                if let link, authSession.userId != nil { consumeDeepLink(link) }
            }
            .onChange(of: authSession.userId) { uid in
                if let link = notificationService.pendingDeepLink, uid != nil { consumeDeepLink(link) }
            }
```

```swift
    private func consumeDeepLink(_ link: NotificationDeepLink) {
        notificationService.pendingDeepLink = nil
        switch link {
        case .chat(let roomId, let title, let asOwner, let storeType):
            // 채팅 목록의 방 진입 패턴과 동일하게 라우터 세팅 (chatRoomAsOwner 필수)
            router.selectedChat = title
            router.selectedRoomId = roomId
            router.chatRoomAsOwner = asOwner
            router.chatRoomAvatar = asOwner
                ? "img:\(dogAvatarName(roomId))"
                : ((storeType == "호텔") ? "🏨" : "🏠")
            router.go(.chatRoom)
        case .reservationList:
            router.go(.reservationList)
        case .ownerMode:
            router.go(.ownerMode)
        }
    }
```

주의: `dogAvatarName(_:)`은 `EmojiIcon.swift`의 전역 함수(에셋 배열 순환)를 쓴다 — `OwnerDiaryListView`의 private 버전과 혼동하지 말 것.

- [ ] **Step 4: 빌드 검증**

Run: Task 3 Step 4와 동일한 xcodebuild.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 시뮬레이터 딥링크 확인**

배너 탭 → 해당 채팅방 진입(사장님 계정으로 받은 문의 알림 탭 시 말풍선 방향·'응답중' 숨김 = `chatRoomAsOwner` 올바름). 홈이 아닌 화면(마이페이지 등)에서 탭해도 이동. 예약 확정 알림 탭 → 예약 내역.
Expected: 3종 딥링크 모두 정상.

- [ ] **Step 6: 커밋 명령 제시 (사용자 실행)**

```bash
git add Dog_kindergarden/Dog_kindergarden/Views/Notification/AppNotificationService.swift Dog_kindergarden/Dog_kindergarden/AppDelegate.swift Dog_kindergarden/Dog_kindergarden/Views/RootView.swift
git commit -m "feat: 알림 탭 딥링크 — 채팅방·예약 내역·받은 요청 화면 이동, 포그라운드 배너 표시"
```

---

### Task 5: iOS — BGAppRefreshTask (백그라운드 폴링)

**Files:**
- Modify: `Dog_kindergarden/Dog_kindergarden/Info.plist`
- Modify: `Dog_kindergarden/Dog_kindergarden/AppDelegate.swift` — 태스크 등록
- Modify: `Dog_kindergarden/Dog_kindergarden/SceneDelegate.swift` — 백그라운드 진입 시 스케줄
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/Notification/AppNotificationService.swift` — 핸들러·스케줄 함수

**Interfaces:**
- Consumes: Task 3의 `pollOnce()`
- Produces: `AppNotificationService.backgroundTaskId`(String), `static func scheduleBackgroundRefresh()`, `static func handleBackgroundRefresh(_ task: BGAppRefreshTask)`

- [ ] **Step 1: Info.plist 키 추가**

```xml
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>net.suyoung.Dog-kindergarden.refresh</string>
	</array>
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
	</array>
```

- [ ] **Step 2: 서비스에 BG 지원 추가**

`AppNotificationService.swift`에 추가 (파일 상단 `import BackgroundTasks`):

```swift
    // MARK: - 백그라운드 갱신 (BGAppRefreshTask — 실행 시점은 iOS 재량, 보장 없음)

    static let backgroundTaskId = "net.suyoung.Dog-kindergarden.refresh"

    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated static func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()   // 다음 실행 재예약
        let poll = Task { @MainActor in
            await shared.pollOnce()   // 콜드 BG 런치로 userId 미설정이면 no-op (한계 수용)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            poll.cancel()
            task.setTaskCompleted(success: false)
        }
    }
```

- [ ] **Step 3: 등록·스케줄 배선**

`AppDelegate.didFinishLaunchingWithOptions`에 (파일 상단 `import BackgroundTasks`):

```swift
        // 백그라운드 알림 폴링 등록 (didFinishLaunching 리턴 전에 등록해야 함)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppNotificationService.backgroundTaskId, using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            AppNotificationService.handleBackgroundRefresh(refresh)
        }
```

`SceneDelegate.sceneDidEnterBackground`:

```swift
    func sceneDidEnterBackground(_ scene: UIScene) {
        AppNotificationService.scheduleBackgroundRefresh()
    }
```

- [ ] **Step 4: 빌드 + 시연 검증**

Run: Task 3 Step 4와 동일한 xcodebuild → `** BUILD SUCCEEDED **`
시뮬레이터: 앱 실행 → 홈 버튼으로 백그라운드 → Xcode 디버거 일시정지 후:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"net.suyoung.Dog-kindergarden.refresh"]
```

Expected: 백그라운드 상태에서 새 이벤트가 있으면 알림 센터에 알림 도착.

- [ ] **Step 5: 커밋 명령 제시 (사용자 실행)**

```bash
git add Dog_kindergarden/Dog_kindergarden/Info.plist Dog_kindergarden/Dog_kindergarden/AppDelegate.swift Dog_kindergarden/Dog_kindergarden/SceneDelegate.swift Dog_kindergarden/Dog_kindergarden/Views/Notification/AppNotificationService.swift
git commit -m "feat: BGAppRefreshTask 백그라운드 알림 폴링 — 백그라운드 진입 시 스케줄, iOS 재량 실행"
```

---

### Task 6: 종단 검증 + 문서 갱신

**Files:**
- Modify: `docs/PROGRESS.md`, `docs/FEATURES.md`, `docs/PLAN.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: Task 1~5 완료 상태
- Produces: 문서 최신화 (세션 종료 시 PROGRESS 갱신은 프로젝트 규칙)

- [ ] **Step 1: 2계정 종단 시나리오**

시뮬레이터에서 `dev-simulator` ↔ `dev-simulator-owner` 전환하며 설계 문서의 iOS 검증 7단계 전체 수행 (권한 프롬프트 / 배너+딥링크 3종 / 열린 방 억제 / BG 트리거 / 로그아웃 시 알림 제거).
Expected: 전부 통과. 실패 항목은 해당 Task로 돌아가 수정.

- [ ] **Step 2: 문서 갱신**

- `docs/PROGRESS.md` — 완료 항목 추가(구현 요약 + 검증 방법), 장기 계획 푸시 알림 항목 체크(`FCM` 표기는 "로컬 알림+피드 방식으로 대체(유료 멤버십 부재), 원격 푸시는 v2"로 수정), 마지막 업데이트 날짜.
- `docs/PLAN.md` — 장기 표의 "푸시 알림 | 중간 | FCM 연동" → ✅ 완료(피드+로컬 알림 방식, 원격 푸시는 유료 멤버십 확보 후 v2).
- `docs/FEATURES.md` — 알림 기능 섹션 추가(4종 이벤트, 포그라운드 30초/BG, 딥링크, 1회 원칙) + §11 API 표에 notifications 라우트.
- `CLAUDE.md` — 핵심 도메인 설계에 알림 피드 한 줄(중복 방지 불변식: 채팅 메시지를 남기는 이벤트는 채팅 축으로만) + 미완성 영역에 "원격 푸시(APNs) — 유료 멤버십 확보 후" 추가.

- [ ] **Step 3: 커밋 명령 제시 (사용자 실행)**

```bash
git add docs/PROGRESS.md docs/FEATURES.md docs/PLAN.md CLAUDE.md docs/superpowers/plans/2026-07-18-push-notifications.md
git commit -m "docs: 푸시 알림(피드+로컬 알림) 반영 — 기능 명세·진행상황·계획 갱신"
```
