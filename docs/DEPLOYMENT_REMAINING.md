# 맡겨멍 배포까지 남은 일

**기준일:** 2026-10-20
**기준 브랜치:** `main`
**목표:** App Store 1.0 제출과 소규모 실제 가게 파일럿

이 문서는 배포 준비의 단일 현황표다. 코드·로컬 환경만으로 끝낼 수 있는 작업은 바로 실행하고, 계정·실기기·권리 증빙·운영 의사결정이 필요한 작업만 미완료로 둔다. `docs/PLAN.md`는 상세 설계, `docs/RELEASE_TEST_CHECKLIST.md`는 실제 기기 테스트 절차를 담당한다.

## 1. 이번 점검에서 자동 완료한 작업

- [x] Hono·Wrangler와 전이 의존성을 안전 버전으로 갱신하고 깨끗한 설치에서 `npm audit` **0건** 확인
- [x] 갱신된 Wrangler로 Worker 배포 번들 dry-run 성공
- [x] 취약점 갱신과 API 입력 상한이 적용된 Worker 운영 배포 — 버전 `1ae53f87-4ba4-4d9d-8bbe-7d803f6a3bfc`
- [x] 운영 Worker 공개 상태·개인정보처리방침·고객지원·가게·공지 조회 확인
- [x] 운영 Worker에서 예약·사장님 가게·운영자 승인함·고객센터 무인증 요청이 모두 `401`인지 확인
- [x] 운영 읽기 전용 회귀를 반복할 `scripts/production-readonly-smoke.mjs` 추가
- [x] main push·Pull Request마다 의존성 audit, Worker dry-run, 빈 D1 마이그레이션, 인증·권한 회귀를 실행하는 GitHub Actions 추가
- [x] 모든 API 요청 본문을 2MiB로 제한하고 초과 요청을 D1·외부 API 처리 전에 HTTP `413`으로 차단 — 운영 응답까지 확인
- [x] iOS Simulator Release, 빈 D1 전체 마이그레이션, API 인증·권한 회귀를 포함한 Release audit 실행
- [x] 실제 iPhone용 unsigned `arm64` Archive와 완성 번들의 Secret·개발 메뉴·Privacy Manifest 검사
- [x] Xcode 27.0·iPhoneOS SDK 27.0이 현재 제출 최소 기준을 충족하는지 확인
- [x] README·FEATURES·PROGRESS·배포 준비 문서의 오래된 인증·배포 상태 정리

## 2. 출시 차단 항목 — 사용자 정보나 외부 계정 필요

아래 항목은 필요한 값이나 실제 계정이 준비되기 전에는 임의로 완료하지 않는다.

### 2.1 Apple 개발자와 로그인

- [ ] Apple Developer Program 가입
- [ ] Team ID, Sign in with Apple이 활성화된 App ID, Key ID와 `.p8` 키 준비
- [ ] 준비된 값은 Git이 아니라 Worker Secret과 Xcode Signing에 등록
- [ ] Sign in with Apple 구현·실계정 로그인·철회·회원 탈퇴 검증
- [ ] Apple 계정과 카카오 계정을 자동 이메일 병합하지 않을지 최종 확인

필요한 정보: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, Sign in with Apple Key의 `.p8`, Apple Client ID로 사용할 번들 ID 확인. 비밀키 원문은 채팅이나 Git에 붙이지 않고 Cloudflare Secret에 직접 등록한다.

### 2.2 App Store Connect 입력

- [ ] App Store Connect 앱 레코드 생성
- [ ] 계정의 법적 명칭을 기준으로 저작권 문구 확정
- [ ] `docs/APP_STORE_METADATA.md`의 이름·부제·설명·키워드·카테고리 입력
- [ ] 연령 등급 설문을 입력하고 Apple 산정 결과 기록
- [ ] Privacy Policy URL과 Support URL 입력
- [ ] `docs/APP_STORE_PRIVACY_CHECKLIST.md`의 App Privacy 항목 입력
- [ ] 서명 Archive의 Privacy Report와 App Privacy 최종 대조

필요한 정보: App Store Connect 접근 권한과 표시할 법적 저작권 명칭.

### 2.3 심사 계정과 실제 파트너

- [ ] 보호자 심사 계정 준비
- [ ] 실제 소유를 확인한 가게 1곳 이상과 사장님 심사 계정 준비
- [ ] 운영자 승인 후 보호자 예약 → 사장님 확정 → 채팅 → 알림장 → 완료 리뷰 데이터 준비
- [ ] 심사 기간 동안 계정·가게·데이터를 삭제하거나 비활성화하지 않도록 유지
- [ ] 심사 노트에 로그인 방법과 양쪽 역할의 확인 순서 기입

필요한 정보: 사용할 보호자·사장님 카카오 계정, 파일럿 가게, 가게 소유 확인 결과. 계정 비밀번호는 문서나 Git에 저장하지 않는다.

### 2.4 데이터와 이미지 사용 권리

- [ ] App Icon 원본 제작 또는 상업적 이용 권한 증빙을 비공개로 보관
- [ ] 네이버 플레이스에서 수집한 가격·영업시간·사진·편의정보의 운영 노출 가능 범위 확인
- [ ] 공공데이터 원본 데이터셋명, 이용허락, 재배포·가공·출처 표시 조건 확인
- [ ] `emoji_bone`과 `emoji_hotel`의 정확한 Flaticon 제작자·개별 출처 확인
- [ ] 권리가 확인되지 않은 업체 사진은 계속 숨김 처리하고 삭제하지 않음

필요한 정보: 원본 에셋 출처 링크·라이선스 증빙, 사용한 공공데이터 데이터셋 링크, 필요 시 업체 또는 권리자 확인 결과.

### 2.5 외부 콘솔 보안 설정

- [ ] Kakao Developers에서 iOS 번들 ID `net.suyoung.Dog-kindergarden` 제한 확인
- [ ] Naver·Kakao·공공데이터 키의 서비스·도메인·사용량 제한 확인
- [ ] Cloudflare 계정 권한을 복구해 운영 D1 미적용 마이그레이션이 0건인지 다시 확인

현재 CLI는 Worker 배포 이력은 읽지만 원격 D1 조회가 Cloudflare 오류 `7403`으로 거부된다. Cloudflare에서 현재 로그인 계정이 D1 데이터베이스 `dog_kindergarden_db`에 접근 가능한지 확인해야 한다.

## 3. 실제 기기와 제출 직전에 수행

- [ ] Apple Distribution 서명 Archive 생성
- [ ] Organizer `Validate App` 통과
- [ ] Archive에서 Privacy Report 생성
- [ ] 실제 iPhone에 Release/TestFlight 빌드 설치
- [ ] `docs/RELEASE_TEST_CHECKLIST.md` 전체 수행
- [ ] 카카오·Apple 로그인, 권한 허용·거부, 계정 전환·탈퇴 확인
- [ ] 보호자·사장님 두 기기에서 예약·채팅·알림장·리뷰 전체 흐름 확인
- [ ] 네트워크 단절·느린 연결·서버 오류·백그라운드 복귀 확인
- [ ] 필수 iPhone 크기의 App Store 스크린샷을 최종 빌드에서 다시 촬영
- [ ] TestFlight 내부 테스트 후 Critical/Major 결함 0건 확인
- [ ] 제출 당일 Apple 필수 Xcode·SDK 버전 재확인

현재 `docs/screenshots/` 이미지는 프로젝트 소개용 개발 화면이며 App Store 제출용 최종 스크린샷으로 간주하지 않는다.

## 4. v1.0 이후 작업 — 현재 출시 차단 아님

- [ ] Cloudflare R2 기반 알림장 다중 사진 업로드·삭제·보유기간 관리
- [ ] APNs 원격 Push — 현재 서버 이벤트 피드와 로컬 알림 사용
- [ ] WebSocket 실시간 채팅 — 현재 화면 내 폴링 사용
- [ ] 파트너가 가격·영업시간·사진·편의정보를 직접 관리하는 기능
- [ ] 앱 내부 결제, AI 리뷰 요약, 고급 추천·통계
- [ ] 사업자등록증 자동 인증

이 항목은 1.0 심사 준비, 데이터 권리 확인, 실제 가게 파일럿보다 먼저 구현하지 않는다.

## 5. 반복 실행 명령

```bash
# 전체 로컬 출시 검사
scripts/release-audit-smoke.sh

# 실제 iPhone용 unsigned Archive 검사
scripts/release-device-archive-preflight.sh

# 운영 서버에 데이터를 쓰지 않는 공개·인증 경계 검사
node scripts/production-readonly-smoke.mjs

# 백엔드 의존성 취약점
cd backend-cloudflare && npm audit
```

위 자동 검사가 통과해도 Apple 계정, 서명, 실제 기기, 심사 계정, 데이터 권리 항목을 자동 통과로 바꾸지 않는다.
