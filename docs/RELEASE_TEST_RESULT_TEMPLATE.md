# 맡겨멍 Release 테스트 결과

> 상태는 `PASS`, `FAIL`, `BLOCKED`, `NOT RUN` 중 하나로 기록한다. 실행하지 않은 항목을 PASS로 적지 않는다.

## 1. 빌드·환경 정보

| 항목 | 값 |
|---|---|
| 테스트 일시 | |
| 담당자 | |
| Git 브랜치 | |
| Git 커밋 | |
| 앱 버전 / 빌드 번호 | |
| Xcode / SDK | |
| iPhone / iOS | |
| 백엔드 환경 | 로컬 / 개발 / 스테이징 / 운영 |
| 보호자 계정 | 식별 가능한 개인정보 대신 테스트 계정 별칭 기록 |
| 사장님 계정 | |
| 운영자 계정 | |

## 2. 자동 smoke 결과

| 항목 | 상태 | 결과·로그 경로 | 비고 |
|---|---|---|---|
| Git·도구·민감 파일 검사 | NOT RUN | | |
| Worker 번들 dry-run | NOT RUN | | |
| 빈 D1 전체 마이그레이션 | NOT RUN | | |
| API 인증·권한 회귀 | NOT RUN | | |
| iOS Simulator Release 빌드 | NOT RUN | | |
| Release 번들 Secret·디버그 검사 | NOT RUN | | |

자동 결과 문서 경로:

## 3. 실제 기기 필수 결과

| 영역 | 상태 | 확인 내용 | 증거·비고 |
|---|---|---|---|
| 실제 iPhone 설치·실행 | NOT RUN | | |
| 카카오 실계정 인증 | NOT RUN | | |
| Apple 실계정 인증 | NOT RUN | | |
| 위치·사진·캘린더·알림 권한 | NOT RUN | | |
| 보호자 전체 흐름 | NOT RUN | | |
| 사장님·운영자 전체 흐름 | NOT RUN | | |
| APNs·딥링크 | NOT RUN | | |
| 느린 네트워크·오프라인·서버 오류 | NOT RUN | | |
| 앱 종료·백그라운드·계정 전환 | NOT RUN | | |
| 접근성·작은 화면·다크 모드 | NOT RUN | | |
| TestFlight 설치·업데이트 | NOT RUN | | |

세부 실행 항목은 [`RELEASE_TEST_CHECKLIST.md`](RELEASE_TEST_CHECKLIST.md)를 사용한다.

## 4. 발견 결함

| ID | 등급 | 제목 | 재현 단계 | 기대 결과 | 실제 결과 | 증거 | 담당·상태 |
|---|---|---|---|---|---|---|---|
| | Critical / Major / Minor / UX | | | | | | |

## 5. 미실행·차단 항목

| 항목 | 상태 | 사유 | 필요한 계정·기기·외부 조치 | 재검사 예정일 |
|---|---|---|---|---|
| | BLOCKED / NOT RUN | | | |

## 6. 최종 판정

- 자동 smoke: PASS / FAIL
- 실제 기기 필수 검사: PASS / FAIL / INCOMPLETE
- Critical 미해결: 건
- Major 미해결: 건
- 판정: 출시 후보 승인 / 조건부 보류 / 보류
- 판정 근거:
- 다음 조치:

## 7. 확인

| 역할 | 이름 | 확인일 | 의견 |
|---|---|---|---|
| 개발 | | | |
| 테스트 | | | |
| 출시 승인 | | | |
