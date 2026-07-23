# 푸시 알림 설계 — 서버 이벤트 피드 + 로컬 알림 (2026-07-18)

## 배경과 제약

Apple Developer Program 유료 멤버십이 없어 **APNs 원격 푸시는 불가**하다 (FCM도 iOS에서는 APNs를 경유하므로 동일 제약). 따라서 다음 구조로 구현한다:

> **서버는 "이 사용자에게 새로 생긴 일"을 알려주는 통합 이벤트 피드 하나를 제공하고,
> iOS가 이를 폴링해 로컬 알림(UNUserNotificationCenter)으로 번역한다.**

- **포그라운드**: 앱 사용 중 30초 주기 폴링 → 시스템 배너로 확실히 동작.
- **백그라운드**: `BGAppRefreshTask`가 iOS 재량으로 깨어날 때 같은 폴링 1회 — 실행 시점 보장 없음(보통 15분+, 사용 패턴 학습에 따름). 이 한계는 수용한다.
- 유료 멤버십 확보 시 같은 피드 구조 위에 APNs 발송만 얹으면 원격 푸시로 전환 가능 (전방호환).

## 요구사항 (사용자 확정)

1. 알림 대상 4종: **새 채팅·시스템 메시지**(양쪽), **새 예약 요청**(사장님), **예약 확정**(고객), **고객 취소**(사장님).
2. 포그라운드 배너 + 백그라운드 BGAppRefresh 병행.
3. 알림 탭 시 관련 화면으로 딥링크.
4. **각 이벤트는 푸시 1회만** — 중복 금지.
5. 고객 취소는 채팅 자동 메시지 없이 **알림으로만** 사장님에게 전달 (기존 "고객 본인 취소에 메시지를 보내지 말 것" 규칙 유지).

## 중복 방지 불변식

각 이벤트는 정확히 **하나의 축**으로만 피드에 들어간다:

| 축 | 소스 | 포함 이벤트 |
|---|---|---|
| 채팅 축 | `chat_messages` 파생 | 일반 메시지, 알림장 도착, 사장님 취소 안내, 리뷰 요청, 예약 요청 완료 확인 — 모두 이미 채팅 메시지(sender 0 포함)가 존재 |
| 예약 축 | `reservations` 파생 | 새 예약 요청(사장님), 예약 확정(고객), 고객 취소(사장님) — 채팅 메시지가 **없는** 이벤트만 |

- 예약 확정은 현행 confirm 핸들러가 `UPDATE`만 수행하고 시스템 메시지를 남기지 않음을 코드로 확인했다(2026-07-18) — 예약 축 항목이 유일한 알림이다. **향후 확정 시 시스템 메시지를 추가하게 되면 예약 축의 `reservation_confirmed` 항목을 제거해 1회 원칙을 유지할 것.**
- 클라이언트 커서는 단조 전진만 하므로 재폴링·앱 재시작에도 같은 이벤트를 두 번 발행하지 않는다. 로컬 알림 identifier도 이벤트 고유값(`chat-<message_id>`, `confirmed-<reservation_id>` 등)으로 부여해 이중 안전장치로 삼는다.

## 백엔드 변경

### 1) 마이그레이션 `0013_reservation_status_times.sql`

```sql
ALTER TABLE reservations ADD COLUMN confirmed_at TEXT;
ALTER TABLE reservations ADD COLUMN canceled_at TEXT;
ALTER TABLE reservations ADD COLUMN canceled_by TEXT; -- 'USER' | 'OWNER'
```

### 2) 기존 핸들러 수정 (각 한 줄 수준)

- `PATCH /api/reservations/:id/confirm` — `confirmed_at = CURRENT_TIMESTAMP` 기록.
- `PATCH /api/reservations/:id/cancel` — `canceled_at = CURRENT_TIMESTAMP`, `canceled_by = by_owner ? 'OWNER' : 'USER'` 기록. 사장님 취소의 채팅 자동 메시지는 기존 그대로, 고객 취소는 메시지 없이 컬럼 기록만.

### 3) `GET /api/users/:id/notifications` 신설

쿼리 파라미터: `cursor` 하나 (이전 응답의 `cursor` 객체를 JSON 문자열로 그대로 전달, optional). 서버가 파싱해 내부 필드(`message_id`, `request_id`, `confirmed_at`, `canceled_at`)로 각 축을 조회한다 — 클라이언트는 끝까지 내용을 해석하지 않는다.

- **첫 호출(`cursor` 없음)**: `notifications: []` + 현재 커서만 반환 — 신규 로그인 시 과거 이벤트 알림 폭탄 방지.
- **채팅 축**: 기존 unread-count의 합산 스코프 재사용 — ① 내가 손님인 방의 상대·시스템 메시지, ② (사장님이면) 내 가게 방의 손님 메시지(sender 0 제외, 내가 손님인 방 제외). `message_id > after_message` 중 **방별 최신 1건**만 항목화(연속 메시지 알림 폭탄 방지), 2건 이상이면 body 끝에 " 외 N건".
- **예약 요청**: 내 가게(`stores.owner_id = me`) + `status = 'REQUEST'` + `reservation_id > after_request`. 가게명·강아지명 조인.
- **예약 확정**: `user_id = me` + `confirmed_at > after_confirmed`. 가게명 조인.
- **고객 취소**: 내 가게 + `canceled_by = 'USER'` + `canceled_at > after_canceled`. 가게명·강아지명 조인.

응답 형식:

```json
{
  "notifications": [
    {"type": "chat", "title": "멍멍유치원", "body": "네~ 가능합니다", "room_id": 5, "as_owner": false, "store_type": "유치원"},
    {"type": "chat", "title": "김보호자", "body": "예약 문의드려요 외 2건", "room_id": 7, "as_owner": true},
    {"type": "reservation_request", "title": "새 예약 요청", "body": "상민이 보호자의 시간권 요청 — 멍멍유치원", "reservation_id": 12},
    {"type": "reservation_confirmed", "title": "예약 확정", "body": "멍멍유치원 예약이 확정되었어요 — 2026-07-20 (일) 14:00", "reservation_id": 9},
    {"type": "reservation_canceled", "title": "예약 취소", "body": "상민이 보호자가 2026-07-20 (일) 예약을 취소했어요 — 멍멍유치원", "reservation_id": 11}
  ],
  "cursor": {"message_id": 69, "request_id": 12, "confirmed_at": "2026-07-18 12:00:00", "canceled_at": "2026-07-18 12:00:00"}
}
```

- `cursor`는 서버가 구성해 내려주고, **iOS는 내용을 해석하지 않고 그대로 저장했다가 다음 요청에 되돌려준다**(opaque). 이벤트가 없어도 cursor는 항상 현재값으로 반환.
- 채팅 title 규칙: 손님 시점 = 가게명, 사장님 시점 = 손님 닉네임, 시스템 메시지(sender 0) = '맡겨멍'. `as_owner`는 딥링크 시 `chatRoomAsOwner` 설정에 사용.
- 채팅 항목의 `store_type`(손님 시점만): 딥링크 시 `chatRoomAvatar`를 기존 규칙(손님 시점 = 가게 타입 아이콘, 사장님 시점 = room_id 기반 강아지 아바타)대로 정하는 데 필요.
- 시각 커서(`confirmed_at`/`canceled_at`)는 `>` 비교라 같은 초에 연달아 발생한 이벤트를 놓칠 수 있으나, 데모 트래픽에서는 실질 발생 가능성이 없어 수용한다.
- **예약 요청 축은 상태 기반**(`status = 'REQUEST'`)이라 채팅 축·확정 축·취소 축(모두 append-only)과 달리 이벤트가 사라질 수 있다 — 사장님이 알림 피드를 폴링하기 전에 별도 화면(`/api/owners/:id/reservations/pending`)에서 먼저 해당 예약을 확정/취소하면 그 사이 상태가 REQUEST를 벗어나 "새 요청" 알림이 조용히 유실된다(Task 2 리뷰 2026-07-23 발견). 이 경우는 사장님이 이미 그 예약을 인지·처리한 뒤라 실질 피해가 없어(놓치는 건 알림 표시 자체뿐, 예약 처리 누락 아님) 데모 범위 한계로 수용한다.
- 요청 바디 없음(GET). 응답 타입은 기존 컨벤션대로 명시적 타입 정의, `any` 금지.

### 범위 외 (백엔드)

- 인증 없음(user_id 클라이언트 신뢰)은 기존 데모 한계 그대로 — 이 엔드포인트도 동일.

## iOS 변경

### 신규: `AppNotificationService.swift`

폴링과 로컬 알림 발행 전담. `@MainActor` 클래스, `RootView`에서 소유.

- **포그라운드 폴링**: `RootView`의 `.task(id: userId)`에서 30초 주기 — 로그인 상태 + `scenePhase == .active`일 때만. 응답의 각 항목을 `UNUserNotificationCenter.add()`로 즉시 발행 (`userInfo` = type, room_id, reservation_id, as_owner, title).
- **포그라운드 배너 표시**: delegate `willPresent`에서 `.banner, .sound` 반환 — 커스텀 배너 UI를 만들지 않고 시스템 배너 사용 (알림 센터 누적 + 탭 처리 경로 통일).
- **억제 규칙**: 현재 열려 있는 채팅방(`router.selectedRoomId`)과 같은 `room_id`의 chat 알림은 발행 스킵 — 3초 폴링으로 이미 화면에 보이는 중.
- **커서 저장**: UserDefaults `notification_cursor_<userId>` (계정별 — `recent_pins_<userId>` 패턴). 커서 없으면 첫 폴링은 커서 수신만 하고 알림 무발행.

### 알림 권한

로그인 후 홈 최초 진입 시 `requestAuthorization([.alert, .sound])`. 거부 시 폴링은 유지하되 알림만 안 뜸 — 기존 종 아이콘 빨간 점이 폴백. 뱃지 권한은 요청하지 않음(범위 외).

### BGAppRefreshTask

- `Info.plist`: `BGTaskSchedulerPermittedIdentifiers`에 `net.suyoung.Dog-kindergarden.refresh` 추가 + `UIBackgroundModes` = `fetch`.
- 앱 백그라운드 진입 시(`scenePhase == .background`) `BGTaskScheduler.submit`. 핸들러: 같은 폴링 1회 → 알림 발행 → 재스케줄. 만료 핸들러에서 작업 취소.
- 시뮬레이터 시연: Xcode 디버거 `_simulateLaunchForTaskWithIdentifier` 트리거 사용.

### 딥링크 (delegate `didReceive`)

`userInfo` 파싱 후 `AppRouter`로 이동 — 기존 채팅방 진입점 패턴 준수:

| type | 이동 |
|---|---|
| `chat` | `chatRoomAsOwner = as_owner`, `selectedRoomId`, `selectedChat = title`, `chatRoomAvatar`(기존 진입점과 같은 규칙) 설정 → `.chatRoom` |
| `reservation_confirmed` | `.reservationList` |
| `reservation_request`, `reservation_canceled` | `.ownerMode` |

- **콜드 스타트에서 알림 탭**: 세션 복원 전이라 즉시 라우팅 불가 → `pendingDeepLink`에 보관했다가 홈 진입 완료 시 1회 소비.

### 계정 전환·로그아웃

- 로그아웃 시 `removeAllDeliveredNotifications()` + pending 요청 제거 — 다른 계정 알림 잔존 방지 (`AppRouter.reset`의 세션 정리 원칙과 동일 맥락).
- 커서는 계정별 키라 잔존해도 무해 — 재로그인 시 그 계정의 커서에서 이어짐.

### 델리게이트 배선

`UNUserNotificationCenterDelegate`는 앱 시작 시점에 설정해야 함 — 기존 앱 엔트리(카카오 SDK 초기화 지점)에 연결. 정확한 위치는 구현 계획 단계에서 확인.

## 범위 외 (v2)

- 원격 푸시(APNs/FCM) — 유료 멤버십 확보 후 이 피드 구조를 재사용해 서버 발송만 추가.
- 앱 아이콘 뱃지 카운트.
- 알림 종류별 on/off 설정 화면.
- 고객 취소 외 이벤트의 추가 세분화(예: 예약 변경).

## 검증 계획

**백엔드** — `npx tsc --noEmit` → 마이그레이션 0013 로컬·원격 적용 → 배포 → curl 시나리오:

1. 커서 없이 첫 호출 → `notifications: []` + 커서 반환.
2. 손님 계정으로 메시지 전송 → 사장님 피드에 chat 항목(`as_owner: true`) + 커서 증분.
3. 같은 방에 연속 3건 전송 → 항목 1건 + "외 2건".
4. 예약 요청 생성 → 사장님 피드에 `reservation_request`.
5. 확정 → 고객 피드에 `reservation_confirmed` 1건만 (채팅 항목 없음 = 중복 없음 확인).
6. 고객 취소 → 사장님 피드에 `reservation_canceled`, 고객 채팅방에 메시지 없음 확인.
7. 같은 커서로 재호출 → 동일 이벤트 재등장 없음(커서 전진 확인).
8. 받은 커서로 재호출 → 빈 목록.

**iOS** — xcodebuild BUILD SUCCEEDED → 시뮬레이터에서 `dev-simulator` ↔ `dev-simulator-owner` 전환 시나리오:

1. 홈 진입 시 알림 권한 프롬프트.
2. 상대 계정이 메시지 전송(또는 curl로 주입) → 30초 내 배너 표시, 탭 시 해당 채팅방 진입(`chatRoomAsOwner` 올바름).
3. 열려 있는 채팅방의 메시지는 배너 미표시(억제 규칙).
4. 예약 확정 → 고객 배너 1회, 탭 시 예약 내역.
5. 고객 취소 → 사장님 배너, 탭 시 받은 예약 요청 화면.
6. BGAppRefresh 디버그 트리거로 백그라운드 경로 시연.
7. 로그아웃 → 알림 센터에서 이전 계정 알림 제거 확인.
