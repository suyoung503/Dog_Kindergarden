# 맡겨멍 — 개발 계획

> 완료된 Task는 PROGRESS.md 참고. 여기는 남은 작업과 전체 로드맵.

---

## 단기 계획 (지금 당장)

### Task 5: 네이버 블로그 API 연동

**소요 시간:** 10분
**코드는 완성됨 — API 키만 발급하면 됨. 개인 계정으로 발급해야 하므로 사용자가 직접 진행**

1. https://developers.naver.com 접속 → 로그인
2. Applications → 애플리케이션 등록
3. 사용 API: **검색 → 블로그** 체크
4. iOS 번들 ID 입력 후 등록
5. 발급된 Client ID, Secret을 `Create.xcconfig`에 추가:
   ```
   NAVER_CLIENT_ID = 발급받은값
   NAVER_CLIENT_SECRET = 발급받은값
   ```
6. 앱 실행 → 가게 상세 → 블로그 후기 확인

---

### ✅ Task 7: README 작성 (완료 — 2026-07-08)

- 루트 `README.md` — 프로젝트 소개, 주요 기능, 모노레포 구조, 기술 스택
- `Dog_kindergarden/README.md` — 빌드 가이드 (pod install, `Create.xcconfig` 작성 예시 + 키 발급처 표, 개발자 진입 안내)
- `backend-cloudflare/README.md` — 구현된 API 목록을 현재 라우트로 최신화

---

## 중기 계획 (다음 기능)

### 로그인/회원가입

**상태: 카카오 로그인 연동 완료** (`AuthSession` → `POST /api/auth/kakao`). 아래는 선택 배경 기록.

**선택지:**
- A. Cloudflare Workers에 JWT 인증 추가 (현재 백엔드 확장)
- B. Firebase Auth 사용 (빠른 구현)
- C. Kakao 로그인 (사용자 UX 좋음, SDK 이미 포함)

→ **Kakao 로그인 권장** (KakaoMapsSDK 이미 설치되어 있어 추가 의존성 없음)

---

### ✅ 예약 백엔드 실연동 (완료 — 2026-07)

- `BookingView` '예약 신청하기' → `POST /api/reservations` 실연동, 실제 등록 강아지 선택
- 예약 시 `(user_id, store_id)` 조합당 채팅방 1개 자동 생성(`chat_rooms`), 공공 가게는 `store_key`로 `stores` upsert → 안정적 `store_id`/`room_id` 확보
- `BookingDoneView`에 실제 예약 정보 표시, 보호자 정보 영구 저장, 서비스별 총액 계산

---

### ✅ 채팅 API 클라이언트 연동 (완료 — 2026-07-07)

- `ChatService` 네트워킹 레이어 (방 목록/조회/생성, 메시지 로드/전송)
- `ChatRoomView` 실제 메시지 로드/전송 — 낙관적 추가 + 실패 시 롤백, 방 없으면 첫 전송에서 생성(작성 모드)
- 예약 완료화면·가게 상세 문의하기 → 채팅방(`room_id`) 직행, `ChatListView` 실제 방 목록

---

### ✅ MyPageView UserProfile 편집 연결 (완료 — 2026-07-07)

- `ProfileEditSheet` — 이름·연락처·주소 편집, 로그인 시 `PUT /api/users/:id` 서버 저장 + 세션 닉네임 동기화
- 프로필 카드 실데이터 통계 (예약/강아지/채팅 수)

---

### ✅ 찜한 가게 (완료 — 2026-07-08)

- D1 `favorites(user_id, store_id UNIQUE)` 신설, 기존 `store_key` upsert 패턴 재사용 — 채팅방과 동일한 설계
- 가게 상세 하트 토글로 추가/해제, 마이페이지 '찜한 케어'→'찜한 가게' 이름 변경
- `FavoritesView` 신규 — 프로필 아이콘·가게명·주소·호텔/유치원 태그·전화번호 목록, 탭 시 상세 이동

---

### 강아지 사진 업로드 (보류)

`AddDogSheet`의 카메라 버튼(장식만 있고 미연결)을 실제 업로드에 연결하려던 작업. 백엔드 `pets.image_url` 컬럼은 이미 있지만 채워주는 라우트가 없고, 파일 업로드 인프라도 전혀 없는 상태. 이미지 저장소로 Cloudflare R2를 쓰기로 했으나, R2는 무료 티어라도 활성화 시 결제 수단(카드) 등록이 필요해 사용자 판단이 필요해 보류. 재개 시 선택지: (A) R2 활성화 후 버킷 생성부터 이어서 진행, (B) 새 인프라 없이 `image_url`에 base64 data URI를 바로 저장(대신 DB 행이 무거워짐).

---

### ✅ 예약 확정(사장님 모드) + 캘린더 저장 (완료 — 2026-07-09)

- 예약 상태가 REQUEST에서 한 번도 CONFIRMED로 전환될 방법이 없었던 것을 발견 — 시작 화면의 "사장님" 역할 선택은 로그인 후 아무 동작 없이 홈으로 가는 장식용 UI였음
- 백엔드: `GET /api/reservations/pending`(REQUEST 상태 전체, 가게명·타입·강아지명 조인), `PATCH /api/reservations/:id/confirm`(cancel과 동일 패턴) 신설
- iOS: `OwnerModeView` 신규 — 사장님 역할로 로그인 시 진입, 받은 예약 요청 목록 + 확정하기 버튼. 업체-가게 소유 관계가 DB에 없어 전체 가게의 요청을 함께 보여주는 데모 범위로 구현
- 확정 성공 시 EventKit(`CalendarService`)으로 기기 캘린더에 일정 추가. 날짜 선택 UI(`BookingView.vm.dates`)가 연도 없는 문자열이라 오늘 이후 가장 가까운 도래 시점으로 추정해 파싱. 예약 취소 시 저장된 캘린더 일정도 함께 삭제(`removeReservationEvent`)
- Info.plist에 `NSCalendarsUsageDescription`/`NSCalendarsWriteOnlyAccessUsageDescription` 추가

---

## 중기 계획 (다음 기능 작업 — 2026-07-12 정리)

상세는 `PROGRESS.md` 남은 작업 > 중기 참고.

| 기능 | 비고 |
|---|---|
| `reviews` 테이블 삭제 | 마이그레이션 `0010_drop_reviews.sql` (0행 확인 완료) |
| ~~리뷰 요청 시스템 메시지~~ | ✅ 완료 (2026-07-12) — Cron Triggers 매일 KST 18시, 이용일 다음날 채팅방에 자동 메시지 |
| 사장님 취소 알림 | 취소 시 고객 채팅방에 시스템 메시지 + 예약 신청 화면에 취소 가능 경고 문구 |
| 안 읽은 채팅 빨간 점 | 홈 종 아이콘 — 읽음 상태 스키마 확장 필요 |
| 리뷰 태그 지도 필터링 | 현재 미동작 — pet_reviews 태그와 지도 핀 연결 |
| 사용자별 데이터 분리 검증 | `userId: 1` 하드코딩 잔재 전수 교체 포함 |
| 채팅/시스템 메시지 분리 | 말풍선 vs 중앙 안내문 — 설계 검토 |

---

## 장기 계획 (v2)

| 기능 | 난이도 | 비고 |
|---|---|---|
| 알림장(diary) | 중간 | 사장님이 맡긴 날 일지·사진 작성, 보호자가 예약 단위로 열람. DB `diaries` 테이블은 준비됨(화면·API 미구현). ※ 예약 승인은 사장님 모드로 구현 완료 — 별도 업체 앱 계획은 폐기 |
| 푸시 알림 | 중간 | FCM 연동 |
| 실시간 채팅 (WebSocket) | 높음 | 현재는 polling |
| CCTV 실시간 | 매우 높음 | HLS 스트리밍 필요 |
| 결제 시스템 | 높음 | PG사 연동 |
| AI 리뷰 요약 | 중간 | Claude API |

---

## 파일 구조 참고

```
docs/
├── PORTFOLIO.md      ← 포트폴리오용 기술 문서
├── PROGRESS.md       ← 현재 진행상황
├── PLAN.md           ← 이 파일 (개발 계획)
├── deployment-readiness-report.md   ← 배포 체크리스트 원본
└── security-improvements.md         ← 보안 개선 상세 기록
```
