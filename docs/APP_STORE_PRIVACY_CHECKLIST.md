# 맡겨멍 App Store App Privacy 매핑 체크리스트

**점검 기준일:** 2026-10-11
**대상:** 현재 저장소의 iOS 앱, Cloudflare Worker·D1 스키마, CocoaPods SDK
**주의:** 이 문서는 App Store Connect 입력을 준비하기 위한 코드 기반 매핑이다. 실제 Archive의 Xcode Privacy Report와 운영 환경을 다시 대조한 후 제출해야 한다.

## 1. 조사 범위와 결론

### 앱 코드·서버에서 확인한 데이터 흐름

- 카카오 로그인: 카카오 사용자 ID, 닉네임, 동의된 이메일을 서버 계정에 연결
- 프로필: 닉네임, 전화번호, 주소를 서버에 저장
- 반려견: 이름, 견종, 나이, 몸무게, 성별, 사회성, 알레르기, 특이사항과 이용자가 선택한 프로필 사진 1장을 서버에 저장
- 예약·콘텐츠: 예약 일정·유형·요청사항, 채팅, 알림장, 리뷰를 사용자 계정 및 가게와 연결하여 저장
- 이용 기록: 찜, 읽음 상태, 가게 등록 신청·승인 이력을 계정과 연결하여 저장
- 인증: 앱은 원문 세션 토큰을 Keychain에 저장하고 서버는 SHA-256 해시를 30일 인증에 사용

### 현재 빌드에서 수집하지 않는 항목

- **현재 위치:** `Info.plist`에 위치 권한 설명 문자열은 있으나 앱 소스에 `CoreLocation` 사용이나 위치 권한 요청 코드가 없다. 현재 빌드 기준으로 위치를 수집한다고 표시하지 않는다. 위치 기능을 구현하면 선언을 재검토한다.
- **알림장 사진·동영상:** 알림장 사진 업로드는 아직 구현되지 않았다. 다만 강아지 프로필은 시스템 `PhotosPicker`로 선택한 사진 1장을 압축해 서버에 저장하므로 `Photos or Videos`를 수집 항목으로 선언한다.
- **캘린더 내용:** EventKit으로 맡겨멍 예약 일정을 기기에 추가·삭제하지만 캘린더 내용을 서버로 전송하지 않는다. 기기 내부 처리만 하므로 수집 데이터로 표시하지 않는다.
- **진단·광고:** 충돌·분석·광고 SDK, IDFA, ATT 또는 광고 목적 데이터 처리가 없다.

## 2. App Store Connect 입력 매핑

App Store Connect의 **“이 앱에서 데이터를 수집합니까?”**에는 현재 빌드 기준으로 `예`를 선택한다.

아래 항목은 모두 사용자 계정·예약·콘텐츠와 연결되므로 **사용자에게 연결됨: 예**, 광고·데이터 브로커·타사 앱 추적에 사용하지 않으므로 **추적에 사용: 아니요**, 목적은 **앱 기능(App Functionality)**으로 입력한다.

| App Privacy 분류 | 선택 | 실제 데이터 | 연결됨 | 추적 | 목적 |
|---|---:|---|---:|---:|---|
| Contact Info → Name | 예 | 카카오·프로필 닉네임, 채팅·리뷰 표시 이름 | 예 | 아니요 | 앱 기능 |
| Contact Info → Email Address | 예 | 카카오가 동의 범위에서 제공한 이메일 | 예 | 아니요 | 앱 기능 |
| Contact Info → Phone Number | 예 | 이용자가 입력한 연락처 | 예 | 아니요 | 앱 기능 |
| Contact Info → Physical Address | 예 | 이용자가 입력한 주소 | 예 | 아니요 | 앱 기능 |
| Identifiers → User ID | 예 | 카카오 사용자 식별자, 맡겨멍 사용자 ID | 예 | 아니요 | 앱 기능 |
| User Content → Emails or Text Messages | 예 | 보호자·사장님 간 앱 내 채팅 | 예 | 아니요 | 앱 기능 |
| User Content → Photos or Videos | 예 | 이용자가 선택한 강아지 프로필 사진 1장 | 예 | 아니요 | 앱 기능 |
| User Content → Other User Content | 예 | 반려견 정보, 예약 요청사항, 알림장, 리뷰 본문·평가·태그 | 예 | 아니요 | 앱 기능 |
| Usage Data → Product Interaction | 예 | 찜, 예약·채팅 읽음 상태, 사장님 가게 등록 신청·처리 기록 | 예 | 아니요 | 앱 기능 |
| Other Data → Other Data Types | 예 | KakaoMapsSDK와 KakaoSDKCommon이 자체 Privacy Manifest에서 선언 | 예 | 아니요 | 앱 기능 |

### 현재 `아니요`로 두는 항목

- Precise Location / Coarse Location
- Audio Data
- Contacts / Health / Fitness / Financial Info / Sensitive Info
- Browsing History / Search History
- Device ID / Advertising Data
- Crash Data / Performance Data / Other Diagnostic Data
- Purchases

> **제출 직전 확인:** App Store Connect 선언은 앱 자체뿐 아니라 제3자 SDK의 수집도 포함해야 한다. Xcode Privacy Report가 위 표와 다르면 보고서를 기준으로 원인을 조사한 뒤 문서와 App Store Connect를 함께 수정한다.

## 3. 앱 Privacy Manifest 매핑

파일: `Dog_kindergarden/Dog_kindergarden/PrivacyInfo.xcprivacy`

### 앱이 직접 수집하는 데이터

- `NSPrivacyCollectedDataTypeName`
- `NSPrivacyCollectedDataTypeEmailAddress`
- `NSPrivacyCollectedDataTypePhoneNumber`
- `NSPrivacyCollectedDataTypePhysicalAddress`
- `NSPrivacyCollectedDataTypeUserID`
- `NSPrivacyCollectedDataTypeEmailsOrTextMessages`
- `NSPrivacyCollectedDataTypeOtherUserContent`
- `NSPrivacyCollectedDataTypePhotosorVideos`
- `NSPrivacyCollectedDataTypeProductInteraction`

모든 항목은 `Linked = true`, `Tracking = false`, 목적은 `App Functionality`로 선언한다.

### 추적

- `NSPrivacyTracking = false`
- `NSPrivacyTrackingDomains = []`
- 앱 코드에서 ATT, IDFA, AdSupport, 광고 SDK 사용을 찾지 못함

### Required Reason API

| 주체 | API 분류 | 이유 코드 | 근거 |
|---|---|---|---|
| 맡겨멍 앱 | UserDefaults | `CA92.1` | 앱 자체 로그인 표시 상태, 프로필 로컬 사본, 최근 본 가게, 알림·캘린더 매핑을 앱 전용 기본값에 저장 |
| Alamofire 5.9.1 | System Boot Time | `35F9.1` | SDK 제공 Privacy Manifest |
| KakaoMapsSDK 2.12.12 | UserDefaults / Disk Space / File Timestamp | `CA92.1` / `E174.1` / `C617.1` | SDK 프레임워크 제공 Privacy Manifest |
| KakaoSDKCommon 2.22.7 | UserDefaults | `CA92.1` | SDK 제공 Privacy Manifest |

Keychain, EventKit, URLSession, UserNotifications 사용은 현재 Apple의 Required Reason API 목록에서 앱이 추가 사유 코드를 선언해야 하는 항목으로 확인되지 않았다.

## 4. 제3자 SDK 확인

| SDK | 버전 | Manifest 확인 | 현재 조치 |
|---|---:|---:|---|
| Alamofire | 5.9.1 | `Pods/Alamofire/Source/PrivacyInfo.xcprivacy` | Apple 필수 SDK 목록에 해당. 현재는 소스 의존성이라 바이너리 SDK 서명 대상이 아니며 CocoaPods 리소스 빌드 단계 포함 확인 |
| KakaoMapsSDK | 2.12.12 | XCFramework의 기기·시뮬레이터 framework 내부에 존재 | Apple 필수 SDK 목록에는 없으나 앱에 포함되는 framework의 manifest 유지. 내려받은 기기 바이너리는 개발자 서명이 없으므로 실제 Archive 서명·검증을 수동 확인 |
| KakaoSDKCommon | 2.22.7 | `Pods/KakaoSDKCommon/Sources/KakaoSDKCommon/PrivacyInfo.xcprivacy` | CocoaPods 리소스 빌드 단계 포함 확인 |
| KakaoSDKAuth | 2.22.7 | 독립 manifest 없음 | KakaoSDKCommon 의존성 포함 상태와 최신 SDK 배포 문서 재확인 |
| KakaoSDKUser | 2.22.7 | 독립 manifest 없음 | KakaoSDKCommon 의존성 포함 상태와 최신 SDK 배포 문서 재확인 |

`KakaoMapsSDK`와 `KakaoSDKCommon`의 manifest는 `Other Data Types`, 사용자 연결 `true`, 추적 `false`, 앱 기능 목적을 선언한다. 따라서 App Store Connect 매핑에도 이를 포함했다.

Apple의 현재 필수 제3자 SDK 목록에는 Alamofire가 포함되고 Kakao SDK는 포함되지 않는다. 필수 목록에 있는 SDK를 바이너리 의존성으로 사용하는 경우 manifest와 SDK 서명이 모두 필요하지만, 이 프로젝트의 Alamofire는 CocoaPods가 소스에서 빌드한다. SDK 목록과 제출 요건은 바뀔 수 있으므로 제출 당일 Apple 문서와 Xcode 검증 결과를 다시 확인한다.

## 5. 시스템 권한과 데이터 수집 구분

| 권한·기능 | 코드 상태 | 서버 전송 | 제출 전 조치 |
|---|---|---:|---|
| 캘린더 전체 접근 | 예약 확정 일정 추가와 취소 일정 삭제에 사용 | 아니요 | 실제 기기에서 요청 시점·거부 흐름 확인 |
| 알림 | 서버 알림 피드를 30초 간격으로 확인하여 로컬 알림 표시 | 알림 피드 조회만 | APNs 도입 시 기기 토큰 수집 선언 재검토 |
| 위치 When In Use | 설명 문자열은 있으나 요청·수집 코드 없음 | 아니요 | 위치 기능 구현 전까지 요청하지 않는지 확인 |
| 위치 Always | 설명 문자열은 있으나 요청·수집 코드 없음 | 아니요 | 실제 사용 계획이 없다면 최종 제출 전에 `Info.plist`에서 제거 |
| 사진 | `PhotosPicker`로 이용자가 명시적으로 선택한 강아지 사진 1장을 JPEG로 압축·업로드 | 예 | Photos or Videos 선언 유지, 탈퇴 시 반려견 행과 함께 삭제되는지 운영 검증 |
| 카메라 | 직접 촬영 코드 없음 | 아니요 | 카메라 촬영 기능을 추가할 때 권한 설명 재검토 |

## 6. 제출 전 수동 체크리스트

### 2026-10-09 로컬 검증 결과

- `plutil -lint`로 앱 `PrivacyInfo.xcprivacy` 형식 검증 통과
- iOS Simulator용 Release configuration 빌드 통과
- Xcode의 파일 시스템 동기화 대상인 앱 소스 폴더에 manifest를 두어 별도 `project.pbxproj` 수정 없이 앱 리소스에 포함
- 빌드된 `Dog_kindergarden.app/PrivacyInfo.xcprivacy`와 소스 파일이 동일함을 확인
- 빌드 앱에서 앱·Alamofire·KakaoMapsSDK·KakaoSDKCommon manifest 총 4개 확인

위 결과는 시뮬레이터 Release 빌드 검증이며, 배포용 서명 Archive와 App Store Connect 검증을 대신하지 않는다.

- [ ] Xcode에서 **Archive → Generate Privacy Report**를 실행해 앱과 모든 SDK의 집계 결과 확인
- [ ] Archive 안의 앱 루트에 `PrivacyInfo.xcprivacy`가 존재하는지 확인
- [ ] App Store Connect에서 제2절의 데이터 유형·연결·추적·목적을 동일하게 입력
- [ ] 개인정보처리방침의 운영자 이메일 TODO 확정
- [ ] 개인정보처리방침의 계정·예약·채팅·알림장·리뷰·백업 보유기간 TODO 확정
- [x] 회원 탈퇴와 서버 삭제·익명화 기능을 실제 동작과 대조 — 진행 예약 차단, 개인정보 삭제, 운영 기록 익명화, 전 세션 폐기 반영
- [ ] 공개 HTTPS URL에 최종 개인정보처리방침 게시
- [ ] App Store Connect의 Privacy Policy URL 입력
- [ ] 실제 iPhone에서 카카오 로그인, 캘린더 권한, 알림 권한과 거부 흐름 확인
- [ ] 위치·사진·APNs·분석 SDK를 추가하거나 SDK 버전을 올릴 때 manifest와 App Privacy를 재검토

## 7. 현재 남아 있는 출시 차단 사항

1. 운영자 이메일 미확정
2. 개인정보 항목별 보유기간과 탈퇴 시 삭제·익명화 기준 미확정
3. 공개 Privacy Policy URL 미생성
4. 실제 Archive Privacy Report 미생성
5. App Store Connect App Privacy 미입력

따라서 이번 작업은 **코드·문서 준비 완료**이지, 개인정보 관련 출시 요건 전체 완료가 아니다.
