# API Key·Secret 서버 이전 감사

**감사일:** 2026-10-10  
**범위:** iOS 빌드 설정·앱 호출 경로·Cloudflare Worker·Git 이력  
**결론:** 운영 앱 배포 전에 서버용 자격 증명을 Worker로 이전하고 노출된 키를 교체해야 한다.

## 1. 발견 사항

### P0 — Release 앱 번들에 포함되는 서버용 자격 증명

현재 iOS 설정과 호출 경로에는 다음 값이 클라이언트에서 사용되는 구조가 남아 있다.

- Naver Client ID / Client Secret
- Kakao REST API Key
- 공공데이터포털 Service Key

앱 번들에 들어간 값은 소스 저장소가 비공개이거나 `xcconfig`가 Git에서 제외되어도 사용자가 추출할 수 있다. 따라서 이 값들은 **비밀 저장소가 아닌 배포된 클라이언트 자산**으로 간주해야 한다.

`KAKAO_NATIVE_APP_KEY`는 Kakao iOS SDK가 클라이언트에서 쓰도록 설계된 공개 식별자이므로 제거 대상이 아니다. 대신 카카오 콘솔에서 정확한 Bundle ID와 허용 플랫폼 제한을 확인한다.

### P0 — Git 이력에 존재하는 기존 자격 증명

Kakao REST API Key와 공공데이터 Service Key는 과거 커밋 이력에서 발견됐다. 파일의 현재 내용을 지우는 것만으로는 유출 대응이 끝나지 않으므로 새 키를 발급하고 기존 키를 폐기해야 한다.

Naver 값은 이번 Git 이력 점검에서 발견되지 않았지만 앱 번들에 포함됐던 값은 이미 노출된 것으로 보고 Worker 전환 후 교체한다.

> 이 문서에는 키 원문, 일부 문자열, 해시를 기록하지 않는다.

### P1 — 현재 직접 호출 경로

| 기능 | 현재 경로 | 문제 |
|---|---|---|
| 네이버 장소 보강 | iPhone → Naver Local API | Client Secret이 앱에 필요함 |
| 네이버 블로그 후기 | iPhone → Naver Blog API | Client Secret이 앱에 필요함 |
| 카카오 장소 조회 | iPhone → Kakao Local REST API | REST 키가 앱에 필요함 |
| 공공데이터 수집 | 로컬 수집 스크립트 중심 | 명령·오류 로그에 전체 URL과 키가 남을 수 있음 |

공공데이터 키는 현재 앱 런타임에 필요하지 않으므로 iOS 설정에서 제거하고, 수집을 계속한다면 Worker Secret 또는 별도 운영 수집 환경으로만 이동한다.

## 2. 목표 구조

앱이 외부 API의 임의 검색 프록시를 호출하게 만들지 않고, 인증된 사용자가 맡겨멍 DB에 존재하는 가게만 보강하도록 제한한다.

### 제안 엔드포인트

- `GET /api/store-enrichment/place?storeKey=...`
- `GET /api/store-enrichment/blogs?storeKey=...`

Worker는 `storeKey`로 D1에서 가게 이름·주소·좌표를 찾고 외부 API 쿼리를 직접 구성한다. 사용자가 임의 검색어를 전달하는 공개 프록시는 제공하지 않는다.

응답은 앱에 필요한 정규화 필드만 반환하고 외부 API 원문 오류, 요청 헤더, Secret이 포함된 URL은 반환하거나 로그로 남기지 않는다.

### Worker Secret 이름

- `NAVER_API_HUB_CLIENT_ID`
- `NAVER_API_HUB_CLIENT_SECRET`
- `KAKAO_REST_API_KEY`
- `DATA_GO_KR_SERVICE_KEY` — Worker에서 공공데이터 수집을 계속할 때만

`wrangler.toml`에는 Secret 이름이나 비밀이 아닌 기능 플래그만 두고 실제 값은 `wrangler secret put`으로 등록한다.

### 남용 방지

- 맡겨멍 세션 인증 필수
- D1에 등록된 가게만 조회
- 장소 보강 캐시 예시: 24시간
- 블로그 목록 캐시 예시: 15분
- 사용자·IP·가게별 호출 제한
- 외부 API 실패 시 안전한 일반 오류만 반환

## 3. 안전한 전환 순서

1. 각 공급자 콘솔에서 **새 자격 증명**을 발급한다.
2. 새 값을 Cloudflare Worker Secret에 저장한다.
3. Worker 보강 API와 캐시·호출 제한·오류 정제를 구현한다.
4. iOS 호출을 Worker API로 전환한다.
5. iOS `Info.plist`와 `xcconfig`에서 서버용 Key/Secret을 제거한다.
6. Release Archive 또는 앱 번들을 검사해 금지 키 이름·값이 없는지 확인한다.
7. Worker 운영 배포와 실제 기능 확인 후 과거 키를 폐기한다.
8. Git 이력의 과거 값은 공개 저장소 위험도를 검토해 필요 시 별도 이력 정리를 수행한다. 키 교체가 이력 정리보다 먼저다.

기존 키를 먼저 폐기하면 현재 앱 기능이 중단될 수 있으므로 **새 키 발급 → 서버 전환 → 클라이언트 제거 검증 → 기존 키 폐기** 순서를 지킨다.

## 4. 출시 자동 점검 보강 기준

Release smoke에서 아래 설정 이름이나 대응 값이 앱 번들에 포함되면 실패시킨다.

- `NAVER_CLIENT_ID`
- `NAVER_CLIENT_SECRET`
- `KAKAO_REST_API_KEY`
- `DATA_GO_KR_SERVICE_KEY`

`KAKAO_NATIVE_APP_KEY`는 허용하되 카카오 콘솔 제한 확인을 수동 체크리스트에 둔다. 로그 점검은 외부 요청 URL, 헤더, 오류 본문에 key·secret·serviceKey가 포함되지 않는지도 검사한다.

## 5. 완료로 표시할 수 없는 외부 작업

- Naver·Kakao·공공데이터 콘솔의 새 키 발급과 기존 키 폐기
- Cloudflare 운영 환경 Secret 등록
- 공급자별 도메인·Bundle ID·쿼터 제한 확인
- 운영 Worker 배포 후 실제 공급자 응답 검증

이 항목은 콘솔 작업과 운영 검증 증거가 확인되기 전까지 `PLAN.md`에서 완료 처리하지 않는다.
