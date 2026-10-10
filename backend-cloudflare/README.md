# 맡겨멍 Cloudflare 백엔드

이 백엔드는 Cloudflare Workers + D1 기반입니다.

## 1) 사전 준비
- Cloudflare 계정
- Node.js 18+
- Wrangler 로그인

```bash
cd backend-cloudflare
npm install
npx wrangler login
```

## 2) D1 생성
```bash
npx wrangler d1 create dog_kindergarden_db
```

생성 후 나온 `database_id`를 `wrangler.toml`의 `database_id`에 넣어주세요.

## 3) 마이그레이션
```bash
npx wrangler d1 migrations apply dog_kindergarden_db
```

## 4) 로컬 실행
`.dev.vars.example`을 `.dev.vars`로 복사하고 로컬 전용 키를 설정한 뒤 실행합니다. `ALLOW_DEV_AUTH`는 운영 환경에 절대 설정하지 않습니다.

```bash
cp .dev.vars.example .dev.vars
npm run dev
```

인증·권한 회귀 테스트:

```bash
INTERNAL_API_KEY=<.dev.vars와 같은 값> npm run test:auth
```

## 5) 배포
운영에서는 먼저 내부 관리 API 키를 Worker Secret으로 등록합니다.

```bash
npx wrangler secret put INTERNAL_API_KEY
npx wrangler d1 migrations apply dog_kindergarden_db --remote
npm run deploy
```

`ALLOW_DEV_AUTH`는 운영 Worker에 등록하지 않습니다. 인증 변경은 구버전 앱과 호환되지 않으므로 iOS 업데이트와 Worker 배포를 함께 진행해야 합니다.

### 운영자 계정 지정

가게 등록 요청을 승인하는 운영자 권한은 앱에서 선택할 수 없으며, 운영 D1에서 실제 개발자 계정 한 개에만 수동으로 부여합니다. 마이그레이션 적용 후 카카오 계정으로 한 번 로그인한 다음 사용자 번호를 확인해 아래처럼 설정합니다.

```sql
UPDATE users SET is_admin = 1 WHERE user_id = <개발자 사용자 번호>;
```

권한을 부여한 뒤 앱에서 로그아웃하고 다시 로그인하면 마이페이지에 `가게 등록 요청` 메뉴가 나타납니다. 신청자의 이름·연락처·이메일·주소와 신청 가게를 실제 자료와 대조한 뒤 승인해야 하며, 앱이 현실의 사업자 소유 여부를 자동 판정하지는 않습니다.

배포 URL 예시:
- `https://matgyeomung-api.<your-subdomain>.workers.dev`

## 6) iOS 앱 API 주소 변경
앱은 기본적으로 운영 Worker를 사용합니다. 로컬 Worker 또는 다른 환경을 시험할 때만 실행 중인 앱의 `UserDefaults`에 `API_BASE_URL`을 설정합니다. 값은 Worker 루트와 `/api`가 붙은 주소를 모두 허용하며 내부에서 `/api` 형태로 정규화합니다.

예:
```swift
UserDefaults.standard.set(
  "http://127.0.0.1:8787",
  forKey: "API_BASE_URL"
)
```

## 구현된 API

전체 라우트는 `src/index.ts` 하나에 정의되어 있습니다.

### 인증·권한

- `POST /api/auth/kakao`는 클라이언트가 보낸 카카오 액세스 토큰을 카카오 사용자 API에서 검증한 뒤 30일짜리 맡겨멍 세션 토큰을 발급합니다.
- iOS는 세션 토큰을 Keychain에 보관하고 보호 API 호출에 `Authorization: Bearer <token>`을 붙입니다.
- 사용자 번호가 URL이나 본문에 있더라도 서버 세션의 사용자와 같아야 하며, 강아지·예약·찜·채팅·알림장은 DB 소유 관계를 추가 확인합니다.
- 사장님 API는 사장님 역할과 `stores.owner_id`를 모두 확인합니다.
- `POST /api/auth/logout`은 현재 서버 세션을 폐기합니다.
- `/api/admin/*`, `/api/internal/*`는 `X-Internal-Key`가 Worker Secret `INTERNAL_API_KEY`와 같을 때만 허용합니다.
- 공개 조회는 가게·공지·검증된 리뷰 목록으로 제한됩니다.

가게
- `GET /api/stores` — 일반 업체는 기본정보와 capability만 반환하며 미검증 가격·영업시간·이미지는 숨김
- `GET /api/stores/detail?storeKey=...` — `is_partner`, `can_book`, `can_chat`, `can_diary`, `can_review` 포함
- `POST /api/stores/claim` — 사장님 가게 등록 **요청** 생성. 승인 전에는 `owner_id`를 연결하지 않음
- `GET /api/users/:id/store-owner-applications` — 본인의 등록 요청 이력
- `GET /api/owner-applications` — 운영자 전용 승인 대기 목록과 신청자 정보
- `GET /api/owner-applications/pending-count` — 운영자 전용 승인 대기 수
- `PATCH /api/owner-applications/:id/approve` — 운영자 승인, `stores.owner_id` 연결 및 파트너 `ACTIVE` 전환
- `PATCH /api/owner-applications/:id/reject` — 운영자 거절
- `GET /api/owners/:id/stores` — 사장님이 등록한 가게 목록
- `DELETE /api/owners/:id/stores/:storeId` — 등록 해제

예약
- `POST /api/reservations`
- `GET /api/users/:id/reservations`
- `PATCH /api/reservations/:id/cancel` — 바디 `{"by_owner": true}`면 사장님 취소로 간주해 고객 채팅방에 취소 안내 자동 메시지 발송
- `PATCH /api/reservations/:id/confirm`
- `GET /api/owners/:id/reservations/pending` — 사장님이 받은 예약 요청 (내 가게만)

채팅
- `GET /api/chatrooms/:id/messages`
- `POST /api/chatrooms/:id/messages`
- `GET /api/chatrooms/lookup`
- `POST /api/chatrooms`
- `GET /api/users/:id/chatrooms`
- `GET /api/owners/:id/chatrooms` — 사장님이 받은 문의방 목록 (내 가게만)
- `POST /api/chatrooms/:id/read` — 방 열람 읽음 처리 (마지막 메시지까지)
- `GET /api/users/:id/unread-count` — 안 읽은 메시지 수 (홈 종 아이콘 빨간 점용, 손님 시점 공통 + 사장님 계정은 내 가게로 온 손님 메시지 합산)

스케줄러
- Cron `0 9 * * *`(매일 KST 18시) — 이용일 다음날 확정 예약의 채팅방에 리뷰 요청 자동 메시지
- 네이버 플레이스 상세정보 갱신 Cron은 출처·권리 검토 전까지 제거되어 있으며 `NAVER_PLACE_REFRESH_ENABLED=false`로 서버에서도 차단
- `EXPOSE_UNVERIFIED_STORE_DETAILS=false`는 기존 크롤링 가격·영업시간·이미지·편의정보를 공개 API에서 숨긴다. 출처·권리를 확인하지 않은 채 운영에서 `true`로 바꾸지 않는다.
- `POST /api/internal/review-requests` — 위 배치의 데모·테스트용 수동 트리거

리뷰
- `POST /api/pet-reviews`
- `GET /api/pet-reviews`
- `GET /api/pet-reviews/tags`

사용자·강아지·찜·기타
- `POST /api/auth/kakao` — 바디 `access_token`; 카카오 서버 검증 후 세션 발급. 역할은 최초 가입 시 귀속, 반대 역할 로그인은 409
- `POST /api/auth/logout` — 현재 세션 폐기
- `DELETE /api/users/:id/account` — 본인 계정 탈퇴. 진행 예약이 없을 때 개인정보 삭제·운영 기록 익명화·전체 세션 폐기
- `PUT /api/users/:id`
- `GET /api/users/:id/pets`
- `POST /api/users/:id/pets`
- `DELETE /api/pets/:petId`
- `POST /api/favorites`
- `DELETE /api/users/:userId/favorites/:storeId`
- `GET /api/users/:id/favorites`
