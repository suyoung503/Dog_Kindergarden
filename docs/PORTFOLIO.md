# 맡겨멍 — 포트폴리오 기술 문서

## 프로젝트 개요

반려견을 맡길 수 있는 애견 유치원·호텔을 지도 기반으로 탐색하고 예약할 수 있는 iOS 플랫폼.  
공공데이터 동물위탁관리업 API로 전국 업체를 실데이터로 표시하고, 보호자 리뷰·채팅·예약 기능을 통합 제공한다.

**기간:** 2026년 6월 ~  
**역할:** iOS 개발 (Swift/SwiftUI) + Cloudflare Workers 백엔드  
**스택:** Swift 5.9, SwiftUI, Observation, KakaoMapsSDK, TypeScript, Hono, Cloudflare Workers, D1

---

## 기술적 도전과 해결

### 1. 공공데이터 좌표계 변환

**문제**  
data.go.kr 동물위탁관리업 API가 반환하는 좌표가 WGS84(GPS)가 아닌 EPSG:5181(중부원점 TM) 좌표계라 카카오 지도에 그대로 꽂으면 핀이 엉뚱한 곳에 찍혔다.

**고민**  
외부 라이브러리를 쓰면 간단하지만, iOS 앱에 좌표 변환 라이브러리를 CocoaPods로 추가하면 의존성이 늘어난다. 변환 공식 자체는 수학 연산이라 직접 구현이 가능한 수준이었다.

**해결**  
GRS80 타원체 기반 TM→WGS84 역변환을 `TMConverter` enum으로 직접 구현했다. 변환 후 대한민국 영역(위도 33~39, 경도 124~132)을 벗어나는 좌표는 필터링해 잘못된 핀을 차단했다.

```swift
let coord = TMConverter.toWGS84(x: x, y: y)
guard coord.lat > 33, coord.lat < 39, coord.lon > 124, coord.lon < 132 else { return nil }
```

**이 방법을 선택한 이유**  
외부 의존성 없이 단일 파일(AnimalBoardingService.swift)에서 처리 가능하고, 변환 공식이 국제 표준이라 정확도가 보장된다. CocoaPods 라이브러리 추가 대비 앱 용량도 줄어든다.

---

### 2. API 키 보안 — xcconfig 분리

**문제**  
`Info.plist`에 공공데이터·카카오·네이버 API 키가 실제 값으로 하드코딩되어 git에 커밋되어 있었다. GitHub에 올리면 누구나 키를 볼 수 있어 무단 사용 또는 쿼터 소진 위험이 있었다.

**고민**  
대안으로 `.env` 파일, 별도 plist, 빌드 스크립트 등이 있었다. iOS에서는 런타임에 환경변수를 읽을 수 없어서 `.env` 방식은 불가능했다.

**해결**  
Xcode의 **xcconfig(Configuration Settings File)** 방식을 채택했다.

- `Secret.xcconfig`에 실제 키값 보관 → `.gitignore`로 git 제외
- `Info.plist`에는 변수 참조만 남김: `$(DATA_GO_KR_SERVICE_KEY)`
- 빌드 시 Xcode가 xcconfig를 읽어 값을 자동 주입

```
// Secret.xcconfig (git 제외)
DATA_GO_KR_SERVICE_KEY = 실제키값

// Info.plist (git 포함)
<key>DATA_GO_KR_SERVICE_KEY</key>
<string>$(DATA_GO_KR_SERVICE_KEY)</string>
```

**이 방법을 선택한 이유**  
Xcode 네이티브 방식이라 추가 코드 없이 기존 `Bundle.main.object(forInfoDictionaryKey:)` 호출을 그대로 유지할 수 있다. Debug/Release 환경별로 다른 키를 주입하는 것도 가능하다.

| 방법 | 장점 | 단점 |
|---|---|---|
| **xcconfig (채택)** | Xcode 네이티브, 추가 코드 없음 | xcconfig 문법 학습 필요 |
| 환경변수 | 간단 | iOS 런타임에서 환경변수 접근 불가 |
| 별도 plist 파일 | 직관적 | 결국 파일 자체를 gitignore 해야 해 xcconfig와 동일 |
| 키를 그냥 커밋 | 편함 | 보안 사고 위험, 키 재발급 필요 |

---

### 3. Pods git 추적 문제

**문제**  
`.gitignore`가 없어서 CocoaPods의 `Pods/` 디렉토리(279개 파일)가 git에 추적되고 있었다.

**고민**  
이미 git이 추적 중인 파일은 `.gitignore`를 추가해도 자동으로 무시되지 않는다는 점을 인지해야 했다.

**해결**  
`.gitignore` 생성 후 `git rm -r --cached Pods/`로 추적 목록에서만 제거했다. 실제 파일은 삭제되지 않고 git이 더 이상 관리하지 않는다.

**이 방법을 선택한 이유**  
iOS 생태계 표준 관례다. `Podfile.lock`만 커밋하면 누구든 `pod install` 한 번으로 동일한 버전을 재현할 수 있다.

---

### 4. 하드코딩 사용자 정보 제거 — UserProfile 모델

**문제**  
`BookingView`의 보호자 이름·연락처·주소, `HomeView`의 인사말이 문자열로 박혀 있었다.

```swift
formField(label: "이름", value: "김상민")   // 하드코딩
Text("상민님")                               // 하드코딩
```

**고민**  
Core Data나 Keychain을 쓰면 과하다. 간단한 사용자 설정값이라 UserDefaults로 충분하다고 판단했다.

**해결**  
`@Observable` 기반 `UserProfile` 모델을 만들어 `UserDefaults`에 영속 저장하고 `RootView`에서 환경 객체로 주입했다.

```swift
@Observable
final class UserProfile {
    var name: String {
        didSet { UserDefaults.standard.set(name, forKey: "profile_name") }
    }
    // ...
}
```

뷰에서는 `@Environment(UserProfile.self)`로 읽어 사용한다.

**이 방법을 선택한 이유**  
Swift Observation 프레임워크를 사용해 `@Observable`로 선언하면 변경 시 관련 뷰가 자동으로 업데이트된다. `didSet`으로 UserDefaults에 즉시 저장해 앱 재시작 후에도 값이 유지된다.

---

### 5. TypeScript any 타입 제거

**문제**  
Cloudflare Workers 백엔드의 모든 요청 바디가 `any` 타입으로 처리되고 있어 TypeScript를 쓰는 의미가 없었다.

**해결**  
라우트별 요청 바디 타입을 명시적으로 정의했다.

```typescript
type ReservationBody = {
  user_id?: number; userId?: number
  start_date?: string; startDate?: string
  // ...
}

const body = await c.req.json<ReservationBody>()  // any → 명시적 타입
```

**이 방법을 선택한 이유**  
iOS 클라이언트에서 snake_case와 camelCase를 혼용해 보내는 구조가 이미 있었기 때문에 두 형태 모두 optional로 받는 타입을 정의했다. 잘못된 구조의 요청이 들어오면 개발 중에 타입 오류로 바로 잡을 수 있다.

---

### 6. 예약과 채팅방의 도메인 설계 — 공공 가게의 ID 부재 문제

**문제**  
예약(`reservations`)은 `store_id`가 필수인데, 지도의 가게는 공공데이터 API에서 오기 때문에 우리 DB에 `store_id`가 없다(이름·주소만 존재). 또 예약할 때마다 채팅방을 새로 만들면, 같은 가게에 두 번 예약한 사용자가 서로 다른 방을 갖게 되어 대화가 흩어진다.

**고민**  
- **가게 식별**: (A) 예약마다 임시 번호 부여 — 같은 가게를 못 묶음. (B) 이름만 저장 — 구조적 식별 불가. (C) 공공 가게를 우리 `stores`에 등록해 안정적 번호 부여.
- **채팅방 범위**: 방을 '예약'에 묶을지, '가게'에 묶을지, '(사용자+가게)'에 묶을지. 다중 사용자를 고려하면 (사용자+가게)라야 남의 대화가 섞이지 않는다.

**해결**  
- 리뷰 기능에서 이미 쓰던 `store_key`("이름\|주소") 방식을 재사용. 예약 시 `store_key`로 `stores`를 조회해 **있으면 재사용, 없으면 등록(자동 증가 번호)** → 같은 가게는 항상 같은 `store_id`.
- 채팅방은 `chat_rooms(user_id, store_id UNIQUE)` 테이블로 **(사용자+가게) 조합당 1개**. 예약 시 해당 방을 조회/생성하고 그 방에 '예약 요청 완료' 메시지를 남긴다.
- API가 `{reservation_id, room_id}`를 함께 반환해 클라이언트가 이후 채팅방으로 바로 연결할 수 있게 했다.

```typescript
// 같은 가게는 같은 번호, 같은 (유저·가게)는 같은 방
const storeId = existing ? existing.store_id : (await insertStore(...)).id
const roomId  = room     ? room.room_id     : (await insertRoom(userId, storeId)).id
```

**이 방법을 선택한 이유**  
공공 API 데이터를 우리 도메인으로 끌어올 때 흔한 "외부 식별자 ↔ 내부 식별자" 매핑 문제다. `store_key` upsert로 외부 데이터를 자연스럽게 내부 엔티티로 승격시키고, 리뷰와 동일한 키를 써서 일관성을 유지했다. (사용자+가게) 방 설계는 카카오톡 채널 방식과 동일해 사용자에게 직관적이다.

---

## 아키텍처 결정

### iOS — SwiftUI + Observation

UIKit 대신 SwiftUI를 선택한 이유:
- `@Observable` 매크로로 보일러플레이트 없이 상태 관리 가능
- 선언형 UI로 지도·리뷰·예약 화면을 빠르게 구현
- iOS 17+ 기준 Observation이 `@StateObject`/`@ObservedObject` 대비 성능이 뛰어남

### 백엔드 — Cloudflare Workers + D1

Spring Boot 대신 Cloudflare Workers를 선택한 이유:
- 서버 관리 불필요, 글로벌 엣지 배포 자동화
- D1(SQLite)으로 마이그레이션 파일 기반 스키마 관리 가능
- 포트폴리오 배포 비용 무료

### 지도 데이터 — 공공데이터 API

카카오·네이버 플레이스 대신 공공데이터 동물위탁관리업 API를 선택한 이유:
- 정부가 인허가한 업체만 등록되어 있어 신뢰도 높음
- 전국 데이터를 한 번에 가져올 수 있어 초기 로딩 후 필터링이 용이
- 카카오 로컬 API로 마스킹된 주소를 보강하는 이중 구조로 정확도 향상

---

## UI/UX 설계 고민

디자인 시안을 기능으로 옮기며 "정보를 어떻게 배치하고, 사용자의 마찰을 어떻게 줄일까"를 계속 고민했다.

### 강아지 카드 — 정보 밀도 조절

한 줄에 `이름 / 나이 / 성별 / 견종`을 슬래시로 나열하니 답답했다. **이름을 카드의 주인공으로 키우고**, 나이는 이름 옆에, 성별·견종은 아랫줄로 분리해 시선이 자연스럽게 흐르도록 했다. 사회성·알레르기·특이사항 같은 세부 정보는 목록에서 빼고, **카드를 탭하면 열리는 상세 시트**에서 항목별 칸으로 보여줬다 — 목록은 가볍게, 상세는 충분하게.

```
[🐶]  몽이 3살          ← 이름(강조) + 나이
      남 · 포메라니안    ← 성별 · 견종
```

### 한 카드 안의 두 동작 — 탭 영역 분리

강아지 카드에는 '상세 열기'와 '삭제(−)' 두 동작이 공존한다. 카드 본문은 `contentShape(Rectangle())`로 탭 영역을 명확히 잡아 상세 시트를 열고, 삭제 버튼은 그 바깥의 독립 버튼으로 두어 오작동(삭제하려다 상세가 열리는 등)을 막았다.

### 지도 — '전국보기'를 없애고 '보이는 만큼만'

기존엔 도(道) 단위로 전환하는 '전국보기' 모드가 있었는데, 사용자가 도 경계를 신경 써야 해서 부자연스러웠다. 지도를 움직이면(`cameraDidStopped`) **현재 화면의 위경도 범위를 계산해 그 안의 가게만** 도 경계와 무관하게 표시하도록 바꿨다. 핀이 과밀해지는 걸 막으려 화면 중심에서 가까운 순으로 개수 상한을 뒀다.

### 예약 화면 — 실제 데이터와의 마찰 줄이기

- **강아지 선택**을 실제 등록 데이터로 연결해, 고르면 나이·견종·몸무게·메모가 함께 갱신된다.
- **보호자 연락처·주소**는 한 번 입력하면 `UserDefaults`에 영구 저장되고, 다음 예약부터 '자동 불러오기'로 재사용한다. 매번 다시 적는 마찰을 없앴다.
- **서비스를 고르면 총 결제금액이 즉시 다시 계산**된다(가격 문자열 파싱 + 픽업 고정액 합산). 완료화면의 '결제 예정'도 같은 값으로 통일했다.

### 로딩·빈 상태·실패를 눈에 보이게

목록이 비면 안내 문구, 통신 중엔 스피너 + 버튼 비활성, 실패 시 빨간 문구로 상태를 드러냈다. 사용자가 '지금 무슨 일이 일어나는지' 알 수 있게 하는 데 신경 썼다.

### 향후 UI 개선 아이디어

- 강아지 아바타에 실제 사진 업로드(현재는 기본 이미지 순환)
- 예약 날짜를 텍스트 목록 대신 캘린더 피커로, 호텔은 체크인/아웃 기간 선택
- '장기 이용'처럼 범위 가격(₩40,000~)의 명확한 표기·계산 규칙
- 지도 핀 클러스터링(밀집 지역 묶기)
- 채팅 실시간화(WebSocket) 및 읽음 표시

---

## 향후 개선 계획

- 채팅 실시간 연동 (`ChatRoomView` 실메시지 + 예약 후 채팅방 직행)
- MyPage 프로필 편집 UI 연결
- 네이버 블로그 API 키 발급 및 연동
- 푸시 알림 (FCM)
- 업체 측 앱 (알림장 작성, 예약 승인)
