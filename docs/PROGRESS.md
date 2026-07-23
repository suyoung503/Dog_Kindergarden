# 맡겨멍 — 현재 진행상황 및 다음 단계

**마지막 업데이트:** 2026-07-24

---

## 완료된 작업

### 배포 준비

- [x] **Task 1** — `.gitignore` 생성 + `_png_원본/` 삭제 + Pods git 추적 제거
- [x] **Task 2** — API 키 xcconfig 분리 (`Secret.xcconfig`, Info.plist 변수 참조)
- [x] **Task 3** — 백엔드 `.gitignore` + TypeScript `any` 타입 제거
- [x] **Task 4** — 하드코딩 사용자 정보 → `UserProfile` 모델로 교체
- [x] **Task 6** — 미커밋 변경사항 정리 및 GitHub push
- [x] **배포 준비 리포트 재점검** (2026-07-13, `b0eb3ac`) — 판정 ❌→⚠️ Conditional. 6/21의 블로커(공공 API 키 하드코딩)와 경고 대부분 해소 확인, 구 키 노출은 저장소 재생성(2026-07-07 초기화)으로 이력 자체가 없음을 확인해 재발급 불필요 처리. 신규 발견: npm audit high 5건(런타임은 hono 1건, 나머지 wrangler 개발 체인). 남은 수동 확인: Kakao 콘솔 번들 ID 제한 설정

### 기능 구현 (커밋 완료)

- [x] 공공데이터 동물위탁관리업 API 연동 (TM→WGS84 좌표 변환 포함)
- [x] 카카오 지도 핀 표시 + 도별 필터링
- [x] 카카오 로컬 API로 주소 보강
- [x] 보호자 펫 리뷰 시스템 (Cloudflare Workers 백엔드 연동)
- [x] 네이버 블로그 후기 연동 — 2026-07-17 NCP NAVER API HUB 키 발급·연동으로 활성화
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
- [x] **받은 예약 요청 내 가게 스코프 + 최근 본 가게 계정별 영속** (2026-07-12) — (1) 받은 예약 요청이 전체 가게의 REQUEST를 보여주던 데모 방식을 owner 스코프로 교체: `GET /api/reservations/pending` 제거 → `GET /api/owners/:id/reservations/pending` 신설(`stores.owner_id` JOIN 필터), `OwnerModeView`가 로그인 사장님 id로 조회하고 빈 화면에 '내 가게 등록' 안내 추가. 배포 + curl 검증(내 가게 요청만 1건 / 남의 가게 요청 미노출) 완료. (2) '최근 본 가게'가 메모리 값이라 재로그인 때마다 사라지던 것을 계정별 UserDefaults 영속으로 변경: `MapPin`을 Codable화(id는 제외)하고 `AppRouter.addRecentPin()`(중복 제거 + 최신순 + **최대 6개, 오래된 것부터 삭제** + 저장)·`setActiveUser()`(계정별 `recent_pins_<userId>` 키 복원) 신설, `RootView`의 `.task(id: userId)`로 로그인·로그아웃·콜드 런치 세션 복원 시 자동 전환. 견주/사장님 계정이 각자의 최근 목록을 유지한다. xcodebuild BUILD SUCCEEDED. **시뮬레이터 실동작 확인 완료**. 부수 문서 갱신: `PORTFOLIO.md` §8(양방향 채팅·역할 계정 분리 설계), 백엔드 README API 목록 최신화, iOS README 개발자 진입(역할별 2계정) 안내. 커밋 `b35e4c8` push 완료
- [x] **사장님 시점 채팅·예약 다듬기 4건** (2026-07-12) — (1) 자동메시지("예약 요청이 완료되었습니다", sender 0)가 사장님 채팅화면에서 고객 말풍선(왼쪽)으로 보이던 것을 수정: `AppRouter.chatRoomAsOwner` 플래그 신설(받은 문의 진입만 true, 나머지 4개 진입점 false), `ChatRoomView.map`이 사장님 시점에서 sender 0을 내(오른쪽) 말풍선으로 처리. (2) 사장님 시점 채팅방 상단의 '응답중' 표시 숨김(가게 상태 표시라 상대가 손님일 땐 무의미). (3) 캘린더 일정이 사장님 기기에 저장되던 문제 수정 — 코드 확인 결과 `OwnerModeView.confirm`이 확정 기기(사장님 폰)의 EventKit에 추가하고 있었음. **고객이 예약 요청을 넣는 순간**(`BookingView` 성공 직후) 고객 기기 캘린더에 일정을 추가하는 방식으로 전환하고 사장님 기기 추가 코드는 제거. 삭제는 본인 취소 시 즉시, 사장님 취소는 고객이 예약 내역을 열 때 `CalendarService.syncReservationEvents`가 CANCELED를 관찰해 삭제(서버 푸시 없음). (4) 받은 예약 요청에 '예약 취소' 버튼 추가(확인 알림 + 기존 `PATCH /api/reservations/:id/cancel` 재사용) — 고객 예약 내역에 '예약 취소됨'으로 표시되고 (3)의 동기화가 고객 캘린더 일정도 삭제. (5) 테스트 중 "캘린더에 저장 안 됨" 제보의 진짜 원인 발견 — 예약 날짜 칩이 `"금 6/12"…` 6월 하드코딩이라 이미 지난 날짜가 됐고, `parseSchedule`의 '지난 날짜면 +1년' 규칙에 걸려 일정이 **2027년 6월**에 저장되고 있었음(저장은 됐지만 안 보임). 날짜 칩을 오늘부터 6일 동적 생성(`ko_KR` "E M/d")으로 교체. (6) 그래도 저장 안 되던 2차 원인은 시뮬레이터 TCC 캘린더 권한이 이미 거부(0) 상태였던 것 — iOS는 한 번 거부하면 재요청 알림을 안 띄워 조용히 실패. `xcrun simctl privacy booted grant calendar net.suyoung.Dog-kindergarden`으로 허용 처리. 백엔드 변경 없음. xcodebuild BUILD SUCCEEDED. 커밋 `9f7a9e0` push 완료
- [x] **캘린더 권한 거부 시 설정 이동 안내** (2026-07-12) — 캘린더 권한을 한 번 거부하면 iOS가 시스템 알림을 다시 띄우지 않아 예약 일정 저장이 조용히 실패하던 것을 보완. 기기 불문 자동 허용은 iOS 정책상 불가(실기기는 사용자 직접 허용 필수, 시뮬레이터만 `simctl privacy`로 사전 허용 가능)하므로, 예약 성공 후 일정 저장이 권한 거부(`CalendarService.isAccessDenied` 신설, `EKEventStore.authorizationStatus == .denied`)로 실패하면 `BookingView`가 알림("캘린더 권한이 꺼져 있어요")을 띄워 '설정에서 허용'(설정 앱 딥링크) / '건너뛰기'를 제공 — 어느 쪽이든 예약 완료 화면으로 이동, 예약 자체는 정상 처리. xcodebuild BUILD SUCCEEDED. 커밋 `382f2c0` push 완료
- [x] **기능 명세 문서 신설** (2026-07-12) — `docs/FEATURES.md` 작성: 문서만 읽어도 앱 전체 기능을 파악할 수 있도록 화면 지도 + 도메인별 기능(계정/지도/가게 상세/예약/채팅/리뷰/찜/강아지 프로필/마이페이지/사장님 기능) + 백엔드 API 요약 표 + 설계 불변식 + 미완성 범위를 정리. 조사 과정에서 `POST /api/reviews`·`GET /api/stores/:id/reviews`·`GET /api/diaries/:reservationId`가 iOS에서 호출처 없는 구버전 잔재임을 확인해 문서에 명시
- [x] **구버전 잔재 라우트·클라이언트 코드 제거** (2026-07-12) — FEATURES.md 조사에서 확인된 미사용 코드 삭제. **백엔드:** `POST /api/reviews`·`GET /api/stores/:id/reviews`(pet-reviews로 대체된 구 리뷰 계열)·`GET /api/diaries/:reservationId`(다이어리 기능 미구현) 라우트 3개와 전용 타입 `ReviewBody` 제거 — 배포 + curl 검증(삭제 라우트 404 / `pet-reviews/tags` 200) 완료. **iOS:** 호출처 0개였던 `APIClient.createReview`·`fetchStoreReviews`와 전용 타입 `ReviewResponse`·`ReviewCreateRequest`·`ReviewItem` 제거. DB의 `reviews`·`diaries` 테이블은 마이그레이션 이력이라 그대로 둠(reviews 0행, diaries는 0001 시드 데모 1행뿐 — 라우트만 제거). 백엔드 README API 목록·FEATURES.md 표에서도 해당 라우트 삭제. xcodebuild BUILD SUCCEEDED
- [x] **이용일 다음날 리뷰 요청 자동 메시지** (2026-07-12) — 확정(CONFIRMED) 예약의 이용일 다음날, 그 (손님+가게) 채팅방에 자동 메시지(sender 0, '맡겨멍')로 리뷰 작성 요청을 보내는 기능. Cloudflare **Cron Triggers**(`wrangler.toml` crons `0 16 * * *` = 매일 KST 01시)가 `scheduled` 핸들러로 `sendReviewRequests` 실행 — `start_date`("토 7/11 14:00")에 연도가 없어 KST 기준 어제의 "월/일" 문자열 LIKE 대조로 대상 선별, 마이그레이션 0009(`reservations.review_requested` 플래그)로 중복 발송 방지. 데모·테스트용 수동 트리거 `POST /api/internal/review-requests` 추가. 마이그레이션 원격 적용 + 배포 + curl 종단 검증(가입→어제 날짜 예약→확정→트리거 sent:1·방에 메시지 확인→재트리거 sent:0) 후 일회용 데이터 정리 완료. iOS 변경 없음(기존 채팅 로드/3초 폴링으로 자동 표시)
- [x] **리뷰 요청 발송 시각 18시 변경 + 예약 날짜 캘린더형·연도 포함** (2026-07-12) — (1) 리뷰 요청 Cron을 KST 01시→**18시**(`0 9 * * *`)로 변경. (2) 예약 날짜 선택을 6일 칩에서 **캘린더(그래픽 DatePicker)** 로 교체 — 오늘 이후 원하는 날짜 자유 선택(`in: Date()...`). (3) 예약 문자열을 연도 포함 `"2026-07-12 (일) 14:00"` 형식(`BookingViewModel.dateLabel`)으로 저장, `CalendarService.parseSchedule`도 추정('지난 날짜면 +1년') 없이 정확한 연·월·일 해석으로 재작성. (4) 리뷰 요청 대조를 신형은 `YYYY-MM-DD` 정확 매칭, 연도 없는 구형 데이터는 기존 월/일 매칭으로 병행 처리. 배포 + curl 검증(신형·구형 예약 각 1건 → 트리거 sent:2·방 메시지 2건 → 재트리거 sent:0) 후 일회용 데이터 정리, xcodebuild BUILD SUCCEEDED. 커밋 `a413292` push 완료
- [x] **사장님 예약 취소 시 고객 채팅방 자동 메시지 + 예약 신청 화면 취소 가능 경고 문구** (2026-07-12) — 사장님이 받은 예약 요청을 취소하면 고객이 상태 변경을 알 수 있게 해당 (손님+가게) 채팅방에 자동 메시지(sender 0, '맡겨멍', AUTO: "가게 사정으로 {가게명} 예약({일시})이 취소되었어요. 예약 내역에서 확인해주세요 🙏") 전송. 기존 `PATCH /api/reservations/:id/cancel`에 optional 바디 `by_owner`를 추가해 구분 — 고객 본인 취소(바디 없음)는 기존대로 메시지 없이 상태만 변경. iOS는 `APIClient.cancelReservation(byOwner:)` 파라미터 신설, `OwnerModeView`에서만 true 전달. 함께 `BookingView` 신청 버튼 위에 "가게 사정으로 예약이 취소될 수 있어요. 취소되면 채팅으로 알려드려요." 경고 문구 추가. 배포 + curl 검증(고객 취소 → 메시지 0건 / 사장님 취소 → 취소 안내 1건) 후 일회용 데이터 정리(잔존 0), xcodebuild BUILD SUCCEEDED. 커밋 `f83a7ba` push 완료
- [x] **홈 종 아이콘 안 읽은 채팅 빨간 점** (2026-07-12) — 홈 우상단 종(기존: 동작 없는 장식 + 항상 켜진 빨간 점)을 실제 안 읽은 채팅 표시로 전환. **읽음 상태 스키마**: 마이그레이션 0010 `chat_room_reads(room_id, user_id, last_read_message_id)` — 손님·사장님이 같은 방을 각자 시점으로 읽으므로 (방+사용자)별 추적. **백엔드**: `POST /api/chatrooms/:id/read`(열람 시점 마지막 메시지까지 읽음 upsert), `GET /api/users/:id/unread-count` — 손님 시점(내가 손님인 방들의 상대·자동(sender 0) 메시지)은 모든 계정 공통, **사장님 계정은 내 가게 방들의 손님 메시지를 합산**(사장님도 다른 가게엔 손님이므로 분기가 아니라 합산 — 사용자 지적으로 초기 분기 구현을 정정. 사장님 몫은 sender 0 제외 + 내가 손님인 방 제외로 중복 집계 방지). **iOS**: `ChatService.unreadCount`/`markRead` 신설, `ChatRoomView` 최초 로드·폴링 신규분 도착 시 읽음 처리, `HomeView` 종에 `.task` 갱신(홈 복귀마다) + 안 읽은 게 있을 때만 빨간 점 + 탭 시 채팅 목록 이동. 원격 마이그레이션 적용 + 배포 + curl 검증 7단계(보호자: AUTO 1건 unread:1 → 읽음 0 → 본인 메시지 제외 0 → 상대 답장 1 / 사장님: 손님 메시지만 1 → 읽음 0 → 새 문의 1) + 합산 검증(사장님이 손님으로 둔 방 AUTO 1 + 내 가게 문의 1 = 2 → 방별 읽음 1 → 0, 보호자 회귀 1) 후 일회용 데이터 정리(잔존 0), xcodebuild BUILD SUCCEEDED. 커밋 `2432891` push 완료
- [x] **예약 유형 3종 개편 (시간권·종일권·하루 숙박권) + 정기권 안내** (2026-07-13) — 예약 유형을 실제 존재하는 3종으로 정리: **시간권**(시간당 ₩5,000 × 이용 시간 1~6시간, 날짜 + 시작 시간 자유 선택(시간 피커) + 이용 시간), **종일권**(₩35,000)·**하루 숙박권**(₩50,000, 둘 다 날짜만 선택 — 시간 UI 숨김). 구 유형(유치원 반일권/종일권, 호텔 1박, 장기 이용) 제거. `reservation_type`은 "시간권 3시간"처럼 이용 시간 포함 문자열로 저장(서버는 자유 문자열이라 변경 없음), 예약 문자열은 시간권만 시간 포함("2026-07-13 (월) 14:00"), 종일권·숙박권은 날짜만("2026-07-13 (월)") — `CalendarService.parseSchedule`이 날짜만 형식도 해석하고 이때 캘린더에 **종일 일정**으로, 시간권은 이용 시간만큼 기간을 잡아 저장. 정기권은 상품에서 빼고 모든 가게 상세의 체크리스트에 "정기권은 가게에 문의해주세요" 문구로 안내. 서비스 선택 섹션을 날짜 선택 위로 이동(유형에 따라 시간 UI가 달라지므로 먼저 고르는 흐름). 백엔드 cron 리뷰 요청의 `LIKE 'YYYY-MM-DD%'` 대조는 날짜만 형식도 그대로 매칭돼 영향 없음. FEATURES §4·PORTFOLIO 갱신. xcodebuild BUILD SUCCEEDED
- [x] **받은 예약 요청 상세 시트 + 카드 강아지·견주 구별 표시** (2026-07-13) — 사장님 '받은 예약 요청' 카드를 탭하면 화면 이동 없이 **하단 시트**(`PendingDetailSheet`, detents medium/large)로 강아지 정보(이름·견종·나이·몸무게·성별·메모)·예약자 정보(이름·연락처·주소)·예약 정보(가게·일정·유형·요청사항)를 표시(제목·라벨은 이모지 없이 텍스트만). 카드에는 "강아지 : 이름"·"예약자 : 이름" 라벨로 구별해 두 줄로 노출. 백엔드 `GET /api/owners/:id/reservations/pending`에 `pets`(breed·age·weight·gender·note)·`users`(nickname·phone·address) 조인 필드 추가(스키마 변경 없음), iOS `PendingReservation`에 optional 필드 확장 + `Identifiable`(sheet(item:)용). 배포 + curl 종단 검증(일회용 사장님·손님·펫·가게·예약 생성 → 새 필드 9종 응답 확인 → 전부 삭제, 잔존 0) 완료, xcodebuild BUILD SUCCEEDED
- [x] **백엔드 의존성 취약점 해소 (npm audit fix)** (2026-07-13) — npm audit 6건(high 5·low 1) 전부 해소: **hono 4.6.10→4.12.30**(런타임에 실리는 유일한 의존성 — path traversal·CORS 반사 등 5건), wrangler 4.93.0→4.110.0(esbuild·miniflare·undici·ws 동반 갱신, 전부 devDeps). package.json 범위 내 semver 갱신이라 **lockfile만 변경**. 로컬 `node_modules`·`package-lock.json`이 root 소유라 npm 쓰기 불가 → lockfile은 삭제·재복사로 소유권 복구, 설치·audit fix는 스크래치패드 사본에서 수행(`npm_config_cache` 우회) 후 갱신된 lockfile만 저장소로 복사. 갱신된 wrangler로 **재배포**(Version `e9147861`, cron 트리거 유지) + 읽기 전용 curl 스모크(stores 200 · unread-count · chatrooms 정상). `node_modules`는 여전히 root 소유(macOS가 root 소유 디렉터리 rename도 거부) — 로컬 npm 작업이 필요해지면 `sudo chown -R suyoung:staff node_modules ~/.npm` 1회 실행으로 해소
- [x] **채팅 프로필 아이콘 정리 + 에셋 이름 변경** (2026-07-13) — 채팅 목록 '내 채팅'(보호자 시점) 프로필을 순환 이모지에서 **가게 타입별 아이콘**(유치원 kindergarden / 호텔 hotel)으로 교체 — 백엔드 `GET /api/users/:id/chatrooms`에 `store_type` 추가(배포 + 기존 계정 읽기 전용 curl 확인). 사장님 '받은 문의'의 보호자 프로필은 🙋 이모지에서 **강아지 아바타(dog_b/dog_c, room_id 기준 고정 순환)**로 교체. 채팅방(ChatRoomView) 상단·상대 말풍선 프로필도 동일 규칙 — `AppRouter.chatRoomAvatar` 신설, 채팅방 진입점 4곳(가게 상세 문의·예약 완료·내 채팅·받은 문의) 모두에서 설정. 에셋 `icon_kindergarten` → **`kindergarden`**으로 이름 변경(imageset·PNG·Contents.json·`petAssetName` 매핑). xcodebuild BUILD SUCCEEDED
- [x] **사용자별 데이터 분리 전수 검증 + 하드코딩·폴백 제거** (2026-07-12) — 서로 다른 계정 간 채팅·찜·예약·펫·최근 본 가게 혼입 여부 전수 점검. **서버 쿼리 스코프는 전부 정상**(예약·펫·채팅방·찜·받은 문의·받은 요청·unread 모두 user_id/owner_id 조건 확인), recentPins 계정별 영속·`AppRouter.reset`·캘린더 매핑(reservation_id 전역 유일 + 본인 예약만 sync)도 이상 없음. **발견·수정 5건:** (1) **실제 혼입 — `UserProfile`(이름·연락처·주소)이 계정 무관 전역 UserDefaults**: 로그인 시 서버 프로필이 비어 있으면 이전 계정 값이 그대로 남아 새 계정의 예약·프로필에 노출되던 것을, `AuthSession`이 서버 값으로 **무조건 덮어쓰도록**(비어 있으면 초기화) 수정. (2) iOS `?? 1` 폴백 3곳(`ChatRoomView`·`ChatListView`·`StoreDetailView.openChat`) → guard로 교체(미로그인 시 user 1 행세 차단). (3) `APIClient.fetchPets(userId: Int = 1)` 기본값 제거. (4) DEBUG 개발자 로그인의 오프라인 폴백 `userId = 1`(실제 user 1 행세) 제거 → 에러 표시. (5) **서버 `?? 1` 폴백 4곳**(예약 user_id/pet_id, 메시지 sender_id, lookup·방생성 user_id) → 400 반환. 배포 + curl 검증(400 케이스 5종 + 정상 회귀), 전파 지연 중 구버전이 room 1에 넣은 테스트 메시지 1건 확인·삭제, 일회용 데이터 잔존 0, xcodebuild BUILD SUCCEEDED. **남은 한계(기록)**: API 무인증(user_id 신뢰), 취소/확정·펫 삭제 소유 검증 없음, pet_reviews는 user_id 미저장(작성자 이름만) — FEATURES §13에 데모 범위로 명시
- [x] **알림장(diary) 기능 + 이모지 asset 정리** (2026-07-17) — **(1) 알림장:** 예약별로 사장님이 글을 남기고 보호자가 보는 타임라인(예약당 여러 장 시간순). 마이그레이션 0011 `diary_photos`(사진용 — R2 미활성이라 스키마만, API는 항상 빈 `photos:[]` 반환하는 전방호환 계약), 기존 `diaries` 테이블 재사용. 백엔드: `GET/POST/PATCH/DELETE /api/reservations/:id/diaries`·`/api/diaries/:id`, 사장님 '맡은 아이들'용 `GET /api/owners/:id/reservations/confirmed`(확정 예약 + pets·users 조인). **작성 시에만** 보호자 채팅방에 자동 메시지(sender 0) — 수정·삭제는 메시지 없음. iOS: 사장님 홈 FAB '알림장' → `OwnerDiaryListView`(맡은 아이들) → `DiaryTimelineView`(작성/수정/삭제, `DiaryComposer` 시트), 보호자는 예약 내역 확정 카드 '알림장 보기'로 같은 화면 열람 전용. `AppRouter.diaryContext`(예약·강아지·가게·쓰기권한)로 전달, `.diary`/`.ownerDiaryList` 화면 추가. 보호자 화면 강아지 이름은 `GET /api/users/:id/reservations`에 `pets` 조인해 실제 이름 표시. 사진 업로드·표시는 R2 활성화 후 가산(테이블·contract 준비됨). 배포 + curl 종단 검증(400/404·작성+자동메시지·타임라인·수정·삭제·수정삭제 무메시지) 후 일회용 데이터 정리(잔존 0), **시뮬레이터 실동작 확인 완료**. **(2) 이모지 asset 정리:** 유니코드 이모지를 브랜드 asset(PNG)으로 통일. 새 imageset 3개(`emoji_calendar`/`emoji_chat`/`emoji_note`, 사용자가 카탈로그에 넣은 loose PNG를 정식 imageset으로 정리) + `petAssetName` 매핑 추가 → 예약 내역·예약 폼 날짜(📅)·채팅 목록·가게 상세 채팅 버튼(💬)·알림장 빈 상태(📔)를 `EmojiIcon`/`EmojiTitle`로 asset 전환. asset 없는 이모지(📭 👤 ✍️ 📝 📹 🚗 💛 🔁 🙏 등, 리뷰 태그 이모지 포함) 전부 제거 — 받은 예약 없음 화면은 예약 관련이라 📭→캘린더 asset으로 대체. 흐르는 텍스트 안의 발자국은 자산 이미지 크기가 잡히지 않아(기본 본문 폰트로 커짐) 로그인 하단·채팅 자동 메시지 등 인라인 발자국은 제거 — 발자국은 태그라인처럼 `EmojiIcon`으로 크기 고정되는 곳에만 유지. xcodebuild BUILD SUCCEEDED, 백엔드 재배포(Version `cb14b399`)
- [x] **구 reviews 테이블 드롭** (2026-07-17) — 마이그레이션 0012 `drop_reviews`. `reviews`(0002)는 `pet_reviews`(0003)/`/api/pet-reviews`로 완전히 대체된 죽은 테이블(index.ts·iOS 무참조, 배포 DB 0행 확인) → `DROP TABLE IF EXISTS reviews`. 배포 DB 적용·소멸 검증 완료, 워커 코드 무변경이라 재배포 불필요
- [x] **리뷰 태그로 지도 필터링** (2026-07-17) — 홈 지도 상단 리뷰 태그 칩으로 가게 필터(다중 선택 **AND** 조건) + 필터 리드 아이콘·선택 체크마크·전체 초기화 칩 UI. 커밋 `e2d49e8`
- [x] **가게 주소 정밀화 — 네이버 검색 API(NCP API HUB) 연동 + 화면 로직 + DB 백필** (2026-07-17) — 카카오맵에 미등록인 가게들이 마스킹 주소(`***`) 그대로 노출되던 문제 해결. **(1) API 이관 추적:** 네이버 키 인증 실패(024)의 원인이 키가 아니라 developers.naver.com 검색 API의 신규 제휴 중단 — **NCP NAVER API HUB**(`naverapihub.apigw.ntruss.com/search/v1/*`, 헤더 `X-NCP-APIGW-API-KEY-ID`/`-KEY`)로 이관된 것을 확인하고 지역 검색(`NaverLocalService` 신설)·블로그 후기(`NaverBlogService` 엔드포인트 교체) 둘 다 연결 — **블로그 후기 기능 활성화**(구 Task 5 완료). **(2) 화면 로직:** 가게 상세 주소 보강을 네이버 우선(층·건물·호 상세)으로 재구성, 전화·카카오맵 링크는 카카오 병렬 보강, 둘 다 없으면 좌표→지번 폴백. 동명 타지역 오매칭 방지로 핀 좌표 최근접 + 3km 초과 기각(실측: 동명 가게 47km 매칭 차단), 네이버 주소 끝 상호명 꼬리표 제거. **(3) DB 백필:** 찜 목록·내 가게 등 DB 주소 사용 화면을 위해 배포 D1 `stores.address` 16곳 실주소 백필 — 좌표 없는 가게는 마스킹 자릿수 정합(`*`=숫자 1자리, `인천타워대로***번길 **`→`\d\d\d`/`\d\d` 정규식)+시군구 대조로 검증, 근거 없는 4곳(댕냥숲·더견우·펫제이·반려견 마음센터 — 네이버·카카오 모두 미등록/타가게)은 마스킹 유지. **`store_key`는 정체성 키라 불변**, 표시용 address만 갱신(upsert가 address를 안 덮는 것 확인). xcodebuild BUILD SUCCEEDED, 커밋 `fdf6eb1`·`c519d61`. 상세는 `PORTFOLIO.md` §12
- [x] **채팅 시스템 메시지 분리** (2026-07-18) — 자동 메시지(sender 0: 예약 요청·취소 안내·리뷰 요청·알림장 알림)가 일반 말풍선과 섞여 좌/우로 표시되던 것을 화자 없는 **중앙 안내문**(작은 글씨 + 크림색 칩, 카톡 스타일)으로 분리. 양쪽 시점 렌더링이 동일해져 사장님 시점 말풍선 방향 보정용이던 `ChatRoomViewModel.viewingAsOwner`(configure의 `asOwner` 파라미터) 제거 — `router.chatRoomAsOwner`는 '응답중' 숨김용으로 유지. 백엔드 소스 변경 없음 — 다만 배포 DB에 개발 중간 버전 워커가 남긴 구형 알림장 메시지 3건(🐾 이모지 포함, 2건은 줄바꿈 없음)을 정리(이모지 제거 + `char(10)` 줄바꿈 삽입)하고 워커 재배포로 현행 문구(이모지 없음·두 줄)를 확정 반영. xcodebuild BUILD SUCCEEDED
- [x] **푸시 알림(서버 이벤트 피드 + 로컬 알림)** (2026-07-23) — 유료 Apple Developer 멤버십이 없어 원격 푸시(APNs)가 불가능한 제약 아래, 서버가 "새로 생긴 일"을 알려주는 통합 이벤트 피드를 제공하고 iOS가 폴링해 로컬 알림으로 번역하는 방식으로 구현. **백엔드**: 마이그레이션 0013(`reservations.confirmed_at`/`canceled_at`/`canceled_by`) + confirm/cancel 핸들러가 시각·주체 기록, `GET /api/users/:id/notifications` 신설(opaque 커서 — iOS는 내용을 해석하지 않고 그대로 보관·반환) — 알림 대상은 새 채팅·시스템 메시지(양쪽)·새 예약 요청(사장님)·예약 확정(고객)·고객 취소(사장님) 4종. **중복 방지 불변식**: 각 이벤트는 채팅 축(이미 채팅 메시지가 남는 이벤트)과 예약 축(메시지가 없는 이벤트) 중 정확히 하나로만 피드에 들어가 이벤트당 알림 1회를 보장 — 향후 확정 시 시스템 메시지를 추가하게 되면 예약 축의 `reservation_confirmed` 항목을 제거해야 이 원칙이 유지된다(설계 문서에 근거 기록). **iOS**: `AppNotificationService` 신설 — 포그라운드 30초 폴링(로그인 + 활성 상태일 때) + `BGAppRefreshTask`(`net.suyoung.Dog-kindergarden.refresh`, iOS 재량 실행)로 백그라운드 폴링 1회, 알림 탭 시 `UNUserNotificationCenterDelegate`가 채팅방/예약 내역(`ReservationListView`)/받은 예약 요청(`OwnerModeView`)으로 딥링크, 열려 있는 채팅방과 같은 방의 chat 알림은 배너 생략, 로그아웃 시 전달된 알림 전부 제거해 계정 간 잔존 방지. **검증**: 백엔드는 배포 + curl 8단계 시나리오(설계 문서 §검증 계획) 전부 통과 확인 후 테스트 데이터 삭제, iOS는 태스크별 xcodebuild `BUILD SUCCEEDED` 재현 확인 + 코드 리뷰 5건 전부 Approved(Critical/Important 0건, Minor 소수는 데모 범위 한계로 원장에 기록 후 미조치). 시뮬레이터 2계정 종단 시나리오(권한 프롬프트·배너·딥링크·BG 트리거·로그아웃 시 알림 제거)는 별도로 사람이 수행 예정. 상세 설계는 `docs/superpowers/specs/2026-07-18-push-notifications-design.md`
- [x] **로컬 알림 버그 3건 수정** (2026-07-24) — 위 푸시 알림 기능을 시뮬레이터로 실사용하며 발견한 문제 수정. (1) 같은 방으로 여러 번 알림이 오면 알림 센터에 방 기준 고정 identifier(`"\(type)-\(roomId)"`)라 나중 알림이 이전 알림을 덮어써 히스토리가 사라지던 것을 매번 고유한 `UUID` identifier로 교체 — 알림이 각각 쌓이도록 수정. (2) `UNUserNotificationCenterDelegate`의 async 버전 메서드(`willPresent`/`didReceive` async)가 ObjC completion-handler 브리징 스텁과 충돌해(`NSInternalInconsistencyException: Call must be made on main thread`) 배너·딥링크가 조용히 실패할 수 있던 것을, 전통적인 completion-handler 형태로 전환. (3) 포그라운드 배너 표시 옵션에 `.list`를 추가해 알림센터 목록에도 남도록 보완. 백엔드 변경 없음, xcodebuild BUILD SUCCEEDED
- [x] **보호자 알림장 진입 경로를 예약 내역 카드 → 홈 사이드바로 이전 + 정보구조 정리** (2026-07-24) — 보호자가 확정 예약의 알림장을 보려면 예약 내역 카드의 '알림장 보기' 버튼을 눌러야 했는데, 사장님 계정에서 사이드바(FAB)가 계속 늘어나며 사장님 전용 버튼들과 섞여 혼동된다는 지적에서 출발해 내비게이션을 재구성. **(1) 진입 경로 이전:** 사장님의 `OwnerDiaryListView`(맡은 아이들=확정 예약 목록 → 알림장)와 대칭인 `MyDiaryListView` 신설(내가 확정한 예약=맡긴 아이들 목록 → 알림장, 열람 전용) — 홈 FAB에 '확정예약·알림장' 항목으로 추가하고, `ReservationListView`의 '알림장 보기' 버튼과 관련 죽은 코드는 제거. **(2) 정보구조 재검토:** "고객 알림장 / 고객 확정예약기록 / 사장님 예약요청 리스트 / 사장님 알림장 / 사장님 확정예약리스트"까지 5개 진입점이 필요할 것 같다는 고민에 대해, 기존 알림장 목록 화면이 이미 CONFIRMED로 필터링해 가게·강아지·날짜를 보여주므로 "확정예약기록"과 "알림장"이 사실상 같은 화면이라는 점을 확인 — 화면을 늘리는 대신 두 화면(고객/사장님)을 그대로 유지하며 라벨과 그룹핑만 정리하기로 결정. **(3) FAB 구조 정리:** 보호자 항목(`fabItems`, 항상 노출)과 사장님 항목(`ownerFabItems`, `authSession.isOwner`일 때만) 사이에 구분 배지 추가 — 처음엔 작은 회색 텍스트 → 주황색(`brandOrange`) 캡슐 → 최종 짙은 갈색(`brandBrown`) 캡슐 + `storefront.fill` 아이콘으로 3차 조정(사용자가 "잘 안 보인다"를 두 차례 재지적, FAB 토글 버튼과 색이 겹치던 주황색을 브랜드에서 가장 진한 색으로 교체해 해결). 또한 신규 사용자가 '알림장'에 확정예약 목록이 들어있는지 모를 것이라는 지적에 따라 고객·사장님 두 FAB 라벨을 모두 '확정예약·알림장'으로 통일(발견성 확인됨). xcodebuild BUILD SUCCEEDED(총 5회 재검증)

---

## 남은 작업

### 단기 (배포 전 필수)

- [x] **Task 5** — 네이버 블로그 API 키 발급 — 완료 (2026-07-17). developers.naver.com 검색 API가 신규 제휴 중단이라 **NCP NAVER API HUB**에서 발급·연동(상세는 완료 항목 '가게 주소 정밀화' 참고). 가게 상세 블로그 후기 표시 활성화

- [x] **백엔드 의존성 취약점 해소** — 완료 (2026-07-13, `npm audit fix` 6건 전부 해소 + 재배포 — 상세는 완료 항목 참고)

- [x] **Task 7** — README 정리 (2026-07-08) — 루트 `README.md`(프로젝트 소개), `Dog_kindergarden/README.md`(빌드 가이드: Create.xcconfig 작성법·키 발급처 표·개발자 진입 안내) 신규 작성. `backend-cloudflare/README.md`의 API 목록을 현재 라우트로 최신화. 부수적으로 **문서 오류 발견·수정**: 실제 Xcode 빌드 설정(`baseConfigurationReference`)이 가리키는 파일은 `Secret.xcconfig`가 아니라 `Base.lproj/Config/Create.xcconfig`였음 — CLAUDE.md 등 관련 문서를 실제 경로로 정정 (git에 커밋된 적 없어 키 유출은 없음)

### 중기 (기능 확장)

- [x] ~~로그인/회원가입~~ — 카카오 로그인 연동 완료
- [x] ~~예약 API 실연동~~ — 완료 (2026-07 세션)
- [x] ~~채팅 API 클라이언트 연동~~ — 완료 (2026-07-07, `ChatService` 기반 실연동)
- [x] ~~MyPageView에서 `UserProfile` 편집 UI 연결~~ — 완료 (2026-07-07, `ProfileEditSheet`)
- [x] ~~알림장(diary)~~ — 완료 (2026-07-17, 예약당 타임라인 + 사장님 작성/보호자 열람 공유 화면 + 작성 시 채팅 자동 메시지. 사진은 R2 활성화 후)
- [x] ~~`reviews` 테이블 삭제~~ — 완료 (2026-07-17, 마이그레이션 0012 `drop_reviews`)
- [x] ~~이용일 다음날 리뷰 요청 시스템 메시지~~ — 완료 (2026-07-12, Cloudflare Cron Triggers 방식)
- [x] ~~사장님 예약 취소 시 고객에게 시스템 메시지 + 예약 신청 화면 취소 가능 경고 문구~~ — 완료 (2026-07-12, `by_owner` 플래그 방식)
- [x] ~~홈 종모양 안 읽은 채팅 알림~~ — 완료 (2026-07-12, `chat_room_reads` 스키마 + 종 탭 시 채팅 목록 이동)
- [x] ~~리뷰 태그로 지도 필터링~~ — 완료 (2026-07-17, 다중 선택 AND + 필터 UI, 커밋 `e2d49e8`)
- [x] ~~사용자별 데이터 분리 전수 검증~~ — 완료 (2026-07-12, UserProfile 잔존 수정 + `?? 1` 폴백 전수 제거. API 무인증 한계는 FEATURES §13에 기록)
- [x] ~~채팅 메시지와 시스템 메시지 분리 검토~~ — 완료 (2026-07-18, sender 0을 중앙 정렬 안내문 스타일로 분리 — 상세는 완료 항목 참고)

### 장기 (v2)

- [x] ~~업체 측 앱 (예약 승인)~~ — 별도 앱 대신 사장님 모드(받은 예약 요청 확정/취소 · 받은 문의)로 본 앱에 통합 구현. 알림장 작성은 중기 항목으로 이동
- [x] ~~푸시 알림 (FCM)~~ — 완료 (2026-07-23). 유료 Apple Developer 멤버십이 없어 FCM(APNs 경유) 대신 서버 통합 알림 피드(`GET /api/users/:id/notifications`) + iOS 로컬 알림(`UNUserNotificationCenter`) 폴링 방식으로 구현. 원격 푸시(APNs)는 유료 멤버십 확보 후 v2
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
| 네이버 블로그 API | ✅ NCP API HUB 키 연동 완료 (2026-07-17) |
| 가게 주소 정밀화 (네이버 우선 보강 + DB 백필 16곳) | ✅ 완료 (2026-07-17) |
| 알림장(diary) | ✅ 구현 완료 (사진은 R2 활성화 후) |
| 로그인/회원가입 | ✅ 카카오 로그인 |
| 예약 백엔드 연동 | ✅ 연동 완료 |
| 채팅 클라이언트 연동 | ✅ 연동 완료 |
| MyPage 프로필 편집 | ✅ 구현 완료 |
| 찜한 가게 | ✅ 구현 완료 |
| 사장님 모드(예약 확정) + 캘린더 | ✅ 구현 완료 (백엔드 배포 완료) |
| 사장님↔손님 양방향 채팅 | ✅ 구현 완료 (배포·curl·시뮬레이터 확인 완료) |
| 역할별 계정 분리 + 마이페이지 내 가게 등록 | ✅ 구현 완료 (배포·curl·시뮬레이터 확인 완료) |
| 받은 예약 요청 내 가게 스코프 + 최근 본 가게 영속 | ✅ 구현 완료 (배포·curl·시뮬레이터 확인 완료) |
| 이용일 다음날 리뷰 요청 자동 메시지 | ✅ 구현 완료 (Cron + 배포·curl 검증) |
| 사장님 취소 시 고객 채팅방 자동 메시지 | ✅ 구현 완료 (배포·curl 검증) |
| 홈 종 아이콘 안 읽은 채팅 빨간 점 | ✅ 구현 완료 (0010 마이그레이션 + 배포·curl 검증) |
| 사용자별 데이터 분리 | ✅ 전수 점검 완료 (UserProfile 잔존 수정 + 폴백 제거, API 무인증은 데모 한계로 기록) |
| 푸시 알림(서버 이벤트 피드 + 로컬 알림) | ✅ 구현 완료 (2026-07-23, 백엔드 배포·curl 검증 + iOS xcodebuild 확인 — 시뮬레이터 종단 검증은 별도 예정) |
| README | ✅ 작성 완료 |
| 백엔드 의존성 취약점 | ✅ 해소 (2026-07-13, npm audit fix 6건 + 재배포) |

---

## Git 현황

- **저장소:** 모노레포 단일 repo, `main` 브랜치. 최신 커밋 `5d1435f` — 문서 일괄 최신화
- **백엔드:** `backend-cloudflare/` — Cloudflare Workers 배포 완료
- **배포 URL:** `https://matgyeomung-api.dog-kindergarden.workers.dev`
