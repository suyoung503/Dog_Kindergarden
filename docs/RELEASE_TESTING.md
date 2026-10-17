# 맡겨멍 출시 전 테스트 실행 안내

이 문서는 `PLAN.md`의 **Release Audit**과 **실제 기기 Release 테스트 전 단계**를 반복 가능한 로컬 검사와 수동 검사로 분리한다.

## 1. 자동으로 확인하는 범위

저장소 루트에서 다음 명령을 실행한다.

```bash
scripts/release-audit-smoke.sh
```

자동 검사는 운영 D1이나 실제 사용자 계정에 접근하지 않는다. 매 실행마다 빈 임시 D1에 전체 마이그레이션을 적용하고 로컬 Worker를 실행한다.

| ID | 검사 내용 | 성공 기준 |
|---|---|---|
| A01 | Node, npm, Wrangler 실행 도구와 Xcode 도구 확인 | 필수 도구가 모두 설치됨 |
| A02 | 브랜치·커밋·작업 트리 상태 기록 | 실행 대상 상태가 결과에 기록됨 |
| A03 | 인증서·환경변수 파일의 Git 추적 검사 | 민감 파일이 추적되지 않음 |
| S01 | iOS 설정의 서버용 API 자격 증명 검사 | Naver·Kakao REST·공공데이터 자격 증명 리터럴이 없음 |
| S02 | `All_data.csv` 등 문서와 저장소 불일치 확인 | 미정리 파일이 없음 |
| B01 | Worker 배포 번들 dry-run | 번들 생성 성공 |
| B02 | 빈 D1에 모든 마이그레이션 적용 | 전체 마이그레이션 성공 |
| B03 | 격리된 로컬 Worker 기동 | 루트 상태 API 응답 성공 |
| B04 | 인증·객체 권한·승인·예약 상태 회귀 | 기존 API 회귀 테스트 전체 성공 |
| I01 | iOS Simulator용 Release configuration 빌드 | 코드 서명 없이 Release 빌드 성공 |
| I02 | 빌드된 앱의 Secret·개발용 진입 검사 | 서버용 API 자격 증명과 개발 진입 문구가 없음 |
| I03 | 맡겨멍 앱 소스의 Release 컴파일러 경고 검사 | 앱 소스 경고가 0건이며, Pods·Xcode 도구 경고와 분리됨 |
| I04 | 완성 앱의 최소 지원 iOS 검사 | `MinimumOSVersion`이 의도한 iOS 17.0으로 고정됨 |
| I05 | App Store 표시 이름·카테고리 검사 | `CFBundleDisplayName=맡겨멍`, `LSApplicationCategoryType=public.app-category.lifestyle` |

결과와 단계별 로그는 기본적으로 `/tmp/matgyeomung-release-smoke-실행시각`에 생성된다. 보존하려면 출력 경로를 지정한다.

```bash
RESULT_DIR="$PWD/artifacts/release-smoke/$(date +%Y%m%d-%H%M%S)" \
  scripts/release-audit-smoke.sh
```

빠르게 백엔드 회귀만 재검사할 때는 다음 옵션을 사용할 수 있다.

```bash
scripts/release-audit-smoke.sh --quick
scripts/release-audit-smoke.sh --backend-only
scripts/release-audit-smoke.sh --ios-only
```

자동 검사 하나라도 실패하면 명령은 종료 코드 `1`을 반환한다. 다른 단계는 가능한 범위에서 계속 실행되어 한 번의 실행으로 전체 실패 목록을 남긴다.

## 2. 자동 통과로 판단하지 않는 항목

다음 항목은 로컬 Simulator나 개발용 인증 우회로 검증할 수 없다. 자동 결과가 `PASS`여도 별도 수동 검사가 필요하다.

- 실제 iPhone의 Release 빌드 설치와 실행
- 실제 카카오 계정 로그인·재로그인·로그아웃
- Sign in with Apple 실계정 인증과 자격 철회
- 실제 위치·사진·캘린더·알림 권한 허용, 거부, 설정 변경
- APNs Push의 포그라운드·백그라운드·강제 종료 수신
- OAuth·알림·외부 링크 딥링크
- TestFlight 설치·업데이트·크래시 수집
- 보호자와 사장님 실제 계정 및 두 기기 간 전체 흐름
- 느린 이동통신망, 오프라인 전환, 운영 Worker 오류
- VoiceOver, 글자 크기, 작은 화면, 다크 모드

이 항목은 [`RELEASE_TEST_CHECKLIST.md`](RELEASE_TEST_CHECKLIST.md) 순서대로 실행하고 [`RELEASE_TEST_RESULT_TEMPLATE.md`](RELEASE_TEST_RESULT_TEMPLATE.md)에 결과를 기록한다.

## 3. 기존 테스트 현황과 한계

- 백엔드의 `backend-cloudflare/scripts/test-auth-permissions.mjs`는 인증·역할·객체 소유권·가게 승인·예약 상태 회귀를 검사하며 자동 smoke에서 재사용한다.
- iOS의 `Dog_kindergardenTests`는 로딩 상태, 강아지 기본값, 파트너 capability 디코딩, 알림 딥링크, 예약 가격표 변환을 검사하는 단위 테스트 5개를 포함한다. 전체 사용자 흐름과 UI 회귀는 아직 실제 기기 수동 검사 대상이다.
- 실제 iPhone, 외부 계정, APNs, TestFlight가 필요한 항목은 스크립트에서 임의로 성공 처리하지 않는다.
- Simulator Release 빌드 성공은 실제 기기 코드 서명, capability, provisioning, APNs, 외부 SDK 동작 성공을 의미하지 않는다.

## 4. 출시 판정 규칙

1. 자동 smoke의 `FAIL`을 모두 해결한다.
2. 수동 체크리스트의 필수 항목을 실제 기기에서 실행한다.
3. Critical과 Major 결함이 0건인지 확인한다.
4. 미실행 항목은 `PASS`로 간주하지 않고 사유와 후속 일정을 남긴다.
5. 검사한 Git 커밋과 실제 TestFlight/App Store 빌드의 커밋이 같은지 확인한다.
