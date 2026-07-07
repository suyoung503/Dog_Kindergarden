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
- `GET /api/stores`
- `POST /api/reservations`
- `GET /api/users/:id/pets`
- `GET /api/diaries/:reservationId`
- `GET /api/chatrooms/:id/messages`
- `POST /api/chatrooms/:id/messages`
