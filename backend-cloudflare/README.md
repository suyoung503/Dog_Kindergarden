# 맡겨멍 Cloudflare 백엔드

이 백엔드는 Cloudflare Workers + D1·비공개 R2·사용자별 실시간 Durable Object 기반입니다. 현재 운영 상태는 [배포 준비 문서](../docs/DEPLOYMENT_REMAINING.md)를 기준으로 확인합니다.

## 1) 사전 준비
- Cloudflare 계정 (운영·원격 작업 시)
- Node.js 22 (현재 Wrangler의 최소 버전과 CI 실행 기준)
- Wrangler 로그인 (운영·원격 작업 시)

```bash
cd backend-cloudflare
npm ci --ignore-scripts
# 원격 자원 생성/배포 전에만: npx wrangler login
```

이하 셸 명령은 별도 안내가 없으면 `backend-cloudflare` 디렉터리에서 실행합니다. 격리 회귀 검사는 Cloudflare 원격 인증 없이 수행하도록 구성되어 있습니다.

## 2) D1 생성

이 절은 **별도 Cloudflare 환경을 처음 구성할 때만** 필요합니다. 기존 운영 D1/R2를 다시 만들거나 새 DB의 ID로 운영 설정을 덮어쓰지 않습니다. 로컬 개발만 할 때는 다음 절의 `--local` 마이그레이션부터 진행할 수 있습니다.
```bash
npx wrangler d1 create dog_kindergarden_db
```

새 환경에서는 생성 후 나온 `database_id`가 자신의 대상 DB인지 확인해 `wrangler.toml`에 설정합니다. 이 저장소의 기존 운영 DB와 혼동하지 않습니다.

알림장 사진은 공개 URL이 없는 R2 버킷에 저장합니다. 최초 1회 생성하며, 버킷 이름은 `wrangler.toml`의 `DIARY_PHOTOS` 바인딩과 같아야 합니다.

```bash
npx wrangler r2 bucket create matgyeomung-diary-photos
npx wrangler r2 bucket create matgyeomung-diary-photos-preview
```

## 3) 로컬 마이그레이션
```bash
npx wrangler d1 migrations apply dog_kindergarden_db --local
```

로컬 Worker는 별도 로컬 D1을 사용합니다. 로컬 개발을 위해 운영 DB에 `--remote`를 실행하지 않습니다. 운영 반영은 아래 배포 절에서 대상·미적용 목록·승인을 확인한 뒤 별도로 수행합니다.

## 4) 로컬 실행
`.dev.vars.example`을 `.dev.vars`로 복사하고 로컬 전용 키를 설정한 뒤 실행합니다. `.dev.vars`는 Git에서 제외되므로 실제 값을 넣을 수 있지만, 강제 추가(`git add -f`)하거나 문서·이슈·채팅에 값을 복사하지 않습니다. `ALLOW_DEV_AUTH`는 운영 환경에 절대 설정하지 않습니다.

```bash
[ -f .dev.vars ] || cp .dev.vars.example .dev.vars
npm run dev
```

이미 켜 둔 로컬 Worker의 인증·권한 회귀는 같은 디렉터리의 별도 터미널에서 실행합니다.

```bash
INTERNAL_API_KEY='로컬 .dev.vars와 같은 키로 교체' npm run test:auth
```

켜 둔 개발 서버 없이 실행할 수 있는 격리 회귀와 출시 게이트도 제공합니다.

```bash
npm test
npm audit --audit-level=moderate

# 현재 디렉터리에서: 임시 D1·전용 로컬 환경으로 권한 회귀와 번들을 검사
../scripts/release-audit-smoke.sh --backend-only
```

게이트는 운영 DB·실제 계정을 사용하지 않으며 iOS 실기기 검증을 대신하지 않습니다. 로컬 개발 API에 앱을 연결하는 방법은 아래6절을 따릅니다.

## 5) 배포
운영 반영은 검증 후 별도 승인 작업입니다. 새 환경에서는 먼저 내부 관리 API 키를 Worker Secret으로 등록합니다. `INTERNAL_API_KEY`는 네이버·카카오 키가 아니라 운영자/수집 도구의 `/api/admin/*`, `/api/internal/*` 호출을 보호하는 별도 무작위 비밀값입니다. 기존 환경의 Secret을 배포할 때마다 바꾸지 않습니다.

```bash
npx wrangler secret put INTERNAL_API_KEY
```

운영 migration은 먼저 목록과 복구 계획을 확인합니다. 승인한 미적용 파일이 있을 때만 적용하며, 이미 적용한 파일을 다시 실행하지 않습니다.

```bash
npx wrangler d1 migrations list dog_kindergarden_db --remote
# 대상·파일·복구 계획 검토와 승인 후에만 실행
npx wrangler d1 migrations apply dog_kindergarden_db --remote
```

DB 변경이 없는 Worker 수정은 migration을 실행할 필요가 없습니다. 기존 vars를 보존하고 원격 충돌을 확인하며 배포한 뒤 운영 읽기 점검을 수행합니다.

```bash
npx wrangler deploy --keep-vars --strict
# 현재 디렉터리에서: 공개 GET·무인증 차단만 점검
node ../scripts/production-readonly-smoke.mjs
```

아래 외부 서비스 키는 파트너 업체의 서버 측 장소·블로그 보강 기능을 사용할 때만 등록합니다. 인증·예약·승인·고객센터의 핵심 동작에는 필요하지 않으며, 값이 없으면 해당 보강 API만 `503`을 반환합니다.

```bash
npx wrangler secret put NAVER_API_HUB_CLIENT_ID
npx wrangler secret put NAVER_API_HUB_CLIENT_SECRET
npx wrangler secret put KAKAO_REST_API_KEY
```

`ALLOW_DEV_AUTH`는 운영 Worker에 등록하지 않습니다. 현재 앱은 Bearer 세션 인증을 사용하며, 과거 무인증 앱과 호환되지 않습니다. API 계약이 바뀌는 작업은 앱·서버 반영 순서를 함께 검토하고, 서버 내부 수정만으로 끝나는 작업까지 앱 재빌드를 요구하지는 않습니다.
공공데이터 수집을 Worker에서 실행할 때만 `DATA_GO_KR_SERVICE_KEY`를 추가하고, 실제 Secret 값은 `wrangler.toml`, `.dev.vars.example`, 문서에 기록하지 않습니다. 기존에 앱이나 Git 이력에 포함됐던 키는 새 키로 전환한 뒤 공급자 콘솔에서 폐기해야 합니다.

### 운영자 계정 지정

가게 등록 요청을 승인하는 운영자 권한은 앱에서 선택할 수 없습니다. 유일한 운영자 카카오 서비스 사용자 ID의 SHA-256 해시를 Worker Secret `ADMIN_KAKAO_USER_ID_HASH`로 등록합니다. 원문 ID와 해시는 Git·앱 번들·문서·로그에 남기지 않습니다.

다음 입력 예시는 macOS의 zsh 기준입니다.

```zsh
# 운영자 카카오 서비스 사용자 ID를 화면에 표시하지 않고 입력해 해시만 등록
read -s "ADMIN_KAKAO_USER_ID?운영자 Kakao ID: "
printf %s "$ADMIN_KAKAO_USER_ID" | shasum -a 256 | awk '{print $1}' | npx wrangler secret put ADMIN_KAKAO_USER_ID_HASH
unset ADMIN_KAKAO_USER_ID
```

서버는 카카오가 검증한 사용자 ID를 로그인 때 해시해 Secret과 일치하는 계정만 `is_admin=1`로 동기화하고, 지정 운영자가 로그인하면 다른 운영자 권한을 해제합니다. 회원 탈퇴 시 사용자 행의 권한은 제거되지만 같은 카카오 계정으로 재가입하면 새 사용자 번호에 운영자 권한만 복구됩니다. Secret이 없거나 64자리 16진수 형식이 아니면 기존 D1 권한을 유지합니다.

등록 후 앱에서 로그아웃하고 다시 로그인하면 마이페이지에 `가게 등록 요청` 메뉴가 나타납니다. 신청자의 이름·연락처·이메일·주소와 신청 가게를 실제 자료와 대조한 뒤 승인해야 하며, 앱이 현실의 사업자 소유 여부를 자동 판정하지는 않습니다.

배포 URL 예시:
- `https://matgyeomung-api.<your-subdomain>.workers.dev`

## 6) iOS 앱 API 주소 변경
앱은 기본적으로 운영 Worker를 사용합니다. 로컬 Worker 또는 다른 환경을 시험할 때만 실행 중인 앱의 `UserDefaults`에 `API_BASE_URL`을 설정합니다. 값은 Worker 루트와 `/api`가 붙은 주소를 모두 허용하며 내부에서 `/api` 형태로 정규화합니다.

예:
```text
# 시뮬레이터 앱을 Xcode에서 일시정지한 뒤 LLDB 콘솔에서 실행
expr -l Swift -- import Foundation
expr -l Swift -- UserDefaults.standard.set("http://127.0.0.1:8787", forKey: "API_BASE_URL")
```

환경을 바꾸기 전 먼저 로그아웃하고 설정 뒤 앱을 완전히 종료·재실행합니다. 시뮬레이터의 localhost는 Mac의 로컬 Worker에 연결하는 용도이며, 실제 iPhone에 같은 주소를 그대로 적용하지 않습니다. 운영 복귀 시에도 로그아웃 후 LLDB에서 `UserDefaults.standard.removeObject(forKey: "API_BASE_URL")`를 실행하고 앱을 재실행합니다. 서로 다른 서버의 계정/기록을 같은 것으로 취급하지 않습니다.

## 구현된 API

전체 라우트는 `src/index.ts` 하나에 정의되어 있습니다.

### 인증·권한

- `POST /api/auth/kakao`는 클라이언트가 보낸 카카오 액세스 토큰을 카카오 사용자 API에서 검증한 뒤 30일짜리 맡겨멍 세션 토큰을 발급합니다.
- iOS는 세션 토큰을 Keychain에 보관하고 보호 API 호출에 `Authorization: Bearer <token>`을 붙입니다.
- 사용자 번호가 URL이나 본문에 있더라도 서버 세션의 사용자와 같아야 하며, 강아지·예약·찜·채팅·알림장은 DB 소유 관계를 추가 확인합니다.
- 사장님 API는 사장님 역할과 `stores.owner_id`를 모두 확인합니다.
- `POST /api/auth/logout`은 현재 서버 세션을 폐기합니다.
- `/api/admin/*`, `/api/internal/*`는 `X-Internal-Key`가 Worker Secret `INTERNAL_API_KEY`와 같을 때만 허용합니다.
- 공개 조회에는 가게·공지·검증된 리뷰와 공유 랜딩 `GET /store`, `GET /privacy` 개인정보처리방침, `GET /support` 고객지원, `GET /terms` 미시행 약관 준비안이 있습니다. 문서 열람·로그인을 약관 수락 기록으로 취급하지 않습니다.
- 15분 Cron과 `POST /api/internal/data-retention`은 현재 구현된 보유기간에 따라 만료 세션과 오래된 예약·관련 콘텐츠·종료 이력을 정리합니다. 최종 보유 근거와 정책 확정은 배포 준비 문서의 별도 후속이며, 기존5년 정리를 법정 의무로 단정하지 않습니다.

실시간·알림
- `GET /api/realtime` — Bearer 인증 WebSocket. 사용자별 Durable Object가 변경 이벤트를 발행
- `GET /api/users/:id/notifications` — 본인 영속 알림 피드. 최초 이력·커서 이후 누락 복구
- WebSocket은 앱 활성 중 화면 갱신용입니다. 백그라운드·앱 미실행 원격 푸시(APNs)는 별도 미구현입니다.

가게
- `GET /api/stores` — 일반 업체는 기본정보와 capability만 반환하며 미검증 가격·영업시간·이미지는 숨김
- `GET /api/stores/detail?storeKey=...` — `is_partner`, `can_book`, `can_chat`, `can_diary`, `can_review` 포함
- `GET /api/store-enrichment/place?storeKey=...` — 인증·파트너 전용 Naver/Kakao 장소 보강, D1 24시간 캐시
- `GET /api/store-enrichment/blogs?storeKey=...` — 인증·파트너 전용 Naver 블로그 검색, D1 15분 캐시
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
- `GET /api/reservations/:id` — 승인된 해당 가게 사장님의 요청/확정 예약 상세
- `PATCH /api/reservations/:id/cancel` — 바디 `{"by_owner": true}`면 사장님 취소로 간주해 고객 채팅방에 취소 안내 자동 메시지 발송
- `PATCH /api/reservations/:id/confirm`
- `GET /api/owners/:id/reservations/pending` — 사장님이 받은 예약 요청 (내 가게만)
- `GET /api/owners/:id/reservations/confirmed` — 사장님의 확정 예약 목록

알림장
- `GET·POST /api/reservations/:id/diaries` — 예약 참여자 조회, 승인된 가게 사장님 작성
- 게시 본문과 기존 보호자 방의 도착 안내는 같은 D1 batch로 저장합니다. 사진 업로드는 별도 단계이며 성공 응답 자체 유실의 멱등성까지 보장하지 않습니다.
- `PATCH·DELETE /api/diaries/:diaryId` — 승인된 가게 사장님 수정·삭제
- `POST /api/diaries/:diaryId/photos` — 사장님 전용 raw JPEG 업로드(장당 1.5MB, 알림장당 3장). 사진 선택 UUID를 `Idempotency-Key`로 보내 응답 유실 후 재시도 중복을 방지
- `GET /api/diary-photos/:photoId` — 해당 예약 보호자·가게 사장님만 비공개 R2 사진 조회
- `DELETE /api/diary-photos/:photoId` — 해당 가게 사장님만 사진 삭제
- `diary_photo_deletion_queue`가 업로드 중단·R2 삭제 실패를 복구하며, 알림장 삭제·보호자 회원 탈퇴·5년 보유기간 정리 시 연결된 R2 객체와 D1 메타데이터를 함께 삭제

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
- Cron `*/15 * * * *` — 현재 보유기간 기준의 D1 정리와 R2 삭제 대기열 재시도
- Cron `0 9 * * *`(매일 KST 18시) — 이용일 다음날 확정 예약의 채팅방에 리뷰 요청 자동 메시지
- 네이버 플레이스 상세정보 갱신 Cron은 출처·권리 검토 전까지 제거되어 있으며 `NAVER_PLACE_REFRESH_ENABLED=false`로 서버에서도 차단
- `EXPOSE_UNVERIFIED_STORE_DETAILS=false`는 기존 크롤링 가격·영업시간·이미지·편의정보를 공개 API에서 숨긴다. 출처·권리를 확인하지 않은 채 운영에서 `true`로 바꾸지 않는다.
- `POST /api/internal/review-requests` — 위 배치의 데모·테스트용 수동 트리거

리뷰
- `POST /api/pet-reviews`
- `GET /api/pet-reviews`
- `GET /api/pet-reviews/tags`

공지사항
- `GET /api/notices` — 본문을 제외한 최신 공지 목록
- `GET /api/notices/:id` — 공지 상세
- v1에는 앱 작성 화면과 공개 쓰기 API를 두지 않는다. 운영자가 권한 있는 D1 환경에서 `notices(title, body)`를 직접 등록한다.

사용자·강아지·찜·기타
- `POST /api/auth/kakao` — 바디 `access_token`; 카카오 서버 검증 후 세션 발급. 역할은 최초 가입 시 귀속, 반대 역할 로그인은 409
- `POST /api/auth/logout` — 현재 세션 폐기
- `DELETE /api/users/:id/account` — 본인 계정 탈퇴. 진행 예약이 없을 때 개인정보 삭제·운영 기록 익명화·전체 세션 폐기
- `PUT /api/users/:id`
- `GET /api/users/:id/pets`
- `POST /api/users/:id/pets`
- `PUT·GET·DELETE /api/pets/:petId/photo` — 반려견 소유자의 JPEG 사진 업로드·비공개 조회·삭제
- `GET /api/reservations/:id/pet-photo` — 요청/확정 예약의 보호자와 승인된 해당 점주의 예약 범위 사진 조회
- `DELETE /api/pets/:petId`
- `POST /api/favorites`
- `DELETE /api/users/:userId/favorites/:storeId`
- `GET /api/users/:id/favorites`
