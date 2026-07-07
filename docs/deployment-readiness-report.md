# Deployment Readiness Report

**Last checked:** 2026-06-21 (KST)
**감지된 스택:** iOS (Swift / UIKit+SwiftUI, CocoaPods) + Cloudflare Workers (TypeScript/Hono) + D1 (SQLite)
**전체 판정:** ❌ Not ready — 정부 공공 API 서비스 키가 소스에 하드코딩되어 배포 전 반드시 제거·교체 필요

---

## Changes Since Last Check

**이전 점검:** (날짜 미기재 — 직전 리포트 기준)

### ✅ Resolved since last check
- 없음 — 이전 점검의 블로커·경고가 모두 그대로 유지됨

### 🆕 New issues found
- 정부 공공 API 서비스 키가 신규 `BoardingStore`(같은 파일 107행)에 **여전히 평문 하드코딩** — data.go.kr `animal_boarding/info` 연동이 실제로 붙으면서 키가 코드에 박힘
- 디버그 `print()` 1건 — `AnimalBoardingService.swift:151` (에러 핸들러, 경미)
- 미커밋 변경 24 → **26건**으로 증가 (신규 `EmojiIcon.swift`, `AnimalBoardingService.swift`, 이미지셋 7종 미추적)

### ⏳ Still open from last check
- [Blocker] 서비스 키 하드코딩 (`AnimalBoardingService.swift:107`)
- Pods 디렉토리 279개 파일 git 추적
- `.gitignore` 부재
- `NSAllowsArbitraryLoads = true`
- Kakao 앱 키 평문 + 번들 ID 제한 미설정
- iOS README 한 줄
- 목업 데이터(보호자 이름/연락처, Unsplash URL) 잔존

---

## Summary

data.go.kr 동물위탁관리업 API 연동이 실제 코드에 붙었지만, 정부 서비스 키가 `BoardingStore`에 평문으로 박혀 있어 이대로 커밋·배포하면 키가 노출됩니다. 이것이 유일한 하드 블로커입니다. 그 외 Pods 전체 git 추적, `.gitignore` 부재, ATS 비활성화, Kakao 키 평문 등은 App Store 심사·재현성 관점에서 정리가 필요합니다. 백엔드(Cloudflare Workers)는 strict 모드·lockfile·마이그레이션 순서가 양호합니다.

---

## 🔴 Blockers — must fix before deploying

| # | Issue | Location | What to do |
|---|-------|----------|------------|
| 1 | 정부 공공 API 서비스 키 평문 하드코딩 | `Dog_kindergarden/Views/KakaoMap/AnimalBoardingService.swift:107` | 코드에서 제거 → Info.plist(빌드 설정 주입) 또는 백엔드 프록시 경유로 호출. 이미 노출됐으므로 **data.go.kr에서 키 재발급** 권장 |

---

## 🟡 Warnings — should address; not hard blockers

| # | Issue | Location | What to do |
|---|-------|----------|------------|
| 1 | 미커밋 변경 26건 (16 수정 / 10 미추적) | `Dog_kindergarden/` | 키 정리 후 `git add && git commit` — 현재 배포 코드 버전 불명확 |
| 2 | Pods 279개 파일 git 추적 | `Dog_kindergarden/Pods/` | `.gitignore`에 `Pods/` 추가 후 `git rm -r --cached Pods` |
| 3 | `.gitignore` 부재 | iOS repo 루트 | Pods, xcuserdata, `.DS_Store`, build/ 등 추가 |
| 4 | `NSAllowsArbitraryLoads = true` | `Info.plist:24` | ATS 재활성화 — App Store 심사 거절 사유. API가 HTTPS이므로 제거 가능 |
| 5 | Kakao 네이티브 앱 키 평문 | `Info.plist:33` | Kakao Developer Console에서 번들 ID 제한 설정 |
| 6 | 디버그 `print()` | `AnimalBoardingService.swift:151` | 배포 빌드 전 제거 또는 로깅 처리 |
| 7 | iOS README 한 줄 | `Dog_kindergarden/README.md` | 빌드/실행/키 주입 가이드 추가 |
| 8 | 목업 데이터 하드코딩 | Views 다수 (`StoreDetailView`, `BookingView` 등) | 보호자 정보·시설사진(Unsplash URL) → 실제 데이터로 교체 |

---

## 🟢 Passing

- 백엔드 소스에 시크릿 없음
- TypeScript strict 모드 ON (`tsconfig.json`)
- 마이그레이션 순차 정렬 (`0001_init.sql`, `0002_reviews.sql`)
- `package-lock.json` 존재 — 재현 가능 빌드
- 백엔드 배포 URL 설정됨 (`matgyeomung-api…workers.dev`)
- 병합 충돌 마커 없음
- 미푸시 커밋 없음 (upstream 미설정)
- TODO/FIXME 없음
- API 좌표 변환·대한민국 영역 필터링 로직 존재 (`TMConverter`, 좌표 경계 체크)

---

## Full Checklist

### Git State
| Check | Status | Evidence |
|-------|--------|----------|
| 위치 | — | git repo는 `Dog_kindergarden/` 하위 (루트 아님) |
| No uncommitted changes (iOS) | ❌ | `git status --short` 26건 |
| No uncommitted changes (backend) | ✅ | backend 변경 없음 |
| No unpushed commits | ✅ | upstream 미설정 |
| No merge conflict markers | ✅ | `rg` 검색 결과 없음 |

### Secrets & Credentials
| Check | Status | Evidence |
|-------|--------|----------|
| Government API key in iOS source | ❌ | `AnimalBoardingService.swift:107` 평문 serviceKey |
| Kakao app key in Info.plist | ⚠️ | `Info.plist:33` 평문, 번들 ID 제한 미설정 |
| No secrets in backend source | ✅ | `rg` 패턴 이상 없음 |
| .env.example | N/A | Cloudflare는 wrangler secrets 사용 |

### iOS / CocoaPods
| Check | Status | Evidence |
|-------|--------|----------|
| Podfile.lock 존재 | ✅ | 확인됨 |
| Pods/ gitignored | ❌ | 279개 파일 추적 중 |
| .gitignore | ❌ | 부재 |
| NSAllowsArbitraryLoads | ❌ | `Info.plist:24` true |
| LaunchScreen 등록 | ✅ | `Base.lproj/LaunchScreen.storyboard` staged |

### Node.js / Cloudflare Workers
| Check | Status | Evidence |
|-------|--------|----------|
| package-lock.json | ✅ | 존재 |
| tsconfig strict | ✅ | `"strict": true` |
| wrangler.toml 배포 설정 | ✅ | D1 바인딩 + workers.dev URL |
| backend .gitignore | ⚠️ | 없음 (node_modules 추적 여부 확인 권장) |

### Database Migrations
| Check | Status | Evidence |
|-------|--------|----------|
| 순차 정렬 | ✅ | 0001, 0002 정상 |
| 롤백(down) | N/A | D1 마이그레이션 구조상 별도 down 없음 |

### TODO / Debug
| Check | Status | Evidence |
|-------|--------|----------|
| TODO/FIXME | ✅ | 검색 결과 없음 |
| 디버그 print | ⚠️ | `AnimalBoardingService.swift:151` 1건 |
| localhost/127.0.0.1 | ✅ | API 호출은 HTTPS 공공 도메인 |

---

## Commands Run

- `ls deployment-readiness-report.md` / `ls docs/`
- `ls -la` (repo 루트)
- `git rev-parse --is-inside-work-tree` (루트 → git 아님)
- `git -C Dog_kindergarden rev-parse --is-inside-work-tree`
- `find . -maxdepth 3 -name ".git" -type d`
- `cat backend-cloudflare/wrangler.toml` / `package.json` / `tsconfig.json`
- `rg -n "serviceKey|let key|ServiceKey" …/AnimalBoardingService.swift`
- `ls .gitignore Dog_kindergarden/.gitignore`
- `git -C Dog_kindergarden status --short`
- `git ls-files Pods | wc -l`
- `rg -n "NSAllowsArbitraryLoads|KAKAO_NATIVE_APP_KEY" Dog_kindergarden/Info.plist`
- `git log @{u}..HEAD --oneline`
- `rg -l "^<<<<<<< |^>>>>>>> "`
- `sed -n '95,135p' …/AnimalBoardingService.swift`
- `rg -l "BoardingStore" Dog_kindergarden/`
- `rg -n "print\(|localhost|127.0.0.1" …/AnimalBoardingService.swift`
