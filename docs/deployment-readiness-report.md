# 맡겨멍 배포 준비 점검 결과

**최종 점검:** 2026-10-20 KST

**스택:** SwiftUI iOS 앱 + Cloudflare Workers/Hono + D1

**판정:** **조건부 준비 완료** — 코드·운영 공개 API의 자동 점검은 통과했지만 Apple 계정·서명·실기기·데이터 권리·심사 계정이 남아 있다.

남은 작업의 단일 현황표는 [`DEPLOYMENT_REMAINING.md`](DEPLOYMENT_REMAINING.md)를 사용한다.

## 자동 점검 결과

| 영역 | 결과 | 근거 |
|---|---|---|
| 백엔드 의존성 | PASS | Hono 4.13.13, Wrangler 4.151.1, 깨끗한 설치 `npm audit` 0건 |
| Worker 번들·운영 배포 | PASS | 갱신된 Wrangler dry-run 및 운영 버전 `1ae53f87-4ba4-4d9d-8bbe-7d803f6a3bfc` 배포 |
| 로컬 D1·권한 회귀 | PASS | 빈 D1 전체 마이그레이션과 인증·객체 소유권 회귀 통과 |
| 운영 공개 URL | PASS | `/`, `/privacy`, `/support`, `/api/stores`, `/api/notices` HTTP 200 |
| 운영 인증 경계 | PASS | 예약·사장님 가게·승인함·고객센터 무인증 조회 HTTP 401 |
| iOS Simulator Release | PASS | Release 빌드, 앱 소스 경고·Secret·개발 진입 차단 |
| iPhoneOS Archive | PASS | unsigned `arm64` Archive, iOS 17.0, 앱 이름·카테고리·Privacy Manifest 확인 |
| Xcode·SDK | PASS | Xcode 27.0, iPhoneOS SDK 27.0 |
| Git 민감 파일 | PASS | `.dev.vars`, 인증서, 개인키, 프로비저닝 파일 미추적 |
| GitHub CI | 준비 | main push·Pull Request에서 audit·Worker dry-run·로컬 D1·권한 회귀 실행 |
| API 입력 상한 | PASS | `/api/*` 본문 2MiB 초과 시 인증·D1 처리 전 HTTP 413, 운영 응답 확인 |

## 확인된 제한

- 운영 D1 원격 마이그레이션 목록 조회는 Cloudflare API `7403` 권한 오류로 이번 점검에서 재확인하지 못했다.
- unsigned Archive는 Apple Distribution 서명, Organizer Validate App, TestFlight 업로드를 대신하지 않는다.
- 운영 smoke는 실제 사용자 데이터를 만들거나 변경하지 않는 GET 요청만 사용한다.
- Sign in with Apple, 실제 기기 권한, 두 계정 간 흐름, APNs는 외부 계정·기기가 필요하다.
- 네이버·공공데이터·아이콘·업체 사진의 운영 사용 권리는 코드 검사만으로 확정할 수 없다.

## 출시 결론

현재 커밋은 자동 검사를 계속 진행할 수 있는 출시 후보 기반이다. App Store 제출 가능 상태로 확정하려면 `DEPLOYMENT_REMAINING.md`의 **출시 차단 항목**과 **실제 기기와 제출 직전 작업**을 완료해야 한다.
