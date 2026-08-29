# 공지사항 기능 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 마이페이지의 죽어있는 "공지사항" 버튼을 활성화해, 개발자가 DB에 직접 입력한 공지를 모든 사용자가 목록→상세로 확인할 수 있게 한다.

**Architecture:** 백엔드에 `user_id` 없는 전역 `notices` 테이블 1개와 GET 라우트 2개(목록/상세)만 추가한다. iOS는 기존 `AppRouter` 전역 스택 패턴으로 목록→상세 2단계 화면을 새로 만들고, `APIClient`에 조회 메서드 2개를 추가해 연결한다. 작성/수정/삭제 API는 만들지 않는다 — curl/wrangler로 DB에 직접 INSERT해서 운영한다.

**Tech Stack:** Swift 5.9 / SwiftUI(iOS), 기존 `AppRouter`/`APIClient` 패턴 재사용. 백엔드는 Hono + Cloudflare D1, 신규 마이그레이션 1개 + GET 라우트 2개.

## Global Constraints

- `notices` 테이블 스키마는 스펙에 고정된 그대로다: `id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now'))` — `user_id` 컬럼 없음, 읽음 추적 테이블 없음(`docs/superpowers/specs/2026-08-29-notice-board-design.md`).
- 마이그레이션 파일은 `backend-cloudflare/migrations/0017_notices.sql`이다. 이 계획 작성 시점(2026-08-29) 기준 최신 마이그레이션은 `0016_stores_category.sql`이라 0017이 다음 번호다 — 실행 직전 `ls backend-cloudflare/migrations | sort | tail -3`로 번호가 바뀌지 않았는지 재확인한다.
- 작성/수정/삭제 라우트는 만들지 않는다(YAGNI — DB 직접 INSERT로 운영하기로 결정됨).
- `GET /api/notices`는 목록용으로 `id, title, created_at`만 반환(본문 제외), `created_at DESC` 정렬. `GET /api/notices/:id`는 `id, title, body, created_at` 전체를 반환하고, 없으면 404.
- iOS는 `NavigationStack`을 쓰지 않는다 — 기존 `AppRouter.stack` 전역 스택 패턴만 사용한다(CLAUDE.md).
- 화면당 파일 하나 관례를 따른다: `NoticeListView.swift`, `NoticeDetailView.swift`로 분리한다(기존 `ChatListView.swift`/`ChatRoomView.swift`와 동일한 관례).
- 커밋은 **실행자가 직접 `git add`/`git commit`을 실행하지 않는다** — 각 커밋 단계에서 정확한 명령어를 사용자에게 보여주고, 사용자가 자신의 터미널에서 직접 실행하도록 한다(이 프로젝트에서 확립된 규칙 — 서브에이전트의 git commit은 이 환경의 권한 시스템이 실제로 거부한다).
- iOS 빌드는 워크스페이스로: `xcodebuild -workspace Dog_kindergarden.xcworkspace -scheme Dog_kindergarden -destination 'platform=iOS Simulator,id=797D6EB2-6339-4855-B755-09EB8815A147' -derivedDataPath build build` (`Dog_kindergarden/` 디렉터리에서 실행, `.xcodeproj`가 아닌 워크스페이스로 열 것 — CLAUDE.md). 이 destination(iPhone 17, OS 26.5)이 없으면 `xcrun simctl list devices available | rg "iPhone"`로 사용 가능한 iPhone 시뮬레이터의 UDID를 확인해 대체한다.
- 시뮬레이터 터치 자동화(osascript/System Events)는 이 환경에서 신뢰할 수 없는 것으로 이전 세션에서 확인됨 — 콜드 런치 시점에 보이는 화면은 스크린샷만으로 검증 가능하지만, 탭 이동이 필요한 화면(마이페이지 → 공지사항 → 목록 → 상세)은 사람이 시뮬레이터에서 직접 탭한 뒤 스크린샷으로 확인해야 한다. 자동 검증이 불가능한 단계는 그렇다고 명시하고 사람에게 확인을 요청한다.
- 백엔드 테스트/린트 인프라는 없음 — 타입 검사는 `npx tsc --noEmit`(backend-cloudflare/에서), 기능 검증은 수동 curl로 한다(CLAUDE.md).

---

## File Structure

- **Create**: `backend-cloudflare/migrations/0017_notices.sql` — `notices` 테이블 생성.
- **Modify**: `backend-cloudflare/src/index.ts` — `GET /api/notices`, `GET /api/notices/:id` 라우트 추가.
- **Create**: `Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeListView.swift` — 목록 화면.
- **Create**: `Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeDetailView.swift` — 상세 화면.
- **Modify**: `Dog_kindergarden/Dog_kindergarden/Views/Navigation/AppRouter.swift` — `AppScreen`에 `.noticeList`/`.noticeDetail` 케이스 추가, `selectedNotice: Notice?` 프로퍼티 추가.
- **Modify**: `Dog_kindergarden/Dog_kindergarden/APIClient.swift` — `Notice` 모델 + `fetchNotices()`/`fetchNotice(id:)` 추가.
- **Modify**: `Dog_kindergarden/Dog_kindergarden/Views/RootView.swift` — switch에 `.noticeList`/`.noticeDetail` 분기 추가.
- **Modify**: `Dog_kindergarden/Dog_kindergarden/Views/MyPage/MyPageView.swift` — "공지사항" 버튼에 action 연결.

---

### Task 1: 백엔드 — notices 테이블 + 조회 API

**Files:**
- Create: `backend-cloudflare/migrations/0017_notices.sql`
- Modify: `backend-cloudflare/src/index.ts`

**Interfaces:**
- Consumes: 없음(신규 테이블, 신규 라우트).
- Produces:
  - `GET /api/notices` → JSON 배열 `[{id: number, title: string, created_at: string}]`, `created_at DESC` 정렬
  - `GET /api/notices/:id` → `{id: number, title: string, body: string, created_at: string}`, 없으면 `{message: "notice not found"}` 404
  - 이 두 라우트를 Task 2의 iOS `APIClient.fetchNotices()`/`fetchNotice(id:)`가 그대로 소비한다.

- [ ] **Step 1: 마이그레이션 파일 작성**

`backend-cloudflare/migrations/0017_notices.sql`:

```sql
-- 앱 전체 공지사항 — 개발자가 DB에 직접 INSERT해서 운영(앱 내 작성 화면 없음)
CREATE TABLE IF NOT EXISTS notices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

- [ ] **Step 2: 로컬 D1에 마이그레이션 적용**

`backend-cloudflare/` 디렉터리에서:

```bash
npm run d1:migrate
```

Expected: `0017_notices.sql` 적용 로그가 출력되고 에러 없음.

- [ ] **Step 3: `GET /api/notices`, `GET /api/notices/:id` 라우트 추가**

`backend-cloudflare/src/index.ts`에서 `app.get("/api/stores", ...)` 라우트(약 235번째 줄) 앞에 추가:

```typescript
// 공지사항 목록 — 본문 제외, 최신순
app.get("/api/notices", async (c) => {
  const { results } = await c.env.DB.prepare(
    `SELECT id, title, created_at FROM notices ORDER BY created_at DESC`,
  ).all();
  return c.json(results);
});

// 공지사항 상세
app.get("/api/notices/:id", async (c) => {
  const id = Number(c.req.param("id"));
  const notice = await c.env.DB.prepare(
    `SELECT id, title, body, created_at FROM notices WHERE id = ?`,
  )
    .bind(id)
    .first();
  if (!notice) return c.json({ message: "notice not found" }, 404);
  return c.json(notice);
});
```

- [ ] **Step 4: 타입 검사**

`backend-cloudflare/` 디렉터리에서:

```bash
npx tsc --noEmit
```

Expected: 에러 없음.

- [ ] **Step 5: 로컬 서버로 수동 검증**

`backend-cloudflare/` 디렉터리에서:

```bash
npm run dev &
sleep 2
npx wrangler d1 execute dog_kindergarden_db --local \
  --command "INSERT INTO notices (title, body) VALUES ('테스트 공지', '테스트 본문입니다.')"
curl -s http://localhost:8787/api/notices
curl -s http://localhost:8787/api/notices/1
kill %1
```

Expected: 첫 curl 응답이 `[{"id":1,"title":"테스트 공지","created_at":"..."}]` 형태(본문 없음), 둘째 curl 응답이 `{"id":1,"title":"테스트 공지","body":"테스트 본문입니다.","created_at":"..."}` 형태(본문 포함). `npm run dev` 출력에 표시되는 실제 리스닝 포트가 8787과 다르면 그 포트를 사용한다.

- [ ] **Step 6: 커밋 (실행자는 명령어만 제시, 직접 실행하지 않음)**

```bash
git add backend-cloudflare/migrations/0017_notices.sql backend-cloudflare/src/index.ts
git commit -m "$(cat <<'EOF'
feat: 공지사항 백엔드 — notices 테이블 + GET /api/notices, GET /api/notices/:id

EOF
)"
```

---

### Task 2: iOS — 공지사항 목록/상세 화면

**Files:**
- Create: `Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeListView.swift`
- Create: `Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeDetailView.swift`
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/Navigation/AppRouter.swift`
- Modify: `Dog_kindergarden/Dog_kindergarden/APIClient.swift`
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/RootView.swift`
- Modify: `Dog_kindergarden/Dog_kindergarden/Views/MyPage/MyPageView.swift:182`

**Interfaces:**
- Consumes:
  - Task 1의 `GET /api/notices`, `GET /api/notices/:id` — 시뮬레이터에서 실데이터로 확인하려면 Task 1이 배포(`npm run deploy`)돼 있어야 한다(`APIClient.baseURL` 기본값이 배포 Workers URL).
  - `AppRouter.go(_:)`, `AppRouter.back()` — 기존 메서드, `Dog_kindergarden/Dog_kindergarden/Views/Navigation/AppRouter.swift`
  - `MyPageItem(icon: String, label: String, badge: String? = nil, bg: Color = Color.brandCream, action: (() -> Void)? = nil)` — `MyPageView.swift:331`
  - `.safeAreaTopPadding()` — 기존 커스텀 modifier(`SafeAreaKey.swift`), nav bar 상단 여백에 사용
  - `EmojiIcon(emoji: String, size: CGFloat)` — 기존 뷰, 빈 상태/에러 상태 아이콘에 사용(`FavoritesView.swift` 패턴과 동일)
- Produces:
  - `AppScreen.noticeList`, `AppScreen.noticeDetail` — `RootView`의 switch가 이 케이스로 각 화면을 렌더링
  - `AppRouter.selectedNotice: Notice?` — 목록에서 상세로 넘길 때 세팅
  - `APIClient.shared.fetchNotices() async throws -> [Notice]`
  - `APIClient.shared.fetchNotice(id: Int) async throws -> Notice?`
  - `Notice` 구조체(Decodable, Identifiable) — `id: Int, title: String, createdAt: String, body: String?`

- [ ] **Step 1: `APIClient.swift`에 `Notice` 모델과 조회 메서드 추가**

`Dog_kindergarden/Dog_kindergarden/APIClient.swift`의 `fetchStores()` 메서드(133-136번째 줄) 바로 아래에 추가:

```swift
// 공지사항 — 목록은 본문 제외, 상세는 본문 포함(body가 nil이면 목록에서 온 요약)
func fetchNotices() async throws -> [Notice] {
    try await request(path: "/notices", method: "GET")
}

func fetchNotice(id: Int) async throws -> Notice? {
    try await request(path: "/notices/\(id)", method: "GET")
}
```

파일 하단(`StoreDetailResponse` 구조체, 345-362번째 줄) 바로 아래에 모델 추가:

```swift
struct Notice: Decodable, Identifiable {
    let id: Int
    let title: String
    let createdAt: String
    let body: String?
}
```

- [ ] **Step 2: `AppRouter.swift`에 화면 케이스와 프로퍼티 추가**

`Dog_kindergarden/Dog_kindergarden/Views/Navigation/AppRouter.swift`의 `AppScreen` enum(4-22번째 줄) 마지막 케이스를 변경:

```swift
// 변경 전
    case diary
}

// 변경 후
    case diary
    case noticeList
    case noticeDetail
}
```

`AppRouter` 클래스의 `diaryContext` 프로퍼티(62번째 줄) 바로 아래에 추가:

```swift
    var selectedNotice: Notice? = nil      // 공지사항 목록에서 탭한 항목 — 상세 화면에 전달
```

- [ ] **Step 3: `RootView.swift`에 화면 분기 추가**

`Dog_kindergarden/Dog_kindergarden/Views/RootView.swift`의 switch문에서 (84번째 줄 근처):

```swift
// 변경 전
        case .diary:       DiaryTimelineView()
        }

// 변경 후
        case .diary:       DiaryTimelineView()
        case .noticeList:  NoticeListView()
        case .noticeDetail: NoticeDetailView()
        }
```

- [ ] **Step 4: `NoticeListView.swift` 작성**

`Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeListView.swift` 신규 생성:

```swift
import SwiftUI

// 공지사항 목록 — 개발자가 DB에 직접 입력한 공지를 최신순으로 표시
struct NoticeListView: View {
    @Environment(AppRouter.self) private var router

    @State private var notices: [Notice] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navBar
                if isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if loadFailed {
                    errorState
                } else if notices.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(notices) { notice in
                            noticeCard(notice)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task { await load() }
    }

    // MARK: - Nav

    private var navBar: some View {
        HStack(spacing: 12) {
            Button(action: router.back) {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                    .overlay(Image(systemName: "chevron.left").font(.system(size: 15)).foregroundStyle(Color.brandBrown))
            }
            Text("공지사항")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    // MARK: - Empty / Error

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "📢", size: 48)
            Text("등록된 공지사항이 없습니다")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .padding(.top, 100)
    }

    private var errorState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "⚠️", size: 48)
            Text("공지사항을 불러오지 못했어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Button(action: { Task { await load() } }) {
                Text("다시 시도")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.brandOrange)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 100)
    }

    // MARK: - Card

    private func noticeCard(_ notice: Notice) -> some View {
        Button(action: { open(notice) }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                        .multilineTextAlignment(.leading)
                    Text(notice.createdAt)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.brandBrownMid)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrownLight)
            }
            .padding(14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            notices = try await APIClient.shared.fetchNotices()
        } catch {
            loadFailed = true
        }
    }

    private func open(_ notice: Notice) {
        router.selectedNotice = notice
        router.go(.noticeDetail)
    }
}
```

- [ ] **Step 5: `NoticeDetailView.swift` 작성**

`Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeDetailView.swift` 신규 생성:

```swift
import SwiftUI

// 공지사항 상세 — 목록에서 넘어온 id로 본문을 다시 조회
struct NoticeDetailView: View {
    @Environment(AppRouter.self) private var router

    @State private var notice: Notice?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navBar
                if isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if loadFailed || notice == nil {
                    errorState
                } else if let notice {
                    content(notice)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task { await load() }
    }

    // MARK: - Nav

    private var navBar: some View {
        HStack(spacing: 12) {
            Button(action: router.back) {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                    .overlay(Image(systemName: "chevron.left").font(.system(size: 15)).foregroundStyle(Color.brandBrown))
            }
            Text("공지사항")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    // MARK: - Content / Error

    private func content(_ notice: Notice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(notice.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text(notice.createdAt)
                .font(.system(size: 11))
                .foregroundStyle(Color.brandBrownMid)
            Divider()
            Text(notice.body ?? "")
                .font(.system(size: 14))
                .foregroundStyle(Color.brandBrown)
                .multilineTextAlignment(.leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var errorState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "⚠️", size: 48)
            Text("공지사항을 불러오지 못했어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Button(action: router.back) {
                Text("목록으로")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.brandOrange)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 100)
    }

    // MARK: - Actions

    private func load() async {
        guard let id = router.selectedNotice?.id else {
            loadFailed = true
            isLoading = false
            return
        }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            notice = try await APIClient.shared.fetchNotice(id: id)
        } catch {
            loadFailed = true
        }
    }
}
```

- [ ] **Step 6: `MyPageView.swift`의 "공지사항" 버튼에 action 연결**

`Dog_kindergarden/Dog_kindergarden/Views/MyPage/MyPageView.swift:182`:

```swift
// 변경 전
MyPageItem(icon: "megaphone",         label: "공지사항")

// 변경 후
MyPageItem(icon: "megaphone",         label: "공지사항") { router.go(.noticeList) }
```

- [ ] **Step 7: 빌드해서 컴파일 확인**

`Dog_kindergarden/` 디렉터리에서 실행:

```bash
xcodebuild -workspace Dog_kindergarden.xcworkspace -scheme Dog_kindergarden \
  -destination 'platform=iOS Simulator,id=797D6EB2-6339-4855-B755-09EB8815A147' \
  -derivedDataPath build build
```

Expected: 마지막 줄에 `** BUILD SUCCEEDED **`. 이 destination이 없으면 Global Constraints에 명시된 방법으로 대체 UDID를 찾는다.

- [ ] **Step 8: 시뮬레이터에 설치·실행 후 수동으로 확인**

```bash
xcrun simctl boot 797D6EB2-6339-4855-B755-09EB8815A147 2>/dev/null
xcrun simctl install 797D6EB2-6339-4855-B755-09EB8815A147 \
  build/Build/Products/Debug-iphonesimulator/Dog_kindergarden.app
xcrun simctl launch 797D6EB2-6339-4855-B755-09EB8815A147 net.suyoung.Dog-kindergarden
open -a Simulator
```

Simulator.app이 열리면 사람이 직접: 로그인 → 홈 사이드바(FAB) → "마이페이지" → "고객지원" 섹션의 "공지사항" 탭. Task 1에서 curl로 넣은 테스트 공지가 목록에 보이는지, 탭했을 때 상세(본문 포함)로 이동하는지 확인한다. 실데이터로 확인하려면 Task 1이 배포(`npm run deploy`)돼 있어야 한다 — 로컬 wrangler dev만 돌린 상태라면 시뮬레이터 앱 내에서 `UserDefaults`의 `"API_BASE_URL"`을 로컬 주소로 임시 설정해야 한다.

확인용 스크린샷이 필요하면:

```bash
xcrun simctl io 797D6EB2-6339-4855-B755-09EB8815A147 screenshot /private/tmp/claude-501/-Users-suyoung-Documents-Dog-Kindergarden/2385f993-de78-45f8-881a-05b38f9180cd/scratchpad/notice-board.png
```

- [ ] **Step 9: 커밋 (실행자는 명령어만 제시, 직접 실행하지 않음)**

```bash
git add Dog_kindergarden/Dog_kindergarden/APIClient.swift \
  Dog_kindergarden/Dog_kindergarden/Views/Navigation/AppRouter.swift \
  Dog_kindergarden/Dog_kindergarden/Views/RootView.swift \
  Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeListView.swift \
  Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeDetailView.swift \
  Dog_kindergarden/Dog_kindergarden/Views/MyPage/MyPageView.swift
git commit -m "$(cat <<'EOF'
feat: 공지사항 iOS 목록/상세 화면 — 마이페이지 버튼 연결

EOF
)"
```

---

## Self-Review 기록

- **스펙 커버리지**: 핵심 결정(전역 공지 / curl INSERT로 운영 / 안 읽음 추적 없음 / 목록→상세 2단계 / `AppRouter` 패턴 준수) 모두 Global Constraints와 Task 구조에 반영됨. 데이터 모델 → Task 1 Step 1. 백엔드 API → Task 1 Step 3. iOS 구현(신규 파일 2개, `AppRouter`, `APIClient`, `MyPageView` 연결) → Task 2 전체. 동작 흐름 4단계(탭 → 목록 → 상세 → 개발자 INSERT) → Task 1 Step 5(INSERT) + Task 2 Step 4-6(화면 흐름). 에러 처리(목록 조회 실패+재시도, 빈 목록, 상세 조회 실패) → Task 2 Step 4의 `errorState`/`emptyState`, Step 5의 `errorState`. 테스트 방법(백엔드 curl, iOS 빌드+시뮬레이터 확인) → Task 1 Step 5, Task 2 Step 7-8.
- **플레이스홀더 스캔**: 모든 코드 블록이 완전한 실제 코드다. "TBD"/"구현 필요"/설명만 있고 코드가 없는 스텝 없음.
- **타입 일관성**: `Notice` 구조체(`id: Int, title: String, createdAt: String, body: String?`)가 `APIClient` 정의(Task 2 Step 1)와 `NoticeListView`/`NoticeDetailView`의 사용처(Step 4-5)에서 동일하게 쓰임. `AppRouter.selectedNotice: Notice?`, `AppScreen.noticeList`/`.noticeDetail` 네이밍이 `RootView`의 switch(Step 3)와 `MyPageView`의 `router.go(.noticeList)`(Step 6) 호출에서 일치. `fetchNotices()`/`fetchNotice(id:)`가 호출하는 경로(`/notices`, `/notices/\(id)`)가 Task 1의 라우트 경로(`/api/notices`, `/api/notices/:id` — `baseURL`이 이미 `/api`로 끝나므로 일치)와 맞음.
