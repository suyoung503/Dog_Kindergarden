# Sign in with Apple 도입 감사·구현 설계

**감사일:** 2026-10-10
**상태:** 설계 완료, Apple Developer 설정과 구현은 미완료

## 현재 상태

- 번들 ID: `net.suyoung.Dog-kindergarden`
- Xcode 자동 서명이지만 `DEVELOPMENT_TEAM` 미설정
- `.entitlements`, `CODE_SIGN_ENTITLEMENTS`, Sign in with Apple capability 없음
- `AuthenticationServices` 사용 코드 없음
- iOS `AuthSession`과 서버 `users.kakao_id NOT NULL` 구조가 카카오에 직접 결합됨
- 제공자와 무관한 30일 맡겨멍 세션·Keychain 저장 구조는 재사용 가능

로그인 버튼만 추가하면 Apple 전용 사용자를 안전하게 저장하거나 탈퇴 시 Apple 자격을 철회할 수 없으므로 인증 식별자 구조를 먼저 분리해야 한다.

## 권장 데이터 구조

`users`는 맡겨멍 프로필과 역할만 담당하고 외부 로그인 식별자는 별도 테이블로 분리한다.

```text
auth_identities
- identity_id
- user_id
- provider              KAKAO / APPLE
- provider_subject      카카오 ID 또는 Apple sub
- provider_email
- email_verified
- is_private_email
- credential_status
- last_validated_at
- revoked_at
- created_at / updated_at

UNIQUE(provider, provider_subject)
UNIQUE(user_id, provider)
```

Apple refresh token은 탈퇴 시 Apple 권한을 철회하기 위해 원문 복원이 필요하다. 해시만 저장하지 않고 Worker Secret의 별도 키로 AES-GCM 암호화해 `apple_credentials`에 저장한다.

안전한 전환 순서:

1. `auth_identities` 생성
2. 기존 `users.kakao_id`를 `KAKAO` identity로 백필
3. 카카오 로그인도 identity 테이블로 전환하고 회귀검사
4. `users.kakao_id` 직접 의존 제거
5. Apple challenge와 인증 구현

Apple 사용자에게 가짜 `kakao_id`를 넣는 방식은 사용하지 않는다.

## 서버 인증 흐름

권장 API:

```text
POST /api/auth/apple/challenge
POST /api/auth/apple
POST /api/me/auth-identities/apple/link
POST /api/auth/apple/events
```

### Challenge

서버가 5분 만료 `challenge_id`, 임의 `state`, 임의 `nonce`, 가입 요청 역할을 만든다. DB에는 검증에 필요한 해시와 사용 여부를 저장하고 한 번만 소비한다.

### iOS 인증

공식 `SignInWithAppleButton`과 `ASAuthorizationAppleIDRequest`를 사용한다.

```swift
request.requestedScopes = [.fullName, .email]
request.state = state
request.nonce = SHA256(rawNonce)
```

성공 후 identity token, authorization code, challenge ID, state, 최초 제공 이름을 서버로 보낸다.

### 서버 검증

서버는 다음을 모두 확인한다.

- challenge 존재·만료·미사용 여부
- 응답 state와 challenge 일치
- Apple 공개키 중 JWT `kid` 일치 키 선택과 서명 검증
- `iss == https://appleid.apple.com`
- `aud == net.suyoung.Dog-kindergarden`
- `exp`, `nonce`, `sub`
- authorization code 미사용 여부

Apple 공개키 회전을 처리하고 JWT 구현 오류를 줄이기 위해 Workers 호환 `jose` 사용을 우선 검토한다. authorization code는 즉시 Apple `/auth/token`으로 교환하고 refresh token을 암호화 저장한다. `.p8` 개인키는 앱·Git에 넣지 않고 Worker Secret으로만 관리한다.

## 사용자 정보와 역할

- Apple 이름은 최초 승인 때만 받을 수 있으므로 최초 값만 저장하고 재로그인에서 기존 닉네임을 덮어쓰지 않는다.
- 이름이 없으면 `보호자`로 시작하고 프로필 편집을 안내한다.
- 이메일은 클라이언트 값이 아니라 검증된 token 값을 우선한다.
- `@privaterelay.appleid.com`을 정상 이메일로 취급하되 실제 주소라고 추정하지 않는다.
- 역할은 로그인 제공자가 아니라 `users.is_owner`에 귀속한다.
- 신규 사용자만 최초 역할을 선택하며 재로그인의 역할 위조는 차단한다.
- `is_admin`은 Apple 이메일이나 제공자로 자동 부여하지 않는다.

## 카카오·Apple 계정 연결 정책

이메일 일치만으로 자동 병합하지 않는다. Private Relay, 이메일 미동의·변경과 계정 탈취 위험 때문이다.

안전한 연결 방식:

1. 기존 계정으로 로그인
2. 마이페이지에서 `Apple 계정 연결`
3. Apple 인증을 새로 수행
4. 서버 검증 후 현재 `user_id`에 identity 연결
5. 다른 사용자에 이미 연결된 identity면 409

기존 프로필과 역할을 유지하고 비어 있는 값만 보완한다. 이미 별도 계정 두 개가 생성된 경우 자동 병합하지 않고 관리자 절차를 둔다.

## 로그아웃·철회·회원 탈퇴

- 카카오 로그아웃: 카카오 SDK 로그아웃 + 맡겨멍 세션 폐기
- Apple 로그아웃: 맡겨멍 세션만 폐기하고 Apple 연결은 유지
- 앱 시작·포그라운드 복귀 시 `getCredentialState` 확인
- `credentialRevokedNotification` 구독
- `revoked` 또는 `notFound`이면 앱 세션 제거

Apple 사용자의 회원 탈퇴는 저장된 refresh token으로 Apple `/auth/revoke`를 호출한 뒤 맡겨멍 삭제·익명화, 모든 세션·identity·credential 삭제를 수행한다. 서버 간 이벤트 endpoint는 Apple의 `consent-revoked`, `account-deleted` 등을 검증해 세션과 identity를 정리한다.

## 자동 테스트 범위

- 정상·위조·만료 JWT, 잘못된 `kid`·`iss`·`aud`·nonce·sub
- 만료·재사용 challenge와 authorization code
- Apple 서버 오류와 refresh token 암호화 저장
- 신규 보호자·사장님, 기존 역할 위조, 관리자 자동 부여 차단
- 동일 이메일 자동 병합 금지, Private Relay, identity 중복 연결
- revoke 성공·실패, 자격 철회 이벤트, 탈퇴 후 세션 차단·재가입
- 기존 카카오 로그인 전체 회귀

## Apple Developer 계정 없이 가능한 작업

- identity 스키마와 카카오 백필
- challenge/state/nonce
- mock Apple 공개키 기반 JWT 검증 테스트
- 제공자별 `AuthSession` 분리와 Apple UI 코드
- 명시적 계정 연결 API
- 탈퇴·철회 코드 구조와 서버 간 이벤트 검증 테스트
- unsigned Simulator 빌드

## 사람이 완료해야 하는 항목

- Apple Developer Program 가입
- Team ID, App ID, Primary Sign in with Apple ID 설정
- Xcode capability·entitlement·프로비저닝 연결
- Sign in with Apple Key와 `.p8`, Key ID 발급
- 서버 간 알림 endpoint와 Private Relay 발신 도메인 등록
- 실제 iPhone에서 로그인·재로그인·철회·탈퇴·재가입 검증

필요 Worker 설정:

```text
APPLE_CLIENT_ID=net.suyoung.Dog-kindergarden
APPLE_TEAM_ID
APPLE_KEY_ID
APPLE_PRIVATE_KEY_P8
APPLE_REFRESH_TOKEN_ENCRYPTION_KEY
```

참고: [Xcode 설정](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple), [사용자 검증](https://developer.apple.com/documentation/signinwithapple/verifying-a-user), [계정 삭제·토큰 철회](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
