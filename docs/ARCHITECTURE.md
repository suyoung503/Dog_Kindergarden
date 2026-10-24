# 맡겨멍 프로젝트 아키텍처 및 운영 가이드

개발과 유지보수 시 지켜야 할 프로젝트 구조, 명령어, 도메인 규칙을 정리한다.

## 프로젝트 개요

**맡겨멍** — 반려견을 맡길 수 있는 애견 유치원·호텔을 지도 기반으로 탐색하고 예약하는 iOS 플랫폼.
공공데이터를 출발점으로 검수한 서울 지역 업체를 D1에서 제공하고, 승인된 파트너에 리뷰·채팅·예약 기능을 제공한다.

**목표:** 포트폴리오 완성 → 이후 App Store 실제 출시까지 이어가는 로드맵.

모노레포 구성:

- `Dog_kindergarden/` — iOS 앱 (Swift 5.9, SwiftUI + Observation, iOS 17+, CocoaPods)
- `backend-cloudflare/` — 백엔드 (TypeScript, Hono, Cloudflare Workers + D1)
- `docs/` — 기능 명세(`FEATURES.md`), 배포 현황(`DEPLOYMENT_REMAINING.md`), 포트폴리오 기술 문서(`PORTFOLIO.md`), 출시 테스트 문서

커밋 메시지·문서·코드 주석은 한국어를 사용한다. 현재 배포 상태가 달라진 작업은 `docs/DEPLOYMENT_REMAINING.md`를 함께 갱신한다.

## 명령어

### 백엔드 (backend-cloudflare/)

```bash
npm install
npm run dev          # 로컬 실행 (wrangler dev)
npm run deploy       # Cloudflare 배포
npm run d1:migrate   # D1 마이그레이션 적용 (로컬 DB 기본; 배포 DB는 --remote 추가)
```

- 배포 URL: `https://matgyeomung-api.dog-kindergarden.workers.dev`
- 스키마 변경은 반드시 `migrations/`에 번호 순 SQL 파일 추가로만 한다 (기존 파일 다음 번호를 사용한다).
- `backend-cloudflare/scripts/test-auth-permissions.mjs`가 인증·인가 회귀를 검사하고 GitHub Actions가 의존성 audit, Worker dry-run, 빈 D1 마이그레이션과 회귀 테스트를 실행한다. 전체 출시 전 검사는 저장소 루트의 `scripts/release-audit-smoke.sh`를 사용한다.

### iOS 앱 (Dog_kindergarden/)

```bash
pod install          # 최초 1회 및 Podfile 변경 시
open Dog_kindergarden.xcworkspace   # .xcodeproj가 아닌 .xcworkspace로 열 것
```

빌드·실행·테스트는 Xcode에서 한다 (스킴: `Dog_kindergarden`).

**빌드 전 필수 — Create.xcconfig:** iOS SDK의 공개 앱 식별자는 git에서 제외된 `Dog_kindergarden/Base.lproj/Config/Create.xcconfig`에 있고 (Xcode 빌드 설정의 `baseConfigurationReference`가 이 파일을 가리킴), `Info.plist`가 `$(변수)`로 참조한다. 파일이 없으면 지도·로그인이 동작하지 않는다. 필요한 값:

```
KAKAO_NATIVE_APP_KEY
```

Naver Client ID/Secret, Kakao REST API Key, 공공데이터 Service Key는 iOS 번들에 두지 않는다. Worker의 Secret으로만 관리하며, 앱은 인증된 `/api/store-enrichment/*`를 호출한다.

## 아키텍처

### iOS — 커스텀 스택 내비게이션 + 환경 객체

`NavigationStack`을 쓰지 않는다. `RootView`가 `AppRouter.stack`(화면 enum 배열)의 마지막 요소를 switch로 렌더링하는 구조다.

- 화면 추가 = `AppScreen` enum에 case 추가 + `RootView`의 switch에 분기 추가 + `router.go(.화면)`으로 이동.
- 화면 간 전달 데이터는 파라미터가 아니라 `AppRouter`의 프로퍼티(`selectedPin`, `selectedRoomId`, `lastBooking` 등)에 담는다.
- 상태 모델은 전부 `@Observable` 클래스로 `RootView`에서 `.environment()`로 주입: `AppRouter`(내비게이션), `BoardingStore`(공공데이터 가게), `TagStore`(리뷰 태그), `UserProfile`(보호자 정보, UserDefaults 영속), `AuthSession`(카카오 로그인 + `isOwner` 보호자·사장님 역할, UserDefaults 영속). 뷰에서는 `@Environment(타입.self)`로 읽는다.
- 역할(보호자/사장님)로 로그인 후 진입 화면을 분기하지 않는다. 목적지는 모두 `.home`이고, 사장님 여부는 `AuthSession.isOwner`에 귀속해 홈 사이드바(FAB)에 '받은 예약 요청'만 조건부 노출한다. (진입 분기 방식은 뒤로가기·재실행 시 오라우팅을 유발해 폐기했다.)
- 역할은 **최초 가입 시 계정(서버 `users.is_owner`)에 영구 귀속**된다. 같은 카카오 계정으로 반대 역할 가입은 서버가 409로 거절하고 iOS는 안내 문구를 띄운다(역할별 데이터 분리 목적 — 견주/사장님이 채팅·찜·예약을 공유하지 않게). 개발자 진입도 역할별 별개 계정: `dev-simulator`(견주) / `dev-simulator-owner`(사장님). 로그아웃 시 `AppRouter.reset(to:)`이 스택과 함께 `recentPins`·`selectedPin`·`selectedRoomId`·`lastBooking`을 비워 계정 간 잔존 데이터를 막는다 — reset에 세션 상태 초기화를 빼먹지 말 것. '최근 본 가게'는 계정별 UserDefaults(`recent_pins_<userId>`, 최대 6개) 영속이며 `RootView`의 `.task(id: userId)`가 `router.setActiveUser()`로 로그인 계정 것을 복원한다 — `recentPins` 갱신은 직접 배열 조작 대신 `router.addRecentPin()`을 쓸 것.
- 운영자 권한(`users.is_admin`)은 보호자·사장님 역할과 별개다. 유일한 운영자 카카오 서비스 사용자 ID의 SHA-256 해시를 Worker Secret `ADMIN_KAKAO_USER_ID_HASH`에 보관하고, 카카오가 검증한 ID를 로그인 때 같은 방식으로 해시해 일치 계정만 운영자로 동기화한다. 지정 운영자가 로그인하면 다른 활성 운영자는 해제된다. 회원 탈퇴 시 해당 D1 사용자 행은 기존 정책대로 익명화되고 운영자 권한도 해제되지만, 같은 카카오 계정으로 재가입하면 새 `user_id`에 운영자 권한만 복구된다. Secret이 없거나 64자리 16진수 형식이 아니면 기존 D1 권한을 유지하며, 원문 ID와 해시는 Git·앱 번들·로그·API 응답에 넣지 않는다.
- 화면 상단 여백은 `.safeAreaTopPadding()`(`SafeAreaKey.swift`)를 쓴다. `body`에서 `UIApplication.safeAreaTop`을 직접 읽으면(`.padding(.top, UIApplication.safeAreaTop + 12)`) 콜드 런치 때 레이아웃 피드백 순환(AttributeGraph cycle)이 생겨 그 화면이 얼어붙는다 — 특히 초기 화면. 상세는 `docs/PORTFOLIO.md` §7.

### iOS — API 연결

`APIClient.shared`가 기본 REST 레이어. snake_case↔camelCase 변환은 JSONDecoder/Encoder 전략으로 자동 처리. baseURL은 UserDefaults `"API_BASE_URL"`로 덮어쓸 수 있다(기본값: 배포 Workers URL). 예외: 채팅은 `ChatService`(static enum)가 담당하며 snake_case DTO를 그대로 쓴다 — 같은 이름의 타입을 `APIClient`에 중복 정의하지 말 것.

userId는 항상 `AuthSession.userId`를 guard로 꺼내 쓴다 — `?? 1` 같은 폴백 금지(2026-07-12 전수 제거: 미로그인 시 user 1 데이터로 섞이는 사고 방지). 서버도 user_id 누락 시 1로 귀속하지 않고 400을 반환한다. 로그인 시 `AuthSession`이 서버 프로필(연락처·주소)을 **무조건** 로컬 `UserProfile`에 덮어쓴다(비어 있으면 초기화) — 계정 전환 시 이전 계정 값 잔존 방지이므로 조건부 반영으로 되돌리지 말 것.

### 지도 데이터 흐름

1. `AnimalBoardingService`의 `BoardingStore`가 `GET /api/stores`(백엔드 `is_curated=1` 필터)를 호출해 **선별된 서울 유치원/호텔만** 핀 데이터로 가져온다(2026-08-20 이전엔 공공데이터 API를 직접 호출·전국 페이지네이션했으나, 서버가 `numOfRows`를 100건으로 강제 절단하는 미문서화 제한 때문에 대부분의 가게가 애초에 로드되지 않는 문제가 있어 폐기 — `TMConverter`·전국 페이지네이션 코드는 삭제). 큐레이션 목록은 공공데이터 폐업 여부 확인 + 네이버/카카오 보강 주소·좌표를 거쳐 `backend-cloudflare/crawl-results/apply-curated-seoul-*.sql`로 D1에 반영한 것 — 가격정보 유무와 무관하게 유치원/호텔이면 포함된다. 응답의 `store_key`는 `MapPin.storeKeyOverride`에 담아 식별 키가 어긋나지 않게 한다.
2. 가게 상세의 주소·전화·블로그 보강은 iOS가 외부 공급자를 직접 호출하지 않고 인증된 Worker API를 사용
3. `KakaoMapView`는 뷰포트 기반: 지도 이동이 멈추면(`cameraDidStopped`) 현재 화면 위경도 범위 안의 가게만 핀 표시, 중심 가까운 순 개수 상한(현재 큐레이션 대상이 서울로 한정되어 있어 서울 밖에서는 핀이 뜨지 않음 — 전국 확장 시 재검토)
4. 가게 상세(`StoreDetailView`)는 `StoreEnrichmentService`와 `NaverBlogService`를 통해 Worker의 `/api/store-enrichment/place|blogs?storeKey=...`만 호출한다. Worker가 D1의 등록 가게명·주소·좌표로 검색어를 만들므로 임의 검색 프록시가 되지 않으며, `ACTIVE` 파트너와 로그인 세션을 요구한다. Naver 지역 검색은 핀 좌표 최근접 결과 중 **3km 밖을 기각**하고, Kakao는 전화·지도 링크를 보강한다. 결과는 D1에 장소 24시간·블로그 15분 캐시하며 공급자 원문 오류와 Secret은 앱 응답·로그에 전달하지 않는다.

### 핵심 도메인 설계 — 공공 가게의 ID 승격

지도의 가게는 공공 API 출신이라 DB `store_id`가 없다. 이를 다루는 규칙:

- `store_key` = `"이름|주소"` 문자열. 예약·리뷰·찜 시 이 키로 `stores` 테이블을 조회해 **있으면 재사용, 없으면 insert** (upsert) → 같은 가게는 항상 같은 `store_id`.
- `store_key`의 주소 부분은 공공데이터의 **마스킹 원본**(`***`)이다 — 정체성 키라서 **절대 변경 금지**. 표시용 `stores.address` 컬럼만 검증된 실주소로 백필할 수 있다(2026-07-17, 16곳 완료). 백엔드 upsert는 기존 행의 address를 덮어쓰지 않으므로(phone·store_type·좌표만 COALESCE 보강) 백필 값이 유지된다.
- 채팅방은 `chat_rooms(user_id, store_id UNIQUE)`, 찜은 `favorites(user_id, store_id UNIQUE)` — 둘 다 **(사용자+가게) 조합당 1개**. 예약 API가 방을 자동 생성/조회하고 `{reservation_id, room_id}`를 함께 반환한다.
- 사장님-가게 소유는 `stores.owner_id`와 `partner_status`를 함께 사용한다. 마이페이지 '내 가게'에서 신청하면 `PENDING`일 뿐이며 운영자가 신청자 자료를 확인해 승인해야 `owner_id`가 연결되고 `ACTIVE`가 된다. 예약·채팅·알림장·리뷰 capability는 `ACTIVE` 파트너에만 열리며 일반 업체는 전화·외부 지도·찜만 제공한다. 과거 즉시 등록 `owner_id`도 승인 이력이 없으면 마이그레이션에서 대기열로 되돌린다.
- 예약 캘린더 일정은 **고객 기기**에만 쓴다(사장님 기기 금지) — 예약 완료 화면에서 사용자가 `캘린더에 추가`를 눌렀을 때만 권한을 요청해 저장한다. 삭제는 본인 취소 시 즉시, 사장님 취소는 고객이 예약 내역(`ReservationListView`)을 열 때 `CalendarService.syncReservationEvents`가 CANCELED를 관찰해 처리한다.
- 예약 취소는 고객·사장님 공용 `PATCH /api/reservations/:id/cancel` 하나 — 사장님 취소만 바디 `by_owner`로 구분해 고객 채팅방에 취소 안내 자동 메시지(sender 0)를 남긴다(iOS는 `cancelReservation(byOwner:)`, `OwnerModeView`에서만 true). 고객 본인 취소에 메시지를 보내지 말 것.
- 채팅방 진입 시 `router.chatRoomAsOwner`를 반드시 설정할 것(받은 문의에서만 true) — '응답중' 표시가 이 플래그를 따른다. 자동메시지(sender 0)는 시점과 무관하게 화자 없는 **중앙 시스템 안내문**으로 렌더링한다(2026-07-18 말풍선에서 분리 — 좌/우 말풍선으로 되돌리지 말 것). 방은 여전히 (손님+가게)당 1개 — 사장님용 방을 따로 만들지 않고 같은 방에 `sender_id`로 참여하며, `ChatRoomView` 말풍선도 `sender_id == 내 userId` 기준이라 양쪽 시점 모두 그대로 동작한다.
- 안 읽은 채팅(홈 종 아이콘 빨간 점)은 `chat_room_reads(room_id, user_id)`의 `last_read_message_id`로 추적한다 — 읽음 처리는 `ChatRoomView`가 열람(최초 로드·폴링 신규분)마다 `ChatService.markRead` 호출, 카운트는 `GET /api/users/:id/unread-count` — 손님 시점(내가 손님인 방)은 모든 계정 공통이고 사장님 계정은 내 가게로 온 손님 메시지를 **합산**한다(사장님도 다른 가게엔 손님이므로 분기가 아니라 합산; 사장님 몫은 sender 0 제외 + 내가 손님인 방 제외로 중복 집계 방지). 채팅 로드 경로를 바꿀 때 markRead 호출을 빼먹지 말 것.
- 알림장(diary)은 **예약당 타임라인** — `diaries` 테이블을 예약에 1:N으로 묶고 사진 메타데이터는 `diary_photos`, 파일은 비공개 R2 바인딩 `DIARY_PHOTOS`에 저장한다. 알림장당 JPEG 최대 3장·장당 1.5MB이며, 사진 조회는 해당 예약 보호자와 가게 사장님, 등록·삭제는 승인된 가게 사장님만 가능하다. 사진 선택 UUID를 `Idempotency-Key`로 저장해 응답 유실 후 업로드 재시도가 중복 사진을 만들지 않는다. `diary_photo_deletion_queue`가 업로드 중단과 삭제 실패를 복구하며 R2는 호출당 최대 1,000개씩 재시도한다. 알림장·회원 탈퇴·5년 보유기간 정리 때 R2 객체와 D1 행을 함께 삭제한다. 사장님이 **작성할 때만** 보호자 채팅방에 자동 메시지(sender 0)를 남기며 수정·삭제에는 보내지 않는다. iOS는 `DiaryTimelineView` 하나를 `router.diaryContext.canWrite`로 공유하고, `PhotosPicker` 선택 사진을 ImageIO로 최대 1600px JPEG 다운샘플링하며 전체 화면 좌우 넘김을 제공한다.
- 알림 피드(`GET /api/users/:id/notifications`, opaque 커서)는 이벤트당 정확히 한 축으로만 들어간다 — 이미 채팅 메시지를 남기는 이벤트(알림장 도착·사장님 취소 안내·리뷰 요청 등)는 채팅 축으로만 노출하고, 메시지가 없는 이벤트(새 예약 요청·확정·고객 취소)만 예약 축에 넣는다. 이벤트당 알림 1회 보장이 이 분리에 의존하므로 어느 한쪽에 중복 추가하지 말 것.
- 이 패턴을 깨는 변경(예약마다 방 생성, 이름만으로 가게 식별 등)은 하지 않는다.
- iOS에서 서버가 보강한 `store_key`로 화면을 다시 그릴 때(`FavoritesView` 등)는 `MapPin.storeKeyOverride`에 원본 키를 담아 재계산으로 키가 어긋나지 않게 한다.

### 백엔드 — Hono 앱 + 가게 상세 갱신 모듈

모든 HTTP 라우트는 `src/index.ts`에 있고(`/api/stores`, `/api/reservations`, `/api/reservations/:id/diaries`, `/api/chatrooms/*`, `/api/pet-reviews`, `/api/favorites`, `/api/auth/kakao`, `/api/users/*`, `/api/pets/*` 등), 네이버 플레이스 상세정보 순환 갱신은 `src/storeDetailRefresh.ts`로 분리돼 있다.

- 요청 바디 타입은 iOS가 snake_case/camelCase를 혼용하므로 **두 형태 모두 optional로 받는 타입**을 정의한다 (`ReservationBody` 참고). `any` 사용 금지.
- D1 바인딩 이름은 `DB` (`wrangler.toml`).
- 활성 Cron Trigger는 `0 9 * * *` 하나다. 매일 09:00 UTC(KST 18시)에 이용일(start_date)이 어제였던 CONFIRMED 예약의 채팅방으로 리뷰 요청 자동 메시지를 보내며, 중복은 `reservations.review_requested`로 막고 데모용 수동 트리거는 `POST /api/internal/review-requests`다. 네이버 플레이스 상세정보 순환 갱신은 출처·권리 검토 전까지 Cron에서 제거했고 `NAVER_PLACE_REFRESH_ENABLED=false`로 서버에서도 차단한다. `EXPOSE_UNVERIFIED_STORE_DETAILS=false`는 일반·파트너 모두의 기존 미검증 가격·영업시간·이미지·편의정보를 공개 응답에서 숨긴다. export는 `{ fetch: app.fetch, scheduled }` 형태를 유지한다. `start_date`는 연도 포함 형식 — 시간권은 `"2026-07-12 (일) 14:00"`, 종일권·하루 숙박권은 날짜만 `"2026-07-12 (일)"` (iOS `BookingViewModel.dateLabel`·`CalendarService.parseSchedule`과 맞물림, 날짜만이면 캘린더에 종일 일정) — 연도 없는 구형 `"토 7/12 14:00"` 데이터는 월/일 대조로 계속 처리된다. 예약 유형은 시간권·종일권·하루 숙박권 3종이며, 업체별 가격 등록 전에는 앱이 총액을 계산하지 않고 예약 확정 전에 업체와 확인하도록 안내한다.

## 현재 미완성 영역 (작업 시 주의)

- Sign in with Apple: 상세 설계만 있으며 Apple Developer 설정과 서버·iOS 구현, 실계정 검증이 남아 있다.
- 원격 푸시(APNs)는 유료 Apple Developer 멤버십 확보 후 v2 — 현재는 서버 폴링 피드 + 로컬 알림으로 대체.
