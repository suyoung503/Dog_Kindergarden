# 맡겨멍 — 현재 진행상황 및 다음 단계

**마지막 업데이트:** 2026-07-08

---

## 완료된 작업

### 배포 준비

- [x] **Task 1** — `.gitignore` 생성 + `_png_원본/` 삭제 + Pods git 추적 제거
- [x] **Task 2** — API 키 xcconfig 분리 (`Secret.xcconfig`, Info.plist 변수 참조)
- [x] **Task 3** — 백엔드 `.gitignore` + TypeScript `any` 타입 제거
- [x] **Task 4** — 하드코딩 사용자 정보 → `UserProfile` 모델로 교체
- [x] **Task 6** — 미커밋 변경사항 정리 및 GitHub push

### 기능 구현 (커밋 완료)

- [x] 공공데이터 동물위탁관리업 API 연동 (TM→WGS84 좌표 변환 포함)
- [x] 카카오 지도 핀 표시 + 도별 필터링
- [x] 카카오 로컬 API로 주소 보강
- [x] 보호자 펫 리뷰 시스템 (Cloudflare Workers 백엔드 연동)
- [x] 네이버 블로그 후기 연동 코드 완성 (API 키 미발급 상태)
- [x] 예약 화면 UI
- [x] 채팅 화면 UI + 백엔드 연동
- [x] 강아지 프로필 화면
- [x] 마이페이지 화면
- [x] `UserProfile` 모델 (이름·연락처·주소 UserDefaults 저장)

### 기능 구현 (최근 세션 — 2026-07)

- [x] 카카오 로그인 연동 (`AuthSession` → `POST /api/auth/kakao`, 시뮬레이터는 개발자 진입으로 우회)
- [x] 홈 지도 viewport 기반 표시 — '전국보기' 모드 제거, 현재 화면에 보이는 영역의 가게만 핀 표시(도 경계 무관), 초기 수도권 뷰 + 화면당 핀 개수 상한
- [x] '최근 본 케어' 목록을 화면 이동 후에도 유지 (`AppRouter.recentPins`)
- [x] 강아지 프로필 CRUD — 등록/목록/삭제/상세 (`pets` 테이블 실연동, 사회성·알레르기·특이사항은 `note`에 병합)
- [x] 강아지 카드/상세 UI 정리 (이름 강조 + 나이/성별 분리, 상세는 항목별 칸)
- [x] **예약 API 실연동** — `BookingView` → `POST /api/reservations`, 실제 등록 강아지 선택
- [x] **예약 시 채팅방 자동 생성** — `(user_id, store_id)` 조합당 방 1개(`chat_rooms`), 공공 가게는 `store_key`로 `stores`에 upsert해 안정적 `store_id` 확보
- [x] 예약 완료화면에 실제 예약 정보(가게/강아지/일정/금액) 반영
- [x] 보호자 정보 자동 불러오기 + 영구 저장, 서비스 선택 시 총 결제금액 실시간 계산
- [x] **채팅 클라이언트 연동** — `ChatService` 신설, `ChatRoomView` 실제 메시지 로드/전송(낙관적 추가+실패 롤백, 방 없으면 첫 전송 시 생성), `ChatListView` 실제 방 목록, 예약 완료화면·가게 상세 문의하기 → 채팅방(`room_id`) 직행
- [x] **MyPage 프로필 편집** — `ProfileEditSheet`(이름·연락처·주소), 로그인 시 `PUT /api/users/:id` 서버 저장 + 세션 닉네임 동기화, 비로그인 시 로컬만. 프로필 카드 실데이터 통계(예약/강아지/채팅 수, `GET /api/users/:id/reservations` 라우트 추가)
- [x] 카카오 로그인 시 서버 프로필(연락처·주소)을 로컬 `UserProfile`에 동기화
- [x] 빌드 복구 — `APIClient`와 `ChatService`의 `ChatRoomSummary` 중복 선언 제거 (`ChatService` 쪽으로 일원화)
- [x] 프로필 저장 실패 수정 — 원인: 개발자 진입이 DB에 없는 `userId=1`을 하드코딩 → `PUT /api/users/:id`가 null 반환·디코딩 실패. 개발자 진입을 고정 `kakao_id`(`dev-simulator`)로 실제 유저 등록하도록 변경, 백엔드는 없는 유저에 404 반환 (배포 완료)
- [x] **찜한 가게** (2026-07-08) — 가게 상세 하트 토글로 서버 저장. D1 `favorites(user_id, store_id UNIQUE)` 테이블 신설(마이그레이션 0006, `stores.store_type` 컬럼 추가), 기존 `store_key` upsert 패턴 재사용. API 3개: `POST /api/favorites`, `DELETE /api/users/:id/favorites/:storeId`, `GET /api/users/:id/favorites`. 마이페이지 '찜한 케어'→'찜한 가게' 이름 변경 + 실제 찜 개수 뱃지 + `FavoritesView` 목록 화면(타입별 아이콘·가게명·주소·호텔/유치원 태그·전화번호, 행 탭 시 상세 이동, 하트로 즉시 해제). `MapPin.storeKeyOverride`로 보강 주소로 복원해도 원본 키 유지 (배포·curl 검증 완료)

---

## 남은 작업

### 단기 (배포 전 필수)

- [ ] **Task 5** — 네이버 블로그 API 키 발급
  - https://developers.naver.com 에서 앱 등록
  - `Secret.xcconfig`에 `NAVER_CLIENT_ID`, `NAVER_CLIENT_SECRET` 추가
  - 완료 시 가게 상세 화면에서 블로그 후기 자동 표시

- [ ] **Task 7** — README 정리
  - `Dog_kindergarden/README.md` 빌드 가이드로 업데이트
  - 루트 `README.md` 프로젝트 소개로 작성

### 중기 (기능 확장)

- [x] ~~로그인/회원가입~~ — 카카오 로그인 연동 완료
- [x] ~~예약 API 실연동~~ — 완료 (2026-07 세션)
- [x] ~~채팅 API 클라이언트 연동~~ — 완료 (2026-07-07, `ChatService` 기반 실연동)
- [x] ~~MyPageView에서 `UserProfile` 편집 UI 연결~~ — 완료 (2026-07-07, `ProfileEditSheet`)

### 장기 (v2)

- [ ] 업체 측 앱 (알림장 작성, 예약 승인)
- [ ] 푸시 알림 (FCM)
- [ ] CCTV 실시간 보기
- [ ] 결제 시스템

---

## 현재 배포 상태

| 항목 | 상태 |
|---|---|
| API 키 소스 노출 | ✅ 해결 (xcconfig 분리) |
| Pods git 추적 | ✅ 해결 |
| .gitignore | ✅ 완성 |
| 하드코딩 사용자 정보 | ✅ 해결 |
| 네이버 블로그 API | ⏳ 키 발급 필요 |
| 로그인/회원가입 | ✅ 카카오 로그인 |
| 예약 백엔드 연동 | ✅ 연동 완료 |
| 채팅 클라이언트 연동 | ✅ 연동 완료 |
| MyPage 프로필 편집 | ✅ 구현 완료 |
| README | ⏳ 작성 필요 (다음 작업) |

---

## Git 현황

- **iOS repo:** `Dog_kindergarden/` — `main` 브랜치, origin 최신 상태
- **백엔드:** `backend-cloudflare/` — Cloudflare Workers 배포 완료
- **배포 URL:** `https://matgyeomung-api.dog-kindergarden.workers.dev`
