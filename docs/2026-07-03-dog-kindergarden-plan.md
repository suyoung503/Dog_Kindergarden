# Dog_Kindergarden (맡겨멍) 배포 준비 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 배포 레디니스 리포트의 경고 항목을 모두 해소하고, 하드코딩된 목업 데이터를 제거하여 실제 배포 가능한 상태로 만든다.

---

## 현재 진행 상태 (2026-07-03)

| Task | 상태 |
|---|---|
| Task 1: .gitignore + Pods 정리 | ✅ 완료 |
| Task 2: API 키 xcconfig 분리 | ✅ 완료 |
| Task 3: 백엔드 .gitignore + TypeScript 타입 | ✅ 완료 |
| Task 4: 하드코딩 사용자 정보 → UserProfile | ✅ 완료 |
| Task 5: 네이버 블로그 API 키 발급 | ⏳ 진행 전 |
| Task 6: 미커밋 변경사항 정리 | ✅ 완료 |
| Task 7: README 작성 | ⏳ 진행 전 |

### 다음 진행 순서

**Step 1** → Task 5: 네이버 블로그 API 키 발급 (10분, 수동)  
**Step 2** → Task 7: README 작성 (20분, 코드 작업)

---

**Architecture:**
- iOS: Swift 5.9 / SwiftUI + UIKit 혼용, CocoaPods (KakaoMapsSDK)
- Backend: Cloudflare Workers (TypeScript + Hono) + D1 (SQLite)
- 두 레포는 `Dog_kindergarden/` (iOS) 과 `backend-cloudflare/` (Workers) 로 분리

**Tech Stack:** Swift 5.9, SwiftUI, Observation, CocoaPods, Hono 4, TypeScript 5 strict, Cloudflare D1, wrangler

## Global Constraints

- iOS 최소 배포 타깃: Xcode 프로젝트에 설정된 버전 유지 (변경 금지)
- 백엔드 wrangler.toml 의 `name`·`database_id`·`workers.dev` URL 변경 금지
- `Info.plist` 의 `LSApplicationQueriesSchemes` 항목 변경 금지
- 실제 API 키·시크릿은 절대 소스 코드(`.swift`, `.ts`)에 직접 작성 금지

---

## 파일 구조 (변경 대상)

```
Dog_Kindergarden/
├── Dog_kindergarden/
│   ├── Dog_kindergarden/
│   │   ├── Info.plist                          ← Task 2: 키 xcconfig 이동
│   │   ├── Config/                             ← Task 2: 신규 생성
│   │   │   ├── Secret.xcconfig                 ← Task 2: 신규 (gitignore)
│   │   │   └── Secret.xcconfig.example         ← Task 2: 신규
│   │   ├── Views/
│   │   │   ├── Home/HomeView.swift             ← Task 4: 하드코딩 제거
│   │   │   └── Booking/BookingView.swift       ← Task 4: 하드코딩 제거
│   │   └── Models/                             ← Task 4: 신규
│   │       └── UserProfile.swift               ← Task 4: 신규
│   └── .gitignore                              ← Task 1: 신규
├── backend-cloudflare/
│   ├── .gitignore                              ← Task 3: 신규
│   └── src/index.ts                            ← Task 3: any 타입 제거
├── _png_원본/                                   ← Task 1: 삭제
└── README.md                                   ← Task 5: 신규
```

---

## Task 1: 불필요 파일 삭제 + iOS .gitignore 설정

**Files:**
- Delete: `Dog_Kindergarden/_png_원본/` (Xcode Assets에 이미 포함된 원본 PNG)
- Create: `Dog_kindergarden/.gitignore`

- [x] **Step 1: _png_원본 디렉토리 삭제**

  Assets.xcassets에 이미 편집된 이미지가 들어있으므로 원본 폴더는 불필요합니다.

  ```bash
  rm -rf /Users/suyoung/Documents/Dog_Kindergarden/_png_원본
  ```

- [x] **Step 2: iOS .gitignore 작성**

  `Dog_kindergarden/.gitignore`:

  ```gitignore
  # Xcode 빌드 산출물
  build/
  DerivedData/
  *.o
  *.hmap
  *.ipa

  # CocoaPods (Podfile.lock만 커밋, Pods 디렉토리는 제외)
  Pods/

  # Xcode 사용자 설정
  xcuserdata/
  *.xcscmblueprint
  *.xccheckout

  # macOS
  .DS_Store

  # Swift Package Manager
  .build/
  .swiftpm/

  # xcconfig 시크릿 (키 보관 파일)
  Config/Secret.xcconfig
  ```

- [x] **Step 3: Pods git 추적 제거**

  ```bash
  cd /Users/suyoung/Documents/Dog_Kindergarden/Dog_kindergarden
  git rm -r --cached Pods/
  ```
  Expected: Pods/ 하위 279개 파일 unstage 메시지 출력

- [x] **Step 4: xcuserdata 추적 제거**

  ```bash
  git rm -r --cached Dog_kindergarden/Dog_kindergarden.xcodeproj/xcuserdata/ 2>/dev/null || true
  git rm -r --cached Dog_kindergarden/Dog_kindergarden.xcodeproj/project.xcworkspace/xcuserdata/ 2>/dev/null || true
  ```

- [x] **Step 5: Commit**

  ```bash
  cd /Users/suyoung/Documents/Dog_Kindergarden/Dog_kindergarden
  git add .gitignore
  git commit -m "chore: .gitignore 추가 및 Pods git 추적 제거"
  ```

---

## Task 2: Info.plist API 키 xcconfig 분리 (iOS 보안)

**왜 필요한가:** `Info.plist`의 `DATA_GO_KR_SERVICE_KEY`, `KAKAO_NATIVE_APP_KEY`, `KAKAO_REST_API_KEY`가 git에 커밋되어 있으면 키가 공개됩니다. xcconfig 파일로 분리하고 Secret.xcconfig는 .gitignore에 추가합니다.

**Files:**
- Create: `Dog_kindergarden/Dog_kindergarden/Config/Secret.xcconfig`
- Create: `Dog_kindergarden/Dog_kindergarden/Config/Secret.xcconfig.example`
- Modify: `Dog_kindergarden/Dog_kindergarden/Info.plist` (키 값 → 변수 참조로 변경)
- Modify: `Dog_kindergarden/Dog_kindergarden.xcodeproj/project.pbxproj` (xcconfig 연결)

- [x] **Step 1: Config 디렉토리 + xcconfig.example 작성**

  ```bash
  mkdir -p /Users/suyoung/Documents/Dog_Kindergarden/Dog_kindergarden/Dog_kindergarden/Config
  ```

  `Dog_kindergarden/Dog_kindergarden/Config/Secret.xcconfig.example`:
  ```
  // 이 파일을 복사해 Secret.xcconfig 로 이름 변경 후 실제 키를 입력하세요.
  // Secret.xcconfig 는 절대 git에 커밋하지 마세요.

  DATA_GO_KR_SERVICE_KEY = 여기에_공공데이터_서비스키
  KAKAO_NATIVE_APP_KEY = 여기에_카카오_네이티브앱키
  KAKAO_REST_API_KEY = 여기에_카카오_REST_API키
  NAVER_CLIENT_ID = 여기에_네이버_클라이언트ID
  NAVER_CLIENT_SECRET = 여기에_네이버_클라이언트시크릿
  ```

- [x] **Step 2: Secret.xcconfig 생성 (실제 키 입력, git 제외)**

  `Secret.xcconfig.example`을 복사해서 `Secret.xcconfig` 만들기:
  ```bash
  cp /Users/suyoung/Documents/Dog_Kindergarden/Dog_kindergarden/Dog_kindergarden/Config/Secret.xcconfig.example \
     /Users/suyoung/Documents/Dog_Kindergarden/Dog_kindergarden/Dog_kindergarden/Config/Secret.xcconfig
  ```
  그 다음 `Secret.xcconfig`를 텍스트 에디터로 열어 실제 키 값 입력.

- [x] **Step 3: Xcode에서 xcconfig 연결**

  Xcode에서:
  1. `Dog_kindergarden` 프로젝트 파일 클릭 → PROJECT → `Dog_kindergarden` 선택
  2. `Info` 탭 → Configurations 섹션
  3. `Debug` 행 옆 화살표 클릭 → `Dog_kindergarden` target 열 → `Secret` 선택
  4. `Release` 도 동일하게 설정

  또는 `project.pbxproj` 직접 수정: `baseConfigurationReference` 에 Secret.xcconfig 경로 추가 (Xcode GUI 권장)

- [x] **Step 4: Info.plist 키 값을 변수 참조로 변경**

  `Info.plist`에서 각 키 값을 xcconfig 변수 참조로 교체:

  현재:
  ```xml
  <key>DATA_GO_KR_SERVICE_KEY</key>
  <string>adffe32c8a5500a8d5b6c7de7bffe73134c5c8c54adf9b364f0b35b7656aeb86</string>
  <key>KAKAO_NATIVE_APP_KEY</key>
  <string>cfa538b943c5d65c219f1710ebf69b21</string>
  <key>KAKAO_REST_API_KEY</key>
  <string>6950952748b344f44f5d507838c5d13a</string>
  <key>NAVER_CLIENT_ID</key>
  <string>[NAVER_CLIENT_ID]</string>
  <key>NAVER_CLIENT_SECRET</key>
  <string>[NAVER_CLIENT_SECRET]</string>
  ```

  변경 후:
  ```xml
  <key>DATA_GO_KR_SERVICE_KEY</key>
  <string>$(DATA_GO_KR_SERVICE_KEY)</string>
  <key>KAKAO_NATIVE_APP_KEY</key>
  <string>$(KAKAO_NATIVE_APP_KEY)</string>
  <key>KAKAO_REST_API_KEY</key>
  <string>$(KAKAO_REST_API_KEY)</string>
  <key>NAVER_CLIENT_ID</key>
  <string>$(NAVER_CLIENT_ID)</string>
  <key>NAVER_CLIENT_SECRET</key>
  <string>$(NAVER_CLIENT_SECRET)</string>
  ```

- [x] **Step 5: 빌드 확인**

  Xcode에서 `Cmd+B` (Build)
  Expected: Build Succeeded (키가 xcconfig에서 주입됨)

  앱 실행 후 HomeView에서 지도 핀이 로드되는지 확인.
  Expected: 공공데이터 API 호출 성공 → 지도에 핀 표시

- [x] **Step 6: 기존 커밋된 키 정리 (중요)**

  키가 이미 git history에 있으면 history rewrite가 필요하지만, 포트폴리오용이라면 키 재발급으로 대체 가능합니다:
  - data.go.kr: 기존 서비스키 재발급
  - 카카오: 앱 설정 → 번들 ID 제한 설정으로 오남용 차단
  - 네이버: 애플리케이션 등록 후 새 키 발급

- [x] **Step 7: Commit**

  ```bash
  cd /Users/suyoung/Documents/Dog_Kindergarden/Dog_kindergarden
  git add Dog_kindergarden/Config/Secret.xcconfig.example Dog_kindergarden/Info.plist
  git commit -m "security: API 키를 Info.plist 에서 xcconfig로 분리"
  ```

---

## Task 3: 백엔드 .gitignore + TypeScript 타입 개선

**Files:**
- Create: `backend-cloudflare/.gitignore`
- Modify: `backend-cloudflare/src/index.ts` (`any` → 구체적 타입)

- [x] **Step 1: backend .gitignore 작성**

  `backend-cloudflare/.gitignore`:
  ```gitignore
  node_modules/
  .wrangler/
  dist/
  .env
  *.local
  ```

- [x] **Step 2: .wrangler 디렉토리 git 추적 제거**

  ```bash
  cd /Users/suyoung/Documents/Dog_Kindergarden/backend-cloudflare
  git rm -r --cached .wrangler/ 2>/dev/null || true
  git rm -r --cached node_modules/ 2>/dev/null || true
  ```

- [x] **Step 3: index.ts — 요청 바디 타입 정의 추가**

  `backend-cloudflare/src/index.ts` 상단 (`import` 다음 줄)에 타입 추가:

  ```typescript
  type ReservationBody = {
    user_id?: number; userId?: number
    pet_id?: number; petId?: number
    store_id?: number; storeId?: number
    start_date?: string; startDate?: string
    end_date?: string; endDate?: string
    reservation_type?: string; reservationType?: string
    request_message?: string; requestMessage?: string
  }

  type ReviewBody = {
    reservation_id?: number; reservationId?: number
    user_id?: number; userId?: number
    store_id?: number; storeId?: number
    rating?: number
    revisit?: boolean
    content?: string
  }

  type PetReviewBody = {
    store_key?: string; storeKey?: string
    store_name?: string; storeName?: string
    user_name?: string; userName?: string
    rating?: number
    revisit?: boolean
    cctv?: boolean
    pickup?: boolean
    large_dog?: boolean
    separation_care?: boolean
    content?: string
  }

  type ChatMessageBody = {
    sender_id?: number; senderId?: number
    sender_name?: string; senderName?: string
    message_type?: string; messageType?: string
    content?: string
  }
  ```

- [x] **Step 4: index.ts — `any` 타입 교체**

  각 라우트의 `c.req.json<any>()` 를 구체적 타입으로 교체:

  ```typescript
  // POST /api/reservations
  const body = await c.req.json<ReservationBody>()

  // POST /api/reviews
  const body = await c.req.json<ReviewBody>()

  // POST /api/pet-reviews
  const body = await c.req.json<PetReviewBody>()

  // POST /api/chatrooms/:id/messages
  const body = await c.req.json<ChatMessageBody>()
  ```

- [x] **Step 5: 타입 체크 통과 확인**

  ```bash
  cd /Users/suyoung/Documents/Dog_Kindergarden/backend-cloudflare
  npx tsc --noEmit
  ```
  Expected: 오류 없음

- [x] **Step 6: Commit**

  ```bash
  git add .gitignore src/index.ts
  git commit -m "chore: .gitignore 추가 및 TypeScript any 타입 제거"
  ```

---

## Task 4: 하드코딩 목업 데이터 제거 (iOS)

**배경:** `HomeView.swift:81`의 "상민님", `BookingView.swift`의 "김상민"·"010-1234-5678" 등이 하드코딩되어 있음. `UserProfile` 모델을 만들어 UserDefaults에 저장하고, 각 뷰에서 불러온다.

**Files:**
- Create: `Dog_kindergarden/Dog_kindergarden/Models/UserProfile.swift`
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/Home/HomeView.swift`
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/Booking/BookingView.swift`
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/Navigation/AppRouter.swift`

- [x] **Step 1: UserProfile.swift 작성**

  `Dog_kindergarden/Dog_kindergarden/Models/UserProfile.swift`:

  ```swift
  import Foundation
  import Observation

  @Observable
  final class UserProfile {
      var name: String {
          didSet { UserDefaults.standard.set(name, forKey: "profile_name") }
      }
      var phone: String {
          didSet { UserDefaults.standard.set(phone, forKey: "profile_phone") }
      }
      var address: String {
          didSet { UserDefaults.standard.set(address, forKey: "profile_address") }
      }

      init() {
          name    = UserDefaults.standard.string(forKey: "profile_name")    ?? "보호자"
          phone   = UserDefaults.standard.string(forKey: "profile_phone")   ?? ""
          address = UserDefaults.standard.string(forKey: "profile_address") ?? ""
      }
  }
  ```

- [x] **Step 2: RootView 또는 SceneDelegate에서 UserProfile 환경 주입**

  `RootView.swift` 또는 앱 진입점에서 `UserProfile`을 `@State`로 만들고 `.environment()`로 주입:

  현재 `RootView.swift`에서 `BoardingStore`, `TagStore` 주입하는 방식과 동일하게:
  ```swift
  // RootView.swift 또는 SceneDelegate 에서
  @State private var userProfile = UserProfile()

  // body 안에서
  ContentView()
      .environment(userProfile)
      // 기존 .environment(boarding) 등과 같이
  ```

- [x] **Step 3: HomeView.swift — "상민님" 하드코딩 제거**

  `HomeView.swift`에 `@Environment(UserProfile.self)` 추가 후 교체:

  현재 (`HomeView.swift:8` 근처에 추가):
  ```swift
  @Environment(UserProfile.self) private var userProfile
  ```

  현재 (`HomeView.swift:81`):
  ```swift
  Text("상민님")
  ```
  변경:
  ```swift
  Text("\(userProfile.name)님")
  ```

- [x] **Step 4: BookingView.swift — 보호자 정보 하드코딩 제거**

  `BookingView.swift:8` 근처에 추가:
  ```swift
  @Environment(UserProfile.self) private var userProfile
  ```

  `guardianSection` 의 `formField` 값 교체:
  ```swift
  // 변경 전
  formField(label: "이름",  value: "김상민")
  formField(label: "연락처", value: "010-1234-5678")
  formField(label: "주소",  value: "경기 성남시 분당구 정자로 1")

  // 변경 후
  formField(label: "이름",  value: userProfile.name.isEmpty ? "이름 미설정" : userProfile.name)
  formField(label: "연락처", value: userProfile.phone.isEmpty ? "연락처 미설정" : userProfile.phone)
  formField(label: "주소",  value: userProfile.address.isEmpty ? "주소 미설정" : userProfile.address)
  ```

  `ReviewWriteSheet` 에서 `userName: "상민님"` 도 교체 (`StoreDetailView.swift:62`):
  ```swift
  // 변경 전
  userName: "상민님",

  // 변경 후 (StoreDetailView에 @Environment(UserProfile.self) 추가 후)
  userName: userProfile.name,
  ```

- [x] **Step 5: MyPageView.swift — 프로필 편집 연결 확인**

  `MyPageView.swift`에서 이름·연락처·주소를 입력받아 `UserProfile`에 저장하는 흐름이 있는지 확인. 없으면 간단한 편집 필드 추가:

  ```swift
  @Environment(UserProfile.self) private var userProfile

  // 이름 입력 필드 예시
  TextField("이름", text: $userProfile.name)
  TextField("연락처", text: $userProfile.phone)
  TextField("주소", text: $userProfile.address)
  ```

- [x] **Step 6: 빌드 확인**

  Xcode에서 `Cmd+B`
  Expected: Build Succeeded

  시뮬레이터에서 실행 → MyPage에서 이름 입력 → HomeView에서 "[이름]님" 반영 확인

- [x] **Step 7: Commit**

  ```bash
  cd /Users/suyoung/Documents/Dog_Kindergarden/Dog_kindergarden
  git add Dog_kindergarden/Models/UserProfile.swift \
           Dog_kindergarden/Views/Home/HomeView.swift \
           Dog_kindergarden/Views/Booking/BookingView.swift \
           Dog_kindergarden/Views/StoreDetail/StoreDetailView.swift
  git commit -m "feat: 하드코딩 사용자 정보를 UserProfile 모델로 교체"
  ```

---

## Task 5: 네이버 블로그 API 실연동

**배경:** `NaverBlogService.swift`는 구현 완료, `Info.plist`의 `NAVER_CLIENT_ID`/`NAVER_CLIENT_SECRET`이 플레이스홀더(`[NAVER_CLIENT_ID]`)라 실제 호출이 안 됨.

**Files:**
- Modify: `Dog_kindergarden/Dog_kindergarden/Config/Secret.xcconfig` (키 추가)

- [ ] **Step 1: 네이버 개발자 앱 등록**

  브라우저에서 https://developers.naver.com 접속:
  1. 로그인 → Applications → 애플리케이션 등록
  2. 애플리케이션 이름: `맡겨멍` (또는 임의)
  3. 사용 API: **검색** 체크 → 블로그
  4. iOS 번들 ID: Xcode 프로젝트 PRODUCT_BUNDLE_IDENTIFIER 값 입력
  5. 등록 후 `Client ID`와 `Client Secret` 복사

- [ ] **Step 2: Secret.xcconfig에 키 추가**

  `Secret.xcconfig`를 열어 아래 두 줄 추가 (실제 값으로):
  ```
  NAVER_CLIENT_ID = 여기에_복사한_Client_ID
  NAVER_CLIENT_SECRET = 여기에_복사한_Client_Secret
  ```

- [ ] **Step 3: 동작 확인**

  시뮬레이터에서 앱 실행 → 지도에서 가게 핀 탭 → StoreDetailView 열기 → "📝 블로그 후기" 섹션 확인
  Expected: 가게 이름 + 지역으로 네이버 블로그 결과 5건 표시

  (Secret.xcconfig가 비어있으면 `NaverBlogService:41-42` 가드 조건으로 조용히 스킵됨)

---

## Task 6: 미커밋 변경사항 정리 및 최종 커밋

**배경:** 배포 레디니스 리포트 기준 26건의 uncommitted changes 존재. Task 1~5 완료 후 남은 변경사항을 정리한다.

- [x] **Step 1: 현재 상태 확인**

  ```bash
  cd /Users/suyoung/Documents/Dog_Kindergarden/Dog_kindergarden
  git status --short
  ```

- [x] **Step 2: 변경 파일 검토 후 추가**

  주요 변경 파일들 (EmojiIcon.swift, AnimalBoardingService.swift, 이미지셋 등):
  ```bash
  git add Dog_kindergarden/Views/EmojiIcon.swift
  git add Dog_kindergarden/Views/KakaoMap/AnimalBoardingService.swift
  git add Dog_kindergarden/Assets.xcassets/
  git add Dog_kindergarden/Dog_kindergarden.xcodeproj/project.pbxproj
  git add Dog_kindergarden/Dog_kindergarden.xcodeproj/project.xcworkspace/xcshareddata/
  ```

- [x] **Step 3: Commit**

  ```bash
  git commit -m "feat: 공공데이터 API 연동 및 이모지 아이콘 추가"
  ```

- [x] **Step 4: 최종 git status 확인**

  ```bash
  git status
  ```
  Expected: `nothing to commit, working tree clean`

---

## Task 7: README 작성

**Files:**
- Create: `Dog_Kindergarden/README.md`
- Modify: `Dog_kindergarden/README.md` (현재 한 줄 → 완전한 가이드)

- [ ] **Step 1: 루트 README.md 작성**

  `/Users/suyoung/Documents/Dog_Kindergarden/README.md`:

  ```markdown
  # 맡겨멍 — 강아지 위탁 케어 플랫폼

  공공데이터 기반으로 전국 동물위탁관리업체를 지도에 표시하고, 보호자 리뷰와 예약 기능을 제공하는 iOS 앱입니다.

  ## 프로젝트 구조

  | 디렉토리 | 역할 |
  |---|---|
  | `Dog_kindergarden/` | iOS 앱 (Swift / SwiftUI) |
  | `backend-cloudflare/` | REST API (Cloudflare Workers + D1) |
  | `docs/` | 배포 레디니스 리포트, 플랜 문서 |

  ## 기술 스택

  - **iOS**: Swift 5.9, SwiftUI, Observation, KakaoMapsSDK (CocoaPods)
  - **Backend**: TypeScript, Hono 4, Cloudflare Workers, D1 (SQLite)
  - **외부 API**: 공공데이터(data.go.kr) 동물위탁업, 카카오 로컬, 네이버 블로그 검색

  ## 주요 기능

  - 🗺️ 전국 동물위탁관리업체 지도 표시 (TM→WGS84 좌표 변환)
  - 🐾 보호자 리뷰 (CCTV, 픽업, 대형견, 분리불안 케어 태그)
  - 📅 예약 요청 + 채팅
  - 📝 네이버 블로그 후기 연동

  ## 로컬 실행

  ### iOS

  1. **환경 요구**: Xcode 15+, CocoaPods
  2. `cd Dog_kindergarden && pod install`
  3. `Dog_kindergarden/Config/Secret.xcconfig.example` 복사 → `Secret.xcconfig` 생성 후 키 입력
  4. `Dog_kindergarden.xcworkspace` 열기 → 시뮬레이터 실행

  ### Backend

  1. **환경 요구**: Node.js 18+, Cloudflare 계정
  2. `cd backend-cloudflare && npm install`
  3. `npx wrangler dev` — 로컬 D1 포함 개발 서버 시작
  4. `npx wrangler d1 execute dog-kindergarden-db --file=migrations/0001_init.sql` — 마이그레이션 실행

  ## API 목록

  | Method | Path | 설명 |
  |---|---|---|
  | GET | `/api/stores` | 등록 가게 목록 |
  | GET | `/api/users/:id/pets` | 사용자 반려동물 목록 |
  | POST | `/api/reservations` | 예약 생성 |
  | GET | `/api/chatrooms/:id/messages` | 채팅 메시지 조회 |
  | POST | `/api/chatrooms/:id/messages` | 채팅 메시지 전송 |
  | POST | `/api/reviews` | 가게 리뷰 작성 |
  | GET | `/api/stores/:id/reviews` | 가게 리뷰 조회 |
  | POST | `/api/pet-reviews` | 보호자 펫 리뷰 작성 |
  | GET | `/api/pet-reviews?storeKey=` | 가게 펫 리뷰 조회 |
  | GET | `/api/pet-reviews/tags` | 전체 가게 태그 집계 |

  ## 환경변수

  | 변수 | 위치 | 설명 |
  |---|---|---|
  | `DATA_GO_KR_SERVICE_KEY` | `Secret.xcconfig` | 공공데이터포털 동물위탁업 API 키 |
  | `KAKAO_NATIVE_APP_KEY` | `Secret.xcconfig` | 카카오 지도 SDK 네이티브 앱키 |
  | `KAKAO_REST_API_KEY` | `Secret.xcconfig` | 카카오 로컬 REST API 키 |
  | `NAVER_CLIENT_ID` | `Secret.xcconfig` | 네이버 개발자센터 검색 API Client ID |
  | `NAVER_CLIENT_SECRET` | `Secret.xcconfig` | 네이버 개발자센터 검색 API Client Secret |
  ```

- [ ] **Step 2: Commit**

  ```bash
  cd /Users/suyoung/Documents/Dog_Kindergarden
  git add README.md
  cd Dog_kindergarden
  git add README.md
  git commit -m "docs: iOS README 가이드 및 루트 README 작성"
  ```

---

## 완료 체크리스트

배포 레디니스 리포트 기준으로 모든 항목 해소 여부 확인:

| 항목 | 상태 | 해결 Task |
|---|---|---|
| API 키 소스 하드코딩 | ✅ Info.plist → xcconfig 분리 | Task 2 |
| 미커밋 변경 26건 | ✅ 커밋 완료 | Task 6 |
| Pods git 추적 | ✅ git rm --cached | Task 1 |
| .gitignore 없음 (iOS) | ✅ 생성 | Task 1 |
| .gitignore 없음 (backend) | ✅ 생성 | Task 3 |
| Kakao 앱키 번들 제한 미설정 | ⚠️ 카카오 개발자 콘솔에서 수동 설정 필요 | Task 2 Step 6 |
| 목업 보호자 정보 하드코딩 | ✅ UserProfile 모델로 교체 | Task 4 |
| 네이버 블로그 API 미연동 | ✅ 키 발급 후 xcconfig에 추가 | Task 5 |
| debug print() | ✅ 이미 #if DEBUG 처리됨 | — |
| iOS README 한 줄 | ✅ 전체 가이드로 교체 | Task 7 |
| 중복 코드 (boardingType) | ✅ 이미 수정됨 | 완료 |
| backend TypeScript any | ✅ 타입 정의로 교체 | Task 3 |

---

## 실행 순서 권장

Task 1 → Task 2 → Task 3 → Task 6 → Task 4 → Task 5 → Task 7

Task 2 (xcconfig 설정)는 Xcode GUI 조작이 필요하므로 직접 수행 권장.
