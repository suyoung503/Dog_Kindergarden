# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

**맡겨멍** — 반려견을 맡길 수 있는 애견 유치원·호텔을 지도 기반으로 탐색하고 예약하는 iOS 플랫폼.
공공데이터 동물위탁관리업 API로 전국 업체를 표시하고, 리뷰·채팅·예약 기능을 통합 제공한다.

**목표:** 포트폴리오 완성 → 이후 App Store 실제 출시까지 이어가는 로드맵.
**현재 우선 작업:** 채팅 클라이언트 연동, MyPage 프로필 편집, README 작성 (상세는 `docs/PLAN.md`, `docs/PROGRESS.md`).

모노레포 구성:

- `Dog_kindergarden/` — iOS 앱 (Swift 5.9, SwiftUI + Observation, iOS 16+, CocoaPods)
- `backend-cloudflare/` — 백엔드 (TypeScript, Hono, Cloudflare Workers + D1)
- `docs/` — 계획(`PLAN.md`), 진행상황(`PROGRESS.md`), 포트폴리오 기술 문서(`PORTFOLIO.md`)

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

**빌드 전 필수 — Secret.xcconfig:** API 키는 git에서 제외된 `Secret.xcconfig`에 있고 `Info.plist`가 `$(변수)`로 참조한다. 파일이 없으면 지도·로그인이 동작하지 않는다. 필요한 키:

```
KAKAO_NATIVE_APP_KEY, KAKAO_REST_API_KEY, DATA_GO_KR_SERVICE_KEY,
NAVER_CLIENT_ID, NAVER_CLIENT_SECRET   ← 네이버 키는 아직 미발급 상태
```

## 아키텍처

### iOS — 커스텀 스택 내비게이션 + 환경 객체

`NavigationStack`을 쓰지 않는다. `RootView`가 `AppRouter.stack`(화면 enum 배열)의 마지막 요소를 switch로 렌더링하는 구조다.

- 화면 추가 = `AppScreen` enum에 case 추가 + `RootView`의 switch에 분기 추가 + `router.go(.화면)`으로 이동.
- 화면 간 전달 데이터는 파라미터가 아니라 `AppRouter`의 프로퍼티(`selectedPin`, `selectedRoomId`, `lastBooking` 등)에 담는다.
- 상태 모델은 전부 `@Observable` 클래스로 `RootView`에서 `.environment()`로 주입: `AppRouter`(내비게이션), `BoardingStore`(공공데이터 가게), `TagStore`(리뷰 태그), `UserProfile`(보호자 정보, UserDefaults 영속), `AuthSession`(카카오 로그인). 뷰에서는 `@Environment(타입.self)`로 읽는다.

### iOS — API 연결

`APIClient.shared`가 유일한 REST 레이어. snake_case↔camelCase 변환은 JSONDecoder/Encoder 전략으로 자동 처리. baseURL은 UserDefaults `"API_BASE_URL"`로 덮어쓸 수 있다(기본값: 배포 Workers URL).

주의: 일부 호출에 `userId: 1` 하드코딩이 남아 있다. 카카오 로그인(`AuthSession.userId`)은 구현되어 있으므로, 새 API 호출을 추가할 때는 하드코딩 대신 `AuthSession`의 userId를 쓰는 방향으로 간다.

### 지도 데이터 흐름

1. `AnimalBoardingService`가 공공데이터 동물위탁관리업 API 호출 → 좌표가 TM(EPSG:5181)이므로 `TMConverter`로 WGS84 변환 (외부 라이브러리 없이 직접 구현, 대한민국 범위 밖 좌표는 필터링)
2. `KakaoLocalService`로 마스킹된 주소 보강
3. `KakaoMapView`는 뷰포트 기반: 지도 이동이 멈추면(`cameraDidStopped`) 현재 화면 위경도 범위 안의 가게만 핀 표시, 중심 가까운 순 개수 상한

### 핵심 도메인 설계 — 공공 가게의 ID 승격

지도의 가게는 공공 API 출신이라 DB `store_id`가 없다. 이를 다루는 규칙:

- `store_key` = `"이름|주소"` 문자열. 예약·리뷰 시 이 키로 `stores` 테이블을 조회해 **있으면 재사용, 없으면 insert** (upsert) → 같은 가게는 항상 같은 `store_id`.
- 채팅방은 `chat_rooms(user_id, store_id UNIQUE)` — **(사용자+가게) 조합당 1개**. 예약 API가 방을 자동 생성/조회하고 `{reservation_id, room_id}`를 함께 반환한다.
- 이 패턴을 깨는 변경(예약마다 방 생성, 이름만으로 가게 식별 등)은 하지 않는다.

### 백엔드 — 단일 파일 Hono 앱

`src/index.ts` 하나에 모든 라우트가 있다 (`/api/stores`, `/api/reservations`, `/api/chatrooms/*`, `/api/reviews`, `/api/pet-reviews`, `/api/auth/kakao`, `/api/users/*`, `/api/pets/*` 등).

- 요청 바디 타입은 iOS가 snake_case/camelCase를 혼용하므로 **두 형태 모두 optional로 받는 타입**을 정의한다 (`ReservationBody` 참고). `any` 사용 금지.
- D1 바인딩 이름은 `DB` (`wrangler.toml`).

## 현재 미완성 영역 (작업 시 주의)

- `ChatRoomView`는 아직 `sampleMessages` 하드코딩 — 백엔드 API는 완성되어 있고 클라이언트 연동이 다음 작업.
- `MyPageView`는 UI만 있고 `UserProfile` 바인딩이 안 되어 저장이 동작하지 않음.
- 네이버 블로그 후기: 코드 완성, API 키 미발급 (`NaverBlogService`).
