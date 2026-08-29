# 1:1 문의 설계 — 고정 "고객센터" 가상 가게 재사용 (2026-08-29)

## 배경과 목적

마이페이지 "고객지원" 섹션의 "1:1 문의" 버튼은 현재 `action` 없이 눌러도 아무 반응이 없는 죽은 버튼이다. 이를 살려 사용자가 앱 개발자(운영자)에게 직접 문의를 보낼 수 있게 한다. 목적 범위는 **실사용 대비**(포트폴리오 데모 전용이 아니라, 실제 사용자가 보낼 수 있는 문의를 개발자 본인이 받아 답장하는 용도)다.

## 핵심 결정 — 신규 스키마 없이 기존 가게/채팅 패턴 재사용

CLAUDE.md의 "이 패턴을 깨는 변경(예약마다 방 생성, 이름만으로 가게 식별 등)은 하지 않는다" 원칙에 따라, "개발자 계정"을 완전히 새로운 역할/스키마로 만들지 않는다. 대신:

- **"고객센터"를 가상의 가게 1개로 취급**한다. `stores` 테이블에 실제 공공데이터 가게와 동일한 형태의 행 하나(`store_key`, `name`, `owner_id`)로 존재한다.
- 이 가상 가게의 `owner_id`를 개발자 본인의 실제 카카오 로그인 계정으로 지정하면, 기존 "받은 문의"(`GET /api/owners/:id/chatrooms`, `ChatListView`) 메커니즘이 그대로 이 가게로 온 문의를 보여준다.
- 사용자가 1:1 문의를 누르면 이 고정 `store_key`로 기존 `POST /api/chatrooms`(get-or-create) 흐름을 타고, 결국 "사용자 ↔ 개발자 본인 계정" 채팅방이 생성된다.

**백엔드 코드 변경은 0줄이다.** 기존 `resolveStoreId`(store_key upsert) · `POST /api/chatrooms` · `GET /api/chatrooms/lookup` · `GET /api/owners/:id/chatrooms` · `POST /api/stores/claim`을 그대로 재사용한다.

### 검토했던 대안 — 별도 관리자 플래그 신설

`users.is_admin` 같은 신규 컬럼 + owner_id/받은문의 패턴과 분리된 전용 "관리자 문의함" 화면·엔드포인트. 사장님 UI(사장님 메뉴, 받은 예약 요청 등)가 섞이지 않는 장점이 있지만, 마이그레이션 1개 + 백엔드 라우트 1~2개 + iOS 신규 화면 1개가 추가로 필요하다. 지금 백엔드가 무인증 데모 범위이고(`docs/FEATURES.md` §13), 문의함 하나만 필요한 현재 요구사항 대비 과한 설계라 채택하지 않는다. (사용자 확정: 접근법 A로 진행)

### 알려진 트레이드오프

개발자 본인 계정이 `AuthSession.isOwner = true`가 되므로, 사장님 전용 UI(홈 사이드바 "사장님 메뉴", "받은 예약 요청", "확정예약·알림장" 등)도 함께 보인다. 이 가상 가게에는 실제 예약이 없으므로 해당 화면들은 빈 상태로 보일 뿐 기능적 문제는 없다.

## 데이터 모델 / 프로비저닝

- 고정 `store_key`: `"맡겨멍 고객센터|고객센터"` — 실제 상호명과 절대 겹치지 않는 고유 문자열. iOS 코드에 상수로 둔다.
- 사용자가 처음 문의를 보내기 전까지는 이 `store_key`에 대응하는 `stores` 행이 아직 없다. 첫 문의 전송 시 `POST /api/chatrooms` → `resolveStoreId`가 upsert로 새로 만든다(이 시점엔 `owner_id`가 비어있음).
- **1회성 프로비저닝**(앱 UI가 아니라 배포 후 개발자가 직접 실행):
  1. 개발자 본인의 실제 카카오 계정으로 **사장님(owner) 역할**로 앱에 회원가입한다 — `AuthSession.isOwner`가 true여야 "받은 문의" 섹션 자체가 렌더링되기 때문이다.
  2. 로그인 후 `AuthSession.userId` 값을 확인한다.
  3. 아래 curl을 1회 호출해 이 계정을 가상 가게의 `owner_id`로 지정한다:
     ```bash
     curl -X POST https://matgyeomung-api.dog-kindergarden.workers.dev/api/stores/claim \
       -H "Content-Type: application/json" \
       -d '{"user_id": <내 userId>, "store_key": "맡겨멍 고객센터|고객센터", "store_name": "맡겨멍 고객센터"}'
     ```
  - `MyStoreSheet`("내 가게" 등록 UI)는 공공데이터 목록(`boarding.pins`)에서만 상호명을 검색하므로, 공공데이터에 없는 "고객센터"는 그 화면으로는 등록할 수 없다 — 그래서 curl 직접 호출이 필요하다.
  - 문의가 아직 없어 `stores` 행 자체가 없는 상태에서 먼저 claim을 호출해도, `resolveStoreId`가 upsert로 새로 만들고 바로 `owner_id`를 지정하므로 순서는 상관없다(사용자의 첫 문의보다 먼저 실행해도 무방).

## iOS 구현

`Dog_kindergarden/Dog_kindergarden/Views/StoreDetail/StoreDetailView.swift`의 기존 "문의하기"(`openChat()`) 패턴을 그대로 따른다 — 기존 방이 있으면 그 방으로 진입(과거 대화 내역 표시), 없으면 작성 모드로 진입.

`Dog_kindergarden/Dog_kindergarden/Views/MyPage/MyPageView.swift`의 `supportSection`:

```swift
// 변경 전
MyPageItem(icon: "bubble.left", label: "1:1 문의")

// 변경 후
MyPageItem(icon: "bubble.left", label: "1:1 문의") { openSupportChat() }
```

같은 파일에 메서드 추가:

```swift
// 1:1 문의 — "고객센터"를 고정 store_key를 가진 가상 가게로 취급해 기존 채팅 인프라 재사용.
// 기존 방 있으면 그 방으로, 없으면 작성 모드로 진입 (StoreDetailView.openChat()과 동일 패턴)
private func openSupportChat() {
    let key = "맡겨멍 고객센터|고객센터"
    Task {
        guard let uid = authSession.userId else { return }
        let rid = await ChatService.lookup(userId: uid, storeKey: key)
        router.selectedPin = MapPin(
            name: "맡겨멍 고객센터", type: "고객센터", rating: 0, distance: "",
            latitude: 0, longitude: 0, province: "",
            storeKeyOverride: key
        )
        router.selectedChat = "맡겨멍 고객센터"
        router.selectedRoomId = rid
        router.chatRoomAsOwner = false
        router.chatRoomAvatar = "🎧"
        router.go(.chatRoom)
    }
}
```

- `router.selectedPin`은 위경도가 없는 `MapPin`이지만, `ChatRoomView`는 좌표를 전혀 참조하지 않으므로(채팅 메시지 송수신에만 `storeKey`/`storeAddress` 사용) 문제없다.
- `MapPin.storeKeyOverride`를 지정했으므로 `storeKey` 계산 프로퍼티가 이름+주소 조합이 아니라 이 고정 키를 그대로 반환한다.
- `MyPageView`는 이미 `@Environment(AppRouter.self) private var router`, `@Environment(AuthSession.self) private var authSession`를 갖고 있어 추가 주입이 필요 없다.

## 동작 흐름

1. 사용자가 "1:1 문의" 탭 → `openSupportChat()` → `ChatRoomView` 진입. 기존 대화가 있으면 즉시 로드, 없으면 빈 화면(작성 모드).
2. 첫 메시지 전송 시 `ChatRoomViewModel.send()`가 `ChatService.openRoom(storeKey: "맡겨멍 고객센터|고객센터", ...)` → 방 생성(또는 프로비저닝 때 이미 만들어진 가게 재사용) → 메시지 전송.
3. 개발자가 본인 계정(사장님 역할)으로 로그인 → `ChatListView`의 "받은 문의"에서 확인·답장 — 일반 사장님이 손님 문의에 답하는 것과 완전히 동일한 화면/로직.
4. 안 읽은 문의 배지(홈 종 아이콘)도 기존 "사장님 몫 합산" 로직(`GET /api/users/:id/unread-count`)에 자동 포함 — 별도 처리 불필요.

## 에러 처리

기존 `openChat()`/`ChatRoomView`의 에러 처리를 그대로 재사용하므로 추가로 다룰 엣지 케이스가 없다:

- 로그인 안 된 상태: `guard let uid = authSession.userId else { return }`로 조용히 무시(이 진입점은 로그인 후에만 접근 가능한 마이페이지 내부라 사실상 발생하지 않음).
- 메시지 전송 실패: 기존 `ChatRoomViewModel.send()`의 에러 문구 표시 + 낙관적 추가분 롤백 로직 그대로 적용.

## 테스트 방법

- 실기기/시뮬레이터 UI 자동화가 불안정했던 이전 이력이 있으므로, 빌드 성공 확인 후 시뮬레이터에서 수동으로 "마이페이지 → 1:1 문의" 탭해 빈 채팅방(작성 모드) 진입을 스크린샷으로 확인한다.
- 실제 문의 왕복(사용자 계정 → 개발자 계정 "받은 문의" → 답장 → 사용자 계정에 반영)은 두 계정(예: `dev-simulator` 견주 계정 + 프로비저닝된 실 카카오 사장님 계정)을 오가며 확인이 필요해 자동화 범위 밖이다 — 이 부분은 구현 후 수동 확인 결과를 있는 그대로 보고한다(자동 검증 불가 시 그렇다고 명시).
