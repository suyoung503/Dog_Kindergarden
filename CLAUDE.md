# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

**맡겨멍** — 반려견을 맡길 수 있는 애견 유치원·호텔을 지도 기반으로 탐색하고 예약하는 iOS 플랫폼.
공공데이터 동물위탁관리업 API로 전국 업체를 표시하고, 리뷰·채팅·예약 기능을 통합 제공한다.

**목표:** 포트폴리오 완성 → 이후 App Store 실제 출시까지 이어가는 로드맵.
**현재 우선 작업:** 네이버 블로그 API 키 발급 (사용자가 개인 계정으로 직접 진행 — 상세는 `docs/PLAN.md`, `docs/PROGRESS.md`).

모노레포 구성:

- `Dog_kindergarden/` — iOS 앱 (Swift 5.9, SwiftUI + Observation, iOS 16+, CocoaPods)
- `backend-cloudflare/` — 백엔드 (TypeScript, Hono, Cloudflare Workers + D1)
- `docs/` — 계획(`PLAN.md`), 진행상황(`PROGRESS.md`), 포트폴리오 기술 문서(`PORTFOLIO.md`), 기능 명세(`FEATURES.md`)

커밋 메시지·문서·코드 주석은 한국어를 사용한다. 작업 세션이 끝나면 `docs/PROGRESS.md`를 갱신한다.

## 명령어

### 백엔드 (backend-cloudflare/)

```bash
npm install
npm run dev          # 로컬 실행 (wrangler dev)
npm run deploy       # Cloudflare 배포
npm run d1:migrate   # D1 마이그레이션 적용 (로컬 DB 기본; 배포 DB는 --remote 추가)
```

- 배포 URL: `https://matgyeomung-api.dog-kindergarden.workers.dev`
- 스키마 변경은 반드시 `migrations/`에 번호 순 SQL 파일 추가로만 한다 (`0005_...` 다음은 `0006_...`).
- 테스트/린트 인프라는 없음. 타입 검사는 `npx tsc --noEmit`.

### iOS 앱 (Dog_kindergarden/)

```bash
pod install          # 최초 1회 및 Podfile 변경 시
open Dog_kindergarden.xcworkspace   # .xcodeproj가 아닌 .xcworkspace로 열 것
```

빌드·실행·테스트는 Xcode에서 한다 (스킴: `Dog_kindergarden`).

**빌드 전 필수 — Create.xcconfig:** API 키는 git에서 제외된 `Dog_kindergarden/Base.lproj/Config/Create.xcconfig`에 있고 (Xcode 빌드 설정의 `baseConfigurationReference`가 이 파일을 가리킴), `Info.plist`가 `$(변수)`로 참조한다. 파일이 없으면 지도·로그인이 동작하지 않는다. 필요한 키:

```
KAKAO_NATIVE_APP_KEY, KAKAO_REST_API_KEY, DATA_GO_KR_SERVICE_KEY,
NAVER_CLIENT_ID, NAVER_CLIENT_SECRET   ← 네이버 키는 아직 미발급 상태
```

## 아키텍처

### iOS — 커스텀 스택 내비게이션 + 환경 객체

`NavigationStack`을 쓰지 않는다. `RootView`가 `AppRouter.stack`(화면 enum 배열)의 마지막 요소를 switch로 렌더링하는 구조다.

- 화면 추가 = `AppScreen` enum에 case 추가 + `RootView`의 switch에 분기 추가 + `router.go(.화면)`으로 이동.
- 화면 간 전달 데이터는 파라미터가 아니라 `AppRouter`의 프로퍼티(`selectedPin`, `selectedRoomId`, `lastBooking` 등)에 담는다.
- 상태 모델은 전부 `@Observable` 클래스로 `RootView`에서 `.environment()`로 주입: `AppRouter`(내비게이션), `BoardingStore`(공공데이터 가게), `TagStore`(리뷰 태그), `UserProfile`(보호자 정보, UserDefaults 영속), `AuthSession`(카카오 로그인 + `isOwner` 보호자·사장님 역할, UserDefaults 영속). 뷰에서는 `@Environment(타입.self)`로 읽는다.
- 역할(보호자/사장님)로 로그인 후 진입 화면을 분기하지 않는다. 목적지는 모두 `.home`이고, 사장님 여부는 `AuthSession.isOwner`에 귀속해 홈 사이드바(FAB)에 '받은 예약 요청'만 조건부 노출한다. (진입 분기 방식은 뒤로가기·재실행 시 오라우팅을 유발해 폐기했다.)
- 역할은 **최초 가입 시 계정(서버 `users.is_owner`)에 영구 귀속**된다. 같은 카카오 계정으로 반대 역할 가입은 서버가 409로 거절하고 iOS는 안내 문구를 띄운다(역할별 데이터 분리 목적 — 견주/사장님이 채팅·찜·예약을 공유하지 않게). 개발자 진입도 역할별 별개 계정: `dev-simulator`(견주) / `dev-simulator-owner`(사장님). 로그아웃 시 `AppRouter.reset(to:)`이 스택과 함께 `recentPins`·`selectedPin`·`selectedRoomId`·`lastBooking`을 비워 계정 간 잔존 데이터를 막는다 — reset에 세션 상태 초기화를 빼먹지 말 것. '최근 본 가게'는 계정별 UserDefaults(`recent_pins_<userId>`, 최대 6개) 영속이며 `RootView`의 `.task(id: userId)`가 `router.setActiveUser()`로 로그인 계정 것을 복원한다 — `recentPins` 갱신은 직접 배열 조작 대신 `router.addRecentPin()`을 쓸 것.
- 화면 상단 여백은 `.safeAreaTopPadding()`(`SafeAreaKey.swift`)를 쓴다. `body`에서 `UIApplication.safeAreaTop`을 직접 읽으면(`.padding(.top, UIApplication.safeAreaTop + 12)`) 콜드 런치 때 레이아웃 피드백 순환(AttributeGraph cycle)이 생겨 그 화면이 얼어붙는다 — 특히 초기 화면. 상세는 `docs/PORTFOLIO.md` §7.

### iOS — API 연결

`APIClient.shared`가 기본 REST 레이어. snake_case↔camelCase 변환은 JSONDecoder/Encoder 전략으로 자동 처리. baseURL은 UserDefaults `"API_BASE_URL"`로 덮어쓸 수 있다(기본값: 배포 Workers URL). 예외: 채팅은 `ChatService`(static enum)가 담당하며 snake_case DTO를 그대로 쓴다 — 같은 이름의 타입을 `APIClient`에 중복 정의하지 말 것.

userId는 항상 `AuthSession.userId`를 guard로 꺼내 쓴다 — `?? 1` 같은 폴백 금지(2026-07-12 전수 제거: 미로그인 시 user 1 데이터로 섞이는 사고 방지). 서버도 user_id 누락 시 1로 귀속하지 않고 400을 반환한다. 로그인 시 `AuthSession`이 서버 프로필(연락처·주소)을 **무조건** 로컬 `UserProfile`에 덮어쓴다(비어 있으면 초기화) — 계정 전환 시 이전 계정 값 잔존 방지이므로 조건부 반영으로 되돌리지 말 것.

### 지도 데이터 흐름

1. `AnimalBoardingService`가 공공데이터 동물위탁관리업 API 호출 → 좌표가 TM(EPSG:5181)이므로 `TMConverter`로 WGS84 변환 (외부 라이브러리 없이 직접 구현, 대한민국 범위 밖 좌표는 필터링)
2. `KakaoLocalService`로 마스킹된 주소 보강
3. `KakaoMapView`는 뷰포트 기반: 지도 이동이 멈추면(`cameraDidStopped`) 현재 화면 위경도 범위 안의 가게만 핀 표시, 중심 가까운 순 개수 상한

### 핵심 도메인 설계 — 공공 가게의 ID 승격

지도의 가게는 공공 API 출신이라 DB `store_id`가 없다. 이를 다루는 규칙:

- `store_key` = `"이름|주소"` 문자열. 예약·리뷰·찜 시 이 키로 `stores` 테이블을 조회해 **있으면 재사용, 없으면 insert** (upsert) → 같은 가게는 항상 같은 `store_id`.
- 채팅방은 `chat_rooms(user_id, store_id UNIQUE)`, 찜은 `favorites(user_id, store_id UNIQUE)` — 둘 다 **(사용자+가게) 조합당 1개**. 예약 API가 방을 자동 생성/조회하고 `{reservation_id, room_id}`를 함께 반환한다.
- 사장님-가게 소유는 `stores.owner_id`. 마이페이지 '내 가게'(`MyStoreSheet`)에서 상호명 검색으로 등록(`POST /api/stores/claim`, `store_key` upsert 재사용, 남의 가게면 409)·해제(`DELETE /api/owners/:id/stores/:storeId`)하고, 등록된 가게는 가게 상세에 '내 가게' 뱃지로 표시된다. 받은 문의는 `GET /api/owners/:id/chatrooms`로 조회해 채팅 목록(`ChatListView`) 상단 '받은 문의' 섹션에 표시하고, 받은 예약 요청(`OwnerModeView`)도 `GET /api/owners/:id/reservations/pending`으로 내 가게 것만 조회한다(확정/취소 가능).
- 예약 캘린더 일정은 **고객 기기**에만 쓴다(사장님 기기 금지) — 추가는 예약 요청 시점(`BookingView` 성공 직후), 삭제는 본인 취소 시 즉시 + 사장님 취소는 고객이 예약 내역(`ReservationListView`)을 열 때 `CalendarService.syncReservationEvents`가 CANCELED를 관찰해 삭제(서버 푸시 없음).
- 예약 취소는 고객·사장님 공용 `PATCH /api/reservations/:id/cancel` 하나 — 사장님 취소만 바디 `by_owner`로 구분해 고객 채팅방에 취소 안내 자동 메시지(sender 0)를 남긴다(iOS는 `cancelReservation(byOwner:)`, `OwnerModeView`에서만 true). 고객 본인 취소에 메시지를 보내지 말 것.
- 채팅방 진입 시 `router.chatRoomAsOwner`를 반드시 설정할 것(받은 문의에서만 true) — 자동메시지(sender 0) 말풍선 방향과 '응답중' 표시가 이 플래그를 따른다. 방은 여전히 (손님+가게)당 1개 — 사장님용 방을 따로 만들지 않고 같은 방에 `sender_id`로 참여하며, `ChatRoomView` 말풍선도 `sender_id == 내 userId` 기준이라 양쪽 시점 모두 그대로 동작한다.
- 안 읽은 채팅(홈 종 아이콘 빨간 점)은 `chat_room_reads(room_id, user_id)`의 `last_read_message_id`로 추적한다 — 읽음 처리는 `ChatRoomView`가 열람(최초 로드·폴링 신규분)마다 `ChatService.markRead` 호출, 카운트는 `GET /api/users/:id/unread-count` — 손님 시점(내가 손님인 방)은 모든 계정 공통이고 사장님 계정은 내 가게로 온 손님 메시지를 **합산**한다(사장님도 다른 가게엔 손님이므로 분기가 아니라 합산; 사장님 몫은 sender 0 제외 + 내가 손님인 방 제외로 중복 집계 방지). 채팅 로드 경로를 바꿀 때 markRead 호출을 빼먹지 말 것.
- 이 패턴을 깨는 변경(예약마다 방 생성, 이름만으로 가게 식별 등)은 하지 않는다.
- iOS에서 서버가 보강한 `store_key`로 화면을 다시 그릴 때(`FavoritesView` 등)는 `MapPin.storeKeyOverride`에 원본 키를 담아 재계산으로 키가 어긋나지 않게 한다.

### 백엔드 — 단일 파일 Hono 앱

`src/index.ts` 하나에 모든 라우트가 있다 (`/api/stores`, `/api/reservations`, `/api/chatrooms/*`, `/api/reviews`, `/api/pet-reviews`, `/api/favorites`, `/api/auth/kakao`, `/api/users/*`, `/api/pets/*` 등).

- 요청 바디 타입은 iOS가 snake_case/camelCase를 혼용하므로 **두 형태 모두 optional로 받는 타입**을 정의한다 (`ReservationBody` 참고). `any` 사용 금지.
- D1 바인딩 이름은 `DB` (`wrangler.toml`).
- Cron Trigger(`wrangler.toml` crons, 매일 09:00 UTC = KST 18시)가 `scheduled` 핸들러로 이용일(start_date)이 어제였던 CONFIRMED 예약의 채팅방에 리뷰 요청 자동 메시지를 보낸다 — 중복 방지는 `reservations.review_requested`, 데모용 수동 트리거는 `POST /api/internal/review-requests`. export가 `{ fetch: app.fetch, scheduled }` 형태이므로 `export default app`으로 되돌리지 말 것. `start_date`는 연도 포함 `"2026-07-12 (일) 14:00"` 형식(iOS `BookingViewModel.dateLabel`·`CalendarService.parseSchedule`과 맞물림) — 연도 없는 구형 `"토 7/12 14:00"` 데이터는 월/일 대조로 계속 처리된다.

## 현재 미완성 영역 (작업 시 주의)

- 네이버 블로그 후기: 코드 완성, API 키 미발급 (`NaverBlogService`).
