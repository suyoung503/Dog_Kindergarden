# 맡겨멍 — 현재 진행상황 및 다음 단계

**마지막 업데이트:** 2026-07-12

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
- [x] **찜한 가게** (2026-07-08) — 가게 상세 하트 토글로 서버 저장. D1 `favorites(user_id, store_id UNIQUE)` 테이블 신설(마이그레이션 0006, `stores.store_type` 컬럼 추가), 기존 `store_key` upsert 패턴 재사용. API 3개: `POST /api/favorites`, `DELETE /api/users/:id/favorites/:storeId`, `GET /api/users/:id/favorites`. 마이페이지 '찜한 케어'→'찜한 가게' 이름 변경 + 실제 찜 개수 뱃지 + `FavoritesView` 목록 화면(타입별 아이콘·가게명·주소·호텔/유치원 태그·전화번호, 행 탭 시 상세 이동, 하트로 즉시 해제). `MapPin.storeKeyOverride`로 보강 주소로 복원해도 원본 키 유지 — 배포·curl 검증 + **시뮬레이터 실기기 확인 완료**, 커밋 `061dc02` push 완료
- [x] **미사용 파일 정리** (2026-07-08) — `Config/Untitled.swift`(빈 orphan 파일), SwiftUI 전환 이전 UIKit 프로토타입 잔재 `ViewController.swift`·`FeatureViewControllers.swift`·`DataManager.swift`·`All_data.csv`(총 2000줄+/367KB, 실행 경로에서 전혀 안 쓰임) 삭제. 삭제 과정에서 이 파일들이 정의하던 `DogCareStore`/`PetProfile`/`DiaryEntry`/`ChatMessageItem` 모델을 `APIClient.swift`가 참조 중이던 것을 발견 — 실제 호출처를 전수 조사해 `fetchStores`/`createReservation`/`fetchDiaries`/`fetchMessages`/`sendMessage`는 전부 호출처 0개(지도는 `AnimalBoardingService`, 예약은 `BookingView` 직접 URLSession, 채팅은 `ChatService`가 각각 담당)로 확인해 관련 타입까지 함께 제거. 유일하게 살아있던 `fetchPets`(`MyPageView` 강아지 수 뱃지용)가 의존하던 `PetProfile`만 `APIClient.swift`로 옮겨 보존. xcodebuild `BUILD SUCCEEDED` 재검증 완료, 커밋 `39f641a`·`5297fd5` push 완료
- [x] **예약 내역 사이드바 이동 수정 + 가게 타입별 이모지 표시** (2026-07-08) — 홈 화면 발자국 메뉴의 '예약 내역'을 누르면 예약 신청 화면(`.booking`)이 열리던 버그를 `.reservationList`로 수정. 예약 카드에 호텔🏨/유치원🏠 이모지가 표시되지 않던 문제는 예약 시점의 실제 가게 타입(`MapPin.type`)을 `POST /api/reservations`로 함께 보내 `stores.store_type`에 채우도록(찜 기능과 동일한 fill-only-if-empty 패턴 재사용) 백엔드를 확장하고, `GET /api/users/:id/reservations`·`ReservationSummary.storeType`으로 내려받아 표시. 지금부터 새로 예약하는 건부터 적용되며, 찜도 예약도 한 적 없는 과거 가게는 계속 기본 🏠로 표시됨. 커밋 `f99e93a`
- [x] **예약 취소 기능** (2026-07-08) — 예약 내역 카드마다 '예약 취소' 텍스트 버튼 추가(확인 알림 + 낙관적 업데이트, 실패 시 원상복구). 백엔드에 `PATCH /api/reservations/:id/cancel` 신설(상태를 CANCELED로 변경). 커밋 `5038347`
- [x] **마이페이지 로그아웃 연결** (2026-07-08) — 액션이 연결되지 않아 눌러도 반응이 없던 '로그아웃' 항목에 확인 알림 + `AuthSession.logout()` 연결. `AppRouter`에 `reset(to:)` 메서드를 추가해 로그아웃 시 내비게이션 스택을 `[.start]`로 통째로 교체(뒤로가기로 로그아웃된 채 마이페이지 등 이전 화면에 재진입하는 문제 방지). 커밋 `88c071b`
- [x] **사장님 모드(받은 예약 요청 확정) + 기기 캘린더 저장** (2026-07-09) — 예약 상태가 REQUEST에서 CONFIRMED로 전환될 경로가 아예 없던 것을 발견해 신설. 백엔드 `GET /api/reservations/pending`(REQUEST 전체, 가게·강아지 조인), `PATCH /api/reservations/:id/confirm` 추가(배포 완료). iOS `OwnerModeView` 신규 — 받은 예약 요청 목록 + 확정 버튼, 확정 시 EventKit(`CalendarService`)으로 기기 캘린더에 일정 추가(예약 취소 시 함께 삭제). Info.plist에 캘린더 권한 설명 추가. 업체-가게 소유 관계가 DB에 없어 전체 요청을 함께 보여주는 데모 범위
- [x] **사장님 모드 사이드바 통합 재설계** (2026-07-09) — 로그인 후 역할에 따라 진입 화면을 분기하던 구조가 뒤로가기·앱 재실행 시 사장님 세션을 손님 홈으로 오라우팅하던 문제를 구조적으로 제거. 로그인 후 목적지를 모두 `.home`으로 통일하고, 역할은 `AuthSession.isOwner`(UserDefaults 영속)에 귀속. 시작 화면의 역할 선택은 "보호자 / 보호자·사장님"으로 명칭 정리, 보호자·사장님 계정에만 홈 사이드바(FAB)에 '받은 예약 요청' 항목 노출
- [x] **첫 화면 프리즈 버그 수정 — SwiftUI AttributeGraph 순환** (2026-07-09) — 콜드 런치 직후 시작 화면에서 역할 카드를 탭해도 체크/테두리가 안 바뀌던(상태는 바뀌나 `body`가 재평가 안 되던) 버그. `simctl` 콘솔 캡처로 `AttributeGraph: cycle detected` 로그를 잡아 원인 특정 — `body` 평가 중 `UIApplication.safeAreaTop`(UIKit 윈도우 `safeAreaInsets`)을 읽어, 레이아웃 미확정 상태의 콜드 런치에서 레이아웃 피드백 순환이 생기고 SwiftUI가 갱신 전파를 끊어 화면이 얼어붙음. safe area를 `@State`에 캐시하고 `onAppear`에서 채우는 `.safeAreaTopPadding()` `ViewModifier`로 묶어 `body`가 UIKit 레이아웃을 읽지 않게 함. 같은 위험 패턴이 있던 화면 12곳 전부 이 모디파이어로 통일. 콘솔 캡처로 순환 1건→0건 검증 + **시뮬레이터 실동작 확인 완료**. 상세는 `docs/PORTFOLIO.md` §7
- [x] **예약 취소 시 캘린더 일정 삭제 수정** (2026-07-09) — 예약을 취소해도 확정 시 기기 캘린더에 추가된 일정이 그대로 남던 버그. 캘린더 권한을 쓰기 전용(`requestWriteOnlyAccessToEvents`)으로만 받아 이벤트 조회(`event(withIdentifier:)`)가 불가능해 삭제가 조용히 실패하던 것이 원인. iOS 17+ 권한을 전체 접근(`requestFullAccessToEvents`)으로 바꾸고 `removeReservationEvent`를 async화해 삭제 전 권한 요청, Info.plist에 `NSCalendarsFullAccessUsageDescription` 추가(미사용 write-only 키 제거). 시뮬레이터 실동작 확인 완료, 커밋 `0b2a5f8`
- [x] **카카오 로그인 취소·에러 문구 잔류 수정** (2026-07-09) — (1) 로그인 창을 사용자가 직접 닫아도 빨간 '로그인에 실패했어요' 문구가 뜨던 것을, 취소(`SdkError.ClientFailed(.Cancelled)`) 감지 시 표시하지 않도록 수정. (2) `errorMessage`를 로그인 시도 시작 때만 초기화해, 취소로 뜬 문구가 개발자 진입→로그아웃→start 복귀 후에도 남던 문제를 `logout()`·`loginAsDeveloper()`에서 `errorMessage = nil`로 해결
- [x] **사장님↔손님 양방향 채팅** (2026-07-11) — 기존 채팅이 손님→가게 단방향(사장님이 문의를 볼 방법 자체가 없음)이던 것을 실제 양방향으로 확장. **백엔드:** 마이그레이션 0007로 `stores.owner_id` 신설(사장님-가게 소유 연결), `POST /api/stores/claim`(가게 상세 '내 가게로 등록' — `store_key` upsert 재사용, 남의 가게면 409), `GET /api/owners/:id/stores`, `GET /api/owners/:id/chatrooms`(내 가게로 온 문의방 목록, 손님 닉네임 조인) 추가 — 배포 + curl 시나리오 검증 완료(등록→손님 문의→사장님 문의함 노출→답장→손님 목록/방에 반영→409 충돌). **iOS:** 가게 상세 카드에 사장님 전용 '내 가게로 등록' 버튼(등록되면 '내 가게' 뱃지), 채팅 목록 상단에 '받은 문의' 섹션 분리(손님 닉네임+가게명 행, 탭하면 기존 `ChatRoomView` 재사용 — 말풍선이 `sender_id` 기준이라 수정 없이 사장님/손님 시점 모두 자연스럽게 표시), 채팅방에 3초 폴링 추가로 방을 열어둔 동안 상대 메시지 자동 반영. 별도 문의함 화면 대신 기존 채팅 목록에 섹션으로 통합(사용자 결정). xcodebuild BUILD SUCCEEDED. 커밋 `3fd8df1`
- [x] **역할별 계정 분리 + 내 가게 등록을 마이페이지로** (2026-07-12) — 견주/사장님이 같은 계정 플래그를 공유해 채팅·최근 본 가게가 섞이고, 사장님이 보낸 메시지도 견주가 보낸 것처럼(같은 sender_id) 보이던 구조 문제를 해결. **역할 귀속:** 마이그레이션 0008로 `users.is_owner` 신설 — 역할은 최초 가입 시 카카오 계정에 영구 귀속, 같은 계정으로 반대 역할 가입 시 서버 409 + iOS 안내 문구(탈퇴 기능은 미구현, v2). 개발자 진입도 `dev-simulator`(견주)/`dev-simulator-owner`(사장님) 별개 계정으로 분리해 시뮬레이터 한 대에서 양쪽 테스트 가능. 로그아웃 시 `AppRouter.reset`이 `recentPins` 등 세션 데이터도 초기화. **내 가게 등록 이동:** 가게 상세의 등록 버튼을 제거하고 마이페이지 '내 정보' 최상단 '내 가게' 항목(사장님 전용) → `MyStoreSheet`에서 공공데이터 상호명 부분일치 검색(2글자+, 최대 30건) → 확인 알림 후 등록, 등록된 가게 목록·해제 버튼(`DELETE /api/owners/:id/stores/:storeId` 신설 — 잘못 등록 복구 경로) 제공. 등록된 가게는 가게 상세에 '내 가게' 뱃지 유지. 배포 + curl 검증(보호자 가입→사장님 로그인 409→재로그인 200→사장님 계정 is_owner 1→등록→해제) 완료, 어제 테스트로 남은 가게 19 소유 잔재 정리. xcodebuild BUILD SUCCEEDED. 커밋 `3fd8df1` (양방향 채팅과 합본, push 완료). **시뮬레이터 실동작 확인 완료**
- [x] **받은 예약 요청 내 가게 스코프 + 최근 본 가게 계정별 영속** (2026-07-12) — (1) 받은 예약 요청이 전체 가게의 REQUEST를 보여주던 데모 방식을 owner 스코프로 교체: `GET /api/reservations/pending` 제거 → `GET /api/owners/:id/reservations/pending` 신설(`stores.owner_id` JOIN 필터), `OwnerModeView`가 로그인 사장님 id로 조회하고 빈 화면에 '내 가게 등록' 안내 추가. 배포 + curl 검증(내 가게 요청만 1건 / 남의 가게 요청 미노출) 완료. (2) '최근 본 가게'가 메모리 값이라 재로그인 때마다 사라지던 것을 계정별 UserDefaults 영속으로 변경: `MapPin`을 Codable화(id는 제외)하고 `AppRouter.addRecentPin()`(중복 제거 + 최신순 + **최대 6개, 오래된 것부터 삭제** + 저장)·`setActiveUser()`(계정별 `recent_pins_<userId>` 키 복원) 신설, `RootView`의 `.task(id: userId)`로 로그인·로그아웃·콜드 런치 세션 복원 시 자동 전환. 견주/사장님 계정이 각자의 최근 목록을 유지한다. xcodebuild BUILD SUCCEEDED. **시뮬레이터 실동작 확인 완료**. 부수 문서 갱신: `PORTFOLIO.md` §8(양방향 채팅·역할 계정 분리 설계), 백엔드 README API 목록 최신화, iOS README 개발자 진입(역할별 2계정) 안내

---

## 남은 작업

### 단기 (배포 전 필수)

- [ ] **Task 5** — 네이버 블로그 API 키 발급 (사용자가 직접 해야 함 — 개인 계정으로 앱 등록)
  - https://developers.naver.com 에서 앱 등록
  - `Create.xcconfig`에 `NAVER_CLIENT_ID`, `NAVER_CLIENT_SECRET` 추가
  - 완료 시 가게 상세 화면에서 블로그 후기 자동 표시

- [x] **Task 7** — README 정리 (2026-07-08) — 루트 `README.md`(프로젝트 소개), `Dog_kindergarden/README.md`(빌드 가이드: Create.xcconfig 작성법·키 발급처 표·개발자 진입 안내) 신규 작성. `backend-cloudflare/README.md`의 API 목록을 현재 라우트로 최신화. 부수적으로 **문서 오류 발견·수정**: 실제 Xcode 빌드 설정(`baseConfigurationReference`)이 가리키는 파일은 `Secret.xcconfig`가 아니라 `Base.lproj/Config/Create.xcconfig`였음 — CLAUDE.md 등 관련 문서를 실제 경로로 정정 (git에 커밋된 적 없어 키 유출은 없음)

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
| 찜한 가게 | ✅ 구현 완료 |
| 사장님 모드(예약 확정) + 캘린더 | ✅ 구현 완료 (백엔드 배포 완료) |
| 사장님↔손님 양방향 채팅 | ✅ 구현 완료 (배포·curl·시뮬레이터 확인 완료) |
| 역할별 계정 분리 + 마이페이지 내 가게 등록 | ✅ 구현 완료 (배포·curl·시뮬레이터 확인 완료) |
| 받은 예약 요청 내 가게 스코프 + 최근 본 가게 영속 | ✅ 구현 완료 (배포·curl·시뮬레이터 확인 완료) |
| README | ✅ 작성 완료 |

---

## Git 현황

- **저장소:** 모노레포 단일 repo, `main` 브랜치. origin 최신 커밋 `76599d3`(push 완료). 미커밋: 받은 예약 요청 내 가게 스코프 + 최근 본 가게 계정별 영속 (커밋 예정)
- **백엔드:** `backend-cloudflare/` — Cloudflare Workers 배포 완료
- **배포 URL:** `https://matgyeomung-api.dog-kindergarden.workers.dev`
