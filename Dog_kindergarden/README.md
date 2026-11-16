# 맡겨멍 iOS 앱

Swift 5.9 · SwiftUI + Observation · iOS 17+ · CocoaPods

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

`KakaoSDKCommon`, `KakaoSDKUser`, `KakaoMapsSDK` 등에 `Unable to resolve module dependency`가 뜨면, 기존 `.xcodeproj` 창 대신 위 워크스페이스를 열어 실행하세요. 프로젝트만 열면 CocoaPods의 SDK 타깃이 함께 빌드되지 않습니다.

Xcode 27에서는 오래된 SDK의 iOS 10/13 배포 대상 설정도 빌드 오류가 됩니다. `Podfile`의 `post_install`이 Pods의 최소 배포 대상을 iOS 17 이상으로 보정하므로, Xcode 업데이트 후에도 `pod install`을 실행하세요. 생성된 `Pods.xcodeproj`를 직접 수정할 필요는 없습니다.

### 2. iOS 공개 앱 키 설정 (필수)

API 키는 이 디렉터리 기준으로 git에서 제외된 `Base.lproj/Config/Create.xcconfig` 파일에 두고, `Info.plist`가 `$(변수)`로 참조합니다.
이 파일이 없으면 지도·로그인이 동작하지 않습니다. (Xcode 빌드 설정의 `baseConfigurationReference`가 이 파일을 가리키므로 다른 이름·위치로 만들면 인식되지 않습니다.)

위에서 `cd Dog_kindergarden`을 실행했다면 `Base.lproj/Config/Create.xcconfig` 파일을 새로 만들고 아래 내용을 채워주세요.

```
KAKAO_NATIVE_APP_KEY = 카카오_네이티브_앱_키
```

키 발급처:

| 키 | 발급처 | 용도 |
|---|---|---|
| `KAKAO_NATIVE_APP_KEY` | [Kakao Developers](https://developers.kakao.com) | iOS 카카오 지도와 로그인. Bundle ID 제한을 설정해야 함 |

Naver Client ID/Secret, Kakao REST API Key, 공공데이터 Service Key는 앱 설정에 넣지 않습니다. 외부 장소·블로그 조회는 인증된 Cloudflare Worker가 Secret으로 처리합니다.

### 3. 빌드·실행

Xcode에서 스킴 `Dog_kindergarden`으로 빌드·실행합니다.

```bash
xcodebuild -workspace Dog_kindergarden.xcworkspace -scheme Dog_kindergarden \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

### 4. 백엔드 연결

기본 API 주소는 배포된 Cloudflare Workers(`https://matgyeomung-api.dog-kindergarden.workers.dev`)입니다.
로컬 백엔드로 바꾸려면 앱 실행 후 `UserDefaults`의 `API_BASE_URL` 값을 로컬 주소로 덮어씁니다. (백엔드 실행 방법은 [`../backend-cloudflare/README.md`](../backend-cloudflare/README.md) 참고)

### 5. 로그인 없이 로컬에서 테스트하기 (DEBUG·시뮬레이터)

개발자 진입은 **운영 서버에서는 사용할 수 없습니다.** `DEBUG` 빌드이며 `APIEnvironment.isLocalDevelopment`가 참인 로컬 주소일 때만 시작 화면에 **"개발자 진입 (로컬 서버용)"**이 표시됩니다. 아래 시뮬레이터 예시는127.0.0.1을 사용합니다. Release에는 노출되지 않고 운영 Worker의 개발 로그인 API도 비활성입니다. 버튼이 안 보인다고 운영에 `ALLOW_DEV_AUTH`를 켜지 않습니다.

1. [백엔드 로컬 실행 안내](../backend-cloudflare/README.md)를 따라 로컬 D1을 마이그레이션하고 `.dev.vars`의 로컬 전용 설정으로 Worker를 실행합니다.
2. 기존 계정에서 로그아웃한 뒤 시뮬레이터 앱을 Xcode에서 일시정지하고 아래 LLDB 명령으로 API 주소를 지정합니다. 앱을 완전히 종료·재실행해야 시작 화면의 조건이 다시 반영됩니다.

```text
expr -l Swift -- import Foundation
expr -l Swift -- UserDefaults.standard.set("http://127.0.0.1:8787", forKey: "API_BASE_URL")
```

3. 역할 카드를 선택하고 로컬 개발자 진입을 누릅니다. 현재 서버의 기본 개발 식별자는 보호자 `dev-local-guardian`, 사장님 `dev-local-owner`이며 운영 카카오 계정과 무관합니다. 같은 로컬 환경에서 로그아웃→역할 전환으로 양쪽 흐름을 확인할 수 있습니다.
4. 운영으로 돌아갈 때는 로컬 계정에서 로그아웃하고, 일시정지한 앱의 LLDB에서 아래 설정을 제거한 뒤 앱을 재실행합니다.

```text
expr -l Swift -- import Foundation
expr -l Swift -- UserDefaults.standard.removeObject(forKey: "API_BASE_URL")
```

개발 계정으로 예약을 시험하려면 로컬에서 가게 등록 요청→운영자 승인도 필요합니다. 이는 실제 가게 소유 확인·실계정/실기기 심사 검증을 대신하지 않습니다. 운영 DB나 실제 계정을 테스트 데이터로 사용하지 않습니다.

## 아키텍처 메모

- 화면 전환은 `NavigationStack`이 아니라 `AppRouter.stack`(화면 enum 배열)을 `RootView`가 switch로 렌더링하는 커스텀 방식입니다.
- 상태는 `@Observable` 클래스(`AppRouter`, `BoardingStore`, `TagStore`, `UserProfile`, `AuthSession`)로 `RootView`에서 주입됩니다.
- 자세한 아키텍처 규칙은 저장소 루트의 [아키텍처 가이드](../docs/ARCHITECTURE.md)에 정리되어 있습니다.
