# 맡겨멍 — 개발 계획

> 완료된 Task는 PROGRESS.md 참고. 여기는 남은 작업과 전체 로드맵.

---

## 단기 계획 (지금 당장)

### Task 5: 네이버 블로그 API 연동

**소요 시간:** 10분  
**코드는 완성됨 — API 키만 발급하면 됨**

1. https://developers.naver.com 접속 → 로그인
2. Applications → 애플리케이션 등록
3. 사용 API: **검색 → 블로그** 체크
4. iOS 번들 ID 입력 후 등록
5. 발급된 Client ID, Secret을 `Secret.xcconfig`에 추가:
   ```
   NAVER_CLIENT_ID = 발급받은값
   NAVER_CLIENT_SECRET = 발급받은값
   ```
6. 앱 실행 → 가게 상세 → 블로그 후기 확인

---

### Task 7: README 작성

**소요 시간:** 20분

`Dog_kindergarden/README.md` 업데이트:
- 프로젝트 소개
- 빌드 방법 (pod install, Secret.xcconfig 설정)
- API 키 발급 가이드 링크

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

## 장기 계획 (v2)

| 기능 | 난이도 | 비고 |
|---|---|---|
| 업체 측 앱 | 높음 | 알림장 작성, 예약 승인 |
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
