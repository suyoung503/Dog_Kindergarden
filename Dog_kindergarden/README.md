# 맡겨멍 iOS 앱

Swift 5.9 · SwiftUI + Observation · iOS 16+ · CocoaPods

## 빌드 방법

### 1. 의존성 설치

```bash
cd Dog_kindergarden
pod install
```

반드시 `.xcodeproj`가 아닌 `.xcworkspace`로 엽니다.

```bash
open Dog_kindergarden.xcworkspace
```

### 2. API 키 설정 (필수)

API 키는 git에서 제외된 `Base.lproj/Config/Create.xcconfig` 파일에 두고, `Info.plist`가 `$(변수)`로 참조합니다.
이 파일이 없으면 지도·로그인이 동작하지 않습니다. (Xcode 빌드 설정의 `baseConfigurationReference`가 이 파일을 가리키므로 다른 이름·위치로 만들면 인식되지 않습니다.)

`Dog_kindergarden/Base.lproj/Config/Create.xcconfig` 파일을 새로 만들고 아래 내용을 채워주세요.

```
KAKAO_NATIVE_APP_KEY = 카카오_네이티브_앱_키
KAKAO_REST_API_KEY = 카카오_REST_API_키
DATA_GO_KR_SERVICE_KEY = 공공데이터포털_서비스_키
NAVER_CLIENT_ID = 네이버_클라이언트_ID
NAVER_CLIENT_SECRET = 네이버_클라이언트_시크릿
```

키 발급처:

| 키 | 발급처 | 용도 |
|---|---|---|
| `KAKAO_NATIVE_APP_KEY`, `KAKAO_REST_API_KEY` | [Kakao Developers](https://developers.kakao.com) | 지도, 카카오 로그인, 주소 검색 |
| `DATA_GO_KR_SERVICE_KEY` | [공공데이터포털](https://www.data.go.kr) — "동물위탁관리업" 검색 | 전국 애견 유치원·호텔 업체 데이터 |
| `NAVER_CLIENT_ID`, `NAVER_CLIENT_SECRET` | [Naver Developers](https://developers.naver.com) — 검색 API 중 블로그 사용 설정 | 가게 상세의 블로그 후기 |

> 네이버 키가 없어도 앱은 정상 빌드·실행됩니다 — 블로그 후기 섹션만 비어 있습니다.

### 3. 빌드·실행

Xcode에서 스킴 `Dog_kindergarden`으로 빌드·실행합니다.

```bash
xcodebuild -workspace Dog_kindergarden.xcworkspace -scheme Dog_kindergarden \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

### 4. 백엔드 연결

기본 API 주소는 배포된 Cloudflare Workers(`https://matgyeomung-api.dog-kindergarden.workers.dev`)입니다.
로컬 백엔드로 바꾸려면 앱 실행 후 `UserDefaults`의 `API_BASE_URL` 값을 로컬 주소로 덮어씁니다. (백엔드 실행 방법은 [`../backend-cloudflare/README.md`](../backend-cloudflare/README.md) 참고)

### 5. 로그인 없이 테스트하기 (시뮬레이터)

카카오 로그인 화면에서 **"개발자 진입 (시뮬레이터용)"** 버튼을 누르면 고정 계정(`kakao_id: dev-simulator`)으로 실제 서버에 등록되어, 예약·채팅·프로필 저장 등 서버 연동 기능을 모두 테스트할 수 있습니다. (DEBUG 빌드에서만 노출)

## 아키텍처 메모

- 화면 전환은 `NavigationStack`이 아니라 `AppRouter.stack`(화면 enum 배열)을 `RootView`가 switch로 렌더링하는 커스텀 방식입니다.
- 상태는 `@Observable` 클래스(`AppRouter`, `BoardingStore`, `TagStore`, `UserProfile`, `AuthSession`)로 `RootView`에서 주입됩니다.
- 자세한 아키텍처 규칙은 저장소 루트의 [`CLAUDE.md`](../CLAUDE.md)에 정리되어 있습니다.
