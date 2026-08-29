# 공지사항 설계 — 앱 전체 공지, DB 직접 입력 (2026-08-29)

## 배경과 목적

마이페이지 "고객지원" 섹션의 "공지사항" 버튼은 현재 `action` 없이 눌러도 아무 반응이 없는 죽은 버튼이다(같은 섹션의 "1:1 문의" 버튼을 먼저 살렸다 — `docs/superpowers/specs/2026-08-29-1on1-inquiry-design.md`). 이를 살려 개발자(운영자)가 점검 안내·신규 기능 출시 같은 공지를 올리고, 모든 사용자(견주+사장님)가 마이페이지에서 확인할 수 있게 한다.

기존 코드베이스에 "공지사항"과 관련된 기반(데이터 모델, 백엔드 라우트, 문서 언급)은 전혀 없다 — 완전히 새로 설계한다.

## 핵심 결정

- **공지 범위: 앱 전체(개발자 → 모든 사용자).** 가게별 공지(사장님 → 자기 가게 고객)는 다루지 않는다 — 필요해지면 `stores.owner_id` 개념을 확장해 별도로 설계한다.
- **작성 방법: curl/wrangler로 DB에 직접 INSERT.** 앱 안에 작성 화면을 만들지 않는다. "1:1 문의" 설계의 가게 claim curl과 같은 패턴 — 가끔 올리는 콘텐츠에 전용 UI·권한 체계를 새로 만드는 건 과한 설계라 채택하지 않는다.
- **안 읽음 추적 없음.** 홈 종 아이콘 배지에 합산하지 않는다. 마이페이지 진입 시 목록만 보여준다 — `notice_reads` 같은 추적 테이블을 두지 않아 백엔드·iOS 양쪽 다 단순해진다.
- **화면 구성: 목록 → 상세 2단계.** 앱스토어형 공지사항 UX와 동일. 리스트 항목을 탭하면 상세 화면으로 이동한다.
- **화면 전환은 기존 `AppRouter` 전역 스택 패턴을 따른다.** 이 프로젝트는 `NavigationStack`을 쓰지 않고 `AppRouter.stack`(화면 enum 배열)을 통해서만 화면을 전환한다(CLAUDE.md). 로컬 `@State`+`.sheet()`로 상세를 표시하는 대안도 가능하지만, 프로젝트 전체의 일관된 관례를 벗어나므로 채택하지 않는다.

## 데이터 모델 (백엔드, 신규)

```sql
CREATE TABLE notices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

- `user_id` 컬럼 없음 — 사용자 스코프가 없는 전역 콘텐츠.
- 안 읽음 추적 테이블 없음(위 핵심 결정).
- 마이그레이션 파일 번호는 구현 시점의 최신 번호 다음으로 부여한다(이 문서 작성 시점에 고정하지 않음 — `backend-cloudflare/migrations/`의 최신 번호를 구현 직전에 확인).

## 백엔드 API

`backend-cloudflare/src/index.ts`에 라우트만 추가한다(기존 단일 파일 Hono 앱 구조 유지).

- `GET /api/notices` — 목록용. `id, title, created_at`만 반환(본문 제외, 페이로드 최소화). `created_at DESC` 정렬.
- `GET /api/notices/:id` — 단건 상세. `id, title, body, created_at` 전체 반환.
- 작성/수정/삭제 API는 만들지 않는다 — DB 직접 INSERT로 결정했으므로 쓰기 라우트는 불필요(YAGNI).

## iOS 구현

- **신규 파일**: `Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeListView.swift`, `Dog_kindergarden/Dog_kindergarden/Views/MyPage/NoticeDetailView.swift` — 화면당 파일 하나(기존 `ChatListView.swift`/`ChatRoomView.swift`와 동일한 분리 관례).
- **`AppRouter`**: `AppScreen`에 `.noticeList`, `.noticeDetail` 케이스 추가. `selectedNotice: Notice?` 프로퍼티 추가 — 목록에서 탭한 항목(제목+생성일만 있는 요약)을 상세 화면에 넘겨, 상세 화면이 다시 `id`로 본문을 받아온다.
- **`APIClient`**: `fetchNotices() async -> [Notice]`, `fetchNotice(id:) async -> Notice?` 추가. `Notice` 모델은 목록 응답(`id, title, created_at`)과 상세 응답(`id, title, body, created_at`)을 모두 담을 수 있게 `body`를 옵셔널로 둔다.
- **`MyPageView`**: "공지사항" `MyPageItem`에 `{ router.go(.noticeList) }` 연결.

## 동작 흐름

1. 사용자가 마이페이지 "공지사항" 탭 → `NoticeListView` 진입 → `GET /api/notices` 호출해 목록 표시(제목+날짜).
2. 항목 탭 → `router.selectedNotice`에 요약 정보 저장 → `router.go(.noticeDetail)`.
3. `NoticeDetailView` 진입 시 `GET /api/notices/:id`로 본문을 받아와 표시.
4. 개발자가 새 공지를 올리고 싶으면 `npx wrangler d1 execute dog_kindergarden_db --remote --command "INSERT INTO notices (title, body) VALUES (...)"`를 1회 실행 — 앱 재배포 불필요, 즉시 모든 사용자에게 노출.

## 에러 처리

- 목록 조회 실패: 에러 문구 + 재시도 버튼(기존 다른 목록 화면과 동일 패턴).
- 목록이 비어있을 때: "등록된 공지사항이 없습니다" 같은 빈 상태 문구.
- 상세 조회 실패(예: 목록 로드 후 삭제된 경우): 에러 문구 표시, 목록으로 돌아가기 유도.

## 테스트 방법

- 백엔드: 마이그레이션 적용 후 `curl`로 수동 INSERT 1건 → `GET /api/notices`, `GET /api/notices/:id` 응답이 기대한 필드로 오는지 확인.
- iOS: 빌드 성공 확인(자동) 후, 시뮬레이터에서 마이페이지 → 공지사항 → 목록 → 상세 진입까지 사람이 직접 확인(스크린샷).
