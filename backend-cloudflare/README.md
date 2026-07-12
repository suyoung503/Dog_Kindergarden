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
```bash
npm run dev
```

## 5) 배포
```bash
npm run deploy
```

배포 URL 예시:
- `https://matgyeomung-api.<your-subdomain>.workers.dev`

## 6) iOS 앱 API 주소 변경
`Dog_kindergarden/Dog_kindergarden/APIClient.swift`의 기본 URL을 배포 URL로 바꿔주세요.

예:
```swift
return URL(string: saved ?? "https://matgyeomung-api.<your-subdomain>.workers.dev/api")!
```

## 구현된 API

전체 라우트는 `src/index.ts` 하나에 정의되어 있습니다.

가게
- `GET /api/stores`
- `POST /api/stores/claim` — 사장님 '내 가게' 등록 (다른 사장님 가게면 409)
- `GET /api/owners/:id/stores` — 사장님이 등록한 가게 목록
- `DELETE /api/owners/:id/stores/:storeId` — 등록 해제

예약
- `POST /api/reservations`
- `GET /api/users/:id/reservations`
- `PATCH /api/reservations/:id/cancel`
- `PATCH /api/reservations/:id/confirm`
- `GET /api/owners/:id/reservations/pending` — 사장님이 받은 예약 요청 (내 가게만)

채팅
- `GET /api/chatrooms/:id/messages`
- `POST /api/chatrooms/:id/messages`
- `GET /api/chatrooms/lookup`
- `POST /api/chatrooms`
- `GET /api/users/:id/chatrooms`
- `GET /api/owners/:id/chatrooms` — 사장님이 받은 문의방 목록 (내 가게만)

스케줄러
- Cron `0 9 * * *`(매일 KST 18시) — 이용일 다음날 확정 예약의 채팅방에 리뷰 요청 자동 메시지
- `POST /api/internal/review-requests` — 위 배치의 데모·테스트용 수동 트리거

리뷰
- `POST /api/pet-reviews`
- `GET /api/pet-reviews`
- `GET /api/pet-reviews/tags`

사용자·강아지·찜·기타
- `POST /api/auth/kakao` — 역할(보호자/사장님)은 최초 가입 시 계정에 귀속, 반대 역할 로그인은 409
- `PUT /api/users/:id`
- `GET /api/users/:id/pets`
- `POST /api/users/:id/pets`
- `DELETE /api/pets/:petId`
- `POST /api/favorites`
- `DELETE /api/users/:userId/favorites/:storeId`
- `GET /api/users/:id/favorites`
