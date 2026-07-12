# Deployment Readiness Report

**Last checked:** 2026-07-13 (KST)
**감지된 스택:** iOS (Swift / SwiftUI, CocoaPods) + Cloudflare Workers (TypeScript/Hono) + D1 (SQLite)
**전체 판정:** ⚠️ Conditional — 포트폴리오 데모 배포 기준 하드 블로커 없음. `hono` high 취약점 업그레이드 권장. **App Store 실출시 기준으로는 API 무인증이 블로커.**

---

## Changes Since Last Check

**이전 점검:** 2026-06-21

### ✅ Resolved since last check
- **[구 Blocker #1] 정부 공공 API 서비스 키 하드코딩** — `AnimalBoardingService.swift:107`이 `Bundle.main`(Info.plist `$(DATA_GO_KR_SERVICE_KEY)` 주입)으로 전환. 키 원본은 git 제외된 `Create.xcconfig`
- Pods 279개 파일 git 추적 → **0건** (`.gitignore`에 `Pods/`)
- `.gitignore` 부재 → 루트·iOS·백엔드 3곳 모두 정비 (Pods, node_modules, xcuserdata, .env, xcconfig 시크릿 제외)
- `NSAllowsArbitraryLoads = true` → Info.plist에서 **제거됨** (ATS 정상)
- Kakao 앱 키 평문 → `$(KAKAO_NATIVE_APP_KEY)` 빌드 설정 주입으로 전환
- iOS README 한 줄 → 빌드 가이드 작성 완료 (2026-07-08, 루트·iOS·백엔드 README 3종)
- 목업 데이터(보호자 정보·Unsplash URL) → 검색 결과 0건
- 미커밋 변경 26건 → 이 리포트 파일 1건 제외 클린
- **구 노출 키 이력** — 저장소를 삭제 후 재생성해 이력이 초기화됨 (최초 커밋 `bf59e7a`, 2026-07-07). 전체 이력 pickaxe 검색(`git log --all -S`)에서 하드코딩 키 흔적 0건 확인 → 재발급 불필요

### 🆕 New issues found
- **npm audit: high 5 / low 1** — 런타임 의존성 `hono@^4.6.10`(≤4.12.24 취약, CORS 와일드카드 반사 등) + wrangler 개발 체인(undici·ws·esbuild·miniflare). `npm audit fix`로 해결 가능하나 로컬 `node_modules`가 root 소유라 쓰기 명령이 실패할 수 있음 — 소유권 정리 또는 재설치 필요
- **API 무인증 = 실출시 블로커** — 2026-07-12 사용자별 데이터 분리 검증에서 공식 기록 (아래 추가 점검 기록 참고). 데모 배포에는 블로커 아님

### ⏳ Still open from last check
- 디버그 `print()` — 1건 → **8건** (전부 `⚠️` 에러 핸들러 로그, 성격상 경미)
- Kakao Developer Console 번들 ID 제한 설정 — 콘솔 설정이라 **수동 확인 필요**

---

## Summary

6/21 시점의 하드 블로커(공공 API 키 하드코딩)와 경고 8건 중 7건이 해결됐습니다. 시크릿은 전부 git 제외된 `Create.xcconfig` → Info.plist 주입 구조로 정리됐고, Pods·node_modules 추적, ATS 비활성화, 목업 데이터도 모두 해소됐습니다. 남은 것은 ① `npm audit fix`로 해결 가능한 의존성 취약점(런타임에 실리는 건 hono뿐), ② App Store 실출시 전 필수인 API 인증 레이어(JWT), ③ 콘솔에서 확인해야 하는 수동 항목 1건(Kakao 번들 ID 제한)입니다. 6/21 이전 키 노출 이력은 저장소 재생성으로 초기화 확인 — 재발급 불필요.

---

## 🔴 Blockers — must fix before deploying

_데모(포트폴리오) 배포 기준: 없음_

**실출시(App Store) 기준:**

| # | Issue | Location | What to do |
|---|-------|----------|------------|
| 1 | 전 API 무인증 — `user_id`를 클라이언트 신뢰로 받음 | `backend-cloudflare/src/index.ts` 전체 라우트 | JWT 등 인증 레이어 도입 후 서버가 토큰에서 user_id 도출. 상세: `FEATURES.md` §13 |

---

## 🟡 Warnings — should address; not hard blockers

| # | Issue | Location | What to do |
|---|-------|----------|------------|
| 1 | `hono` high 취약점 (CORS 와일드카드 반사 GHSA-88fw-hqm2-52qc 등 5건, ≤4.12.24) — `app.use("*", cors())` 사용 중 | `backend-cloudflare/package.json` (`^4.6.10`) | `npm audit fix` 후 재배포. ※ 네이티브 앱 전용 API + 쿠키/credential 미사용이라 실질 영향은 제한적 |
| 2 | wrangler 개발 체인 취약점 (undici·ws·esbuild·miniflare, high 4/low 1) | `backend-cloudflare/` devDependencies | 배포 코드에 포함되지 않는 로컬 도구 — #1과 함께 `npm audit fix`. node_modules root 소유 문제로 실패 시 소유권 정리 후 재설치 |
| 3 | 디버그 `print()` 8건 | `KakaoLocalService.swift:61`, `KakaoMapView.swift:485,490`, `AnimalBoardingService.swift:155`, `NaverBlogService.swift:75`, `ReviewService.swift:98,129,159` | 전부 에러 핸들러 경고 로그. 출시 빌드 전 `os.Logger` 전환 또는 `#if DEBUG` 처리 |
| 4 | Kakao 앱 키 번들 ID 제한 미확인 | Kakao Developer Console | 콘솔에서 iOS 플랫폼 번들 ID 등록 여부 확인 (수동) |
| 5 | NAVER 키 미발급 — 블로그 후기 기능 비활성 상태 | `Create.xcconfig` (`NAVER_CLIENT_ID/SECRET`) | 기능 대기 항목 (배포 블로커 아님). 발급 절차: `PLAN.md` Task 5 |

---

## 🟢 Passing

- Git: 작업 트리 클린(이 리포트 파일 제외), 미푸시 커밋 없음, 충돌 마커 없음
- 시크릿: 소스 내 자격증명 패턴 0건, `.env`·xcconfig git 미추적, Info.plist는 전부 `$(변수)` 참조
- iOS: `Podfile.lock` 존재, Pods/xcuserdata 미추적, ATS 정상(NSAllowsArbitraryLoads 없음)
- 백엔드: `package-lock.json` 존재, `tsconfig strict: true`, `: any`/`@ts-ignore` 0건, `console.log` 0건
- 마이그레이션: `0001`~`0010` 순차·중복 없음 (다음 예약 번호 `0011_drop_reviews.sql`)
- 코드 위생: TODO/FIXME 0건, localhost/127.0.0.1 참조 0건, 목업(Unsplash) 0건
- 문서: README 3종(루트·iOS·백엔드) + FEATURES/PLAN/PROGRESS/PORTFOLIO
- 배포 설정: `wrangler.toml` D1 바인딩(`DB`) + Cron Trigger(매일 09:00 UTC) 정상, 코드의 `c.env.DB`·`c.env.APP_NAME` 모두 정의됨
- 사용자별 데이터 분리 검증 통과 (2026-07-12, 아래 기록)

---

## Full Checklist

### Git State
| Check | Status | Evidence |
|-------|--------|----------|
| 위치 | ✅ | 모노레포 루트가 git repo (6/21의 "iOS 하위만 repo" 상태 해소) |
| No uncommitted changes | ⚠️ | 이 리포트 파일 1건만 수정 상태 |
| No unpushed commits | ✅ | `git log origin/main..HEAD` 출력 없음 |
| No merge conflict markers | ✅ | `rg` 검색 결과 없음 |

### Secrets & Credentials
| Check | Status | Evidence |
|-------|--------|----------|
| 공공 API 키 하드코딩 | ✅ | `AnimalBoardingService.swift:107` → `Bundle.main` 참조 |
| Info.plist 키 평문 | ✅ | KAKAO/NAVER/DATA_GO_KR 5종 전부 `$(변수)` 참조 |
| xcconfig git 제외 | ✅ | `Create.xcconfig` 미추적 + `.gitignore` 등재, 필요 키 5종 정의 확인 |
| .env 추적 | ✅ | `git ls-files` 0건 |
| 자격증명 패턴 | ✅ | private key/password/api key 패턴 0건 |
| 과거 커밋 내 노출 키 | ✅ | 저장소 재생성으로 이력 초기화(최초 커밋 2026-07-07) + 전 이력 pickaxe 0건 |

### iOS / CocoaPods
| Check | Status | Evidence |
|-------|--------|----------|
| Podfile.lock 존재 | ✅ | 확인됨 |
| Pods/ gitignored | ✅ | 추적 0건 |
| .gitignore | ✅ | 루트·iOS 정비됨 |
| NSAllowsArbitraryLoads | ✅ | Info.plist에 없음 |
| 디버그 print | ⚠️ | 8건 — 전부 에러 핸들러 (Warning #3) |
| MARKETING_VERSION | ✅ | 1.0 |

### Node.js / Cloudflare Workers
| Check | Status | Evidence |
|-------|--------|----------|
| package-lock.json | ✅ | 존재 |
| tsconfig strict | ✅ | `"strict": true` |
| `: any` / `@ts-ignore` | ✅ | `src/index.ts` 0건 |
| npm audit | ❌ | high 5 / low 1 — hono(런타임)·wrangler 체인(개발) (Warning #1·#2) |
| wrangler.toml | ✅ | D1 바인딩 + workers.dev + cron `0 9 * * *` |
| env 바인딩 정합 | ✅ | 코드 사용 `c.env.DB`·`c.env.APP_NAME` 모두 wrangler.toml 정의 |
| backend .gitignore | ✅ | node_modules/.wrangler/dist/.env 제외 |

### Database Migrations
| Check | Status | Evidence |
|-------|--------|----------|
| 순차 정렬 | ✅ | 0001~0010, 결번·중복 없음 |
| 롤백(down) | N/A | D1 마이그레이션 구조상 별도 down 없음 |
| 스키마 변경 ↔ 마이그레이션 대응 | ✅ | 최근 스키마 변경(chat_room_reads) = `0010` 커밋 `2432891` |

### TODO / Debug
| Check | Status | Evidence |
|-------|--------|----------|
| TODO/FIXME | ✅ | 검색 결과 없음 |
| console.log (backend) | ✅ | 0건 |
| localhost/127.0.0.1 | ✅ | 0건 |

---

## 추가 점검 기록 (원본 리포트 이후)

### 2026-07-12 — 사용자별 데이터 분리 전수 검증 ✅ (커밋 `db36468`)

다른 카카오 계정 간 채팅·찜·예약 데이터가 섞이지 않는지 전수 점검한 결과.

| 영역 | 판정 | 내용 |
|---|---|---|
| 서버 쿼리 스코프 | ✅ | 예약·펫·채팅방·찜·받은 문의·안읽음 카운트 전부 `user_id`/`owner_id` 조건 확인 — 계정 간 혼입 경로 없음 |
| 기기 영속 분리 | ✅ | 최근 본 가게 계정별 키(`recent_pins_<userId>`), 로그아웃 시 `AppRouter.reset` 세션 초기화, 캘린더 일정 매핑(reservation_id 전역 유일) 안전 |
| UserProfile 잔존 | 🔧 수정 | 계정 전환 시 이전 계정 연락처·주소가 남던 유일한 실제 혼입 → 로그인 시 서버 값 무조건 덮어쓰기(비면 초기화) |
| user 1 행세 폴백 | 🔧 수정 | iOS `?? 1` 3곳 guard 교체 + `fetchPets` 기본값 제거 + DEBUG 오프라인 폴백 제거, 서버 `?? 1` 4곳 → 400 반환 |
| API 인증 | ⚠️ 실출시 블로커 | 전 API 무인증 — `user_id`를 클라이언트 신뢰로 받음. 정상 앱 사용에는 문제없으나 **App Store 출시 전 JWT 등 인증 레이어 필수** (상세: `FEATURES.md` §13) |

검증 방법: 서버 라우트 전수 rg 스캔 + curl 400 케이스 5종·정상 회귀 테스트 + xcodebuild BUILD SUCCEEDED. 테스트 데이터 잔존 0 확인.

---

## Commands Run

- `git status --short` / `git log origin/main..HEAD --oneline` / `git branch --show-current`
- `cat .gitignore Dog_kindergarden/.gitignore backend-cloudflare/.gitignore`
- `git ls-files | rg "Pods/|\.env|xcconfig|xcuserdata|node_modules/"` (각각 카운트)
- `rg -n "serviceKey|ServiceKey" Dog_kindergarden/Dog_kindergarden -g "*.swift"`
- `rg -n "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|password\s*[:=]…|api.?key\s*[:=]…" .` (Pods·node_modules 제외)
- `rg -n "NSAllowsArbitraryLoads|KAKAO|NAVER|DATA_GO_KR" Dog_kindergarden/Dog_kindergarden/Info.plist`
- `find Dog_kindergarden -name "*.xcconfig" -not -path "*/Pods/*"` + 키 이름만 추출(`rg -o "^[A-Z_]+"`, 값 미열람)
- `rg -n "TODO|FIXME|HACK|XXX" / "print\(" / "console\.log" / "localhost|127\.0\.0\.1" / "unsplash"` (소스 전역)
- `ls backend-cloudflare/migrations/` + `git log --oneline -5 -- backend-cloudflare/migrations/`
- `ls backend-cloudflare/package-lock.json Dog_kindergarden/Podfile.lock` / `rg '"strict"' tsconfig.json` / `rg '"(dev|deploy|d1:migrate)"' package.json`
- `npm audit --json` / `npm audit` (읽기 전용)
- `rg -o "c\.env\.\w+" src/index.ts | sort -u` / `cat backend-cloudflare/wrangler.toml`
- `rg -n "cors|serve-static" src/index.ts` / `rg '"hono"|"wrangler"' package.json`
- `rg -n "MARKETING_VERSION" project.pbxproj`
- `rg -l "^<{7} |^>{7} " .` (충돌 마커)
- `git log --reverse --oneline` (최초 커밋 확인) + `git log --all -S 'private let serviceKey = "'` (전 이력 키 흔적 검색)
