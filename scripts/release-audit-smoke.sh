#!/usr/bin/env bash

# 맡겨멍 출시 후보의 실제 기기 투입 전 로컬 검증을 한 번에 실행한다.
# 운영 D1/Worker와 실제 계정에는 접근하지 않고 임시 D1만 사용한다.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend-cloudflare"
IOS_DIR="$REPO_ROOT/Dog_kindergarden"

RUN_BACKEND=1
RUN_IOS=1
QUICK=0

usage() {
  cat <<'EOF'
사용법: scripts/release-audit-smoke.sh [옵션]

옵션:
  --quick         iOS Release 빌드를 생략하고 정적 검사와 백엔드 회귀만 실행
  --backend-only  백엔드 검사만 실행(iOS 관련 검사는 건너뜀)
  --ios-only      iOS 정적 검사와 Release 빌드만 실행
  -h, --help      도움말 출력

환경변수:
  RESULT_DIR          로그와 Markdown 결과를 저장할 디렉터리(기본: /tmp 아래)
  RELEASE_SMOKE_PORT  로컬 Worker 포트(기본: 임의 포트)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1 ;;
    --backend-only) RUN_BACKEND=1; RUN_IOS=0 ;;
    --ios-only) RUN_BACKEND=0; RUN_IOS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RESULT_DIR="${RESULT_DIR:-/tmp/matgyeomung-release-smoke-$RUN_ID}"
WORK_DIR="$RESULT_DIR/work"
LOG_DIR="$RESULT_DIR/logs"
SUMMARY_FILE="$RESULT_DIR/summary.tsv"
REPORT_FILE="$RESULT_DIR/release-smoke-result.md"
PORT="${RELEASE_SMOKE_PORT:-$((18000 + RANDOM % 1000))}"
INTERNAL_KEY="release-smoke-local-only-key"
EXPECTED_MIN_IOS="17.0"
EXPECTED_DISPLAY_NAME="맡겨멍"
EXPECTED_APP_CATEGORY="public.app-category.lifestyle"
WORKER_PID=""
FAILURES=0
WARNINGS=0

mkdir -p "$WORK_DIR" "$LOG_DIR"
: > "$SUMMARY_FILE"

cleanup() {
  if [ -n "$WORKER_PID" ] && kill -0 "$WORKER_PID" 2>/dev/null; then
    kill "$WORKER_PID" 2>/dev/null || true
    wait "$WORKER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

record() {
  local id="$1"
  local status="$2"
  local title="$3"
  local log_path="$4"
  printf '%s\t%s\t%s\t%s\n' "$id" "$status" "$title" "$log_path" >> "$SUMMARY_FILE"
  printf '%-8s %-7s %s\n' "[$id]" "$status" "$title"
  case "$status" in
    FAIL) FAILURES=$((FAILURES + 1)) ;;
    WARN) WARNINGS=$((WARNINGS + 1)) ;;
  esac
}

run_command() {
  local id="$1"
  local title="$2"
  shift 2
  local log="$LOG_DIR/$id.log"
  if "$@" >"$log" 2>&1; then
    record "$id" PASS "$title" "$log"
    return 0
  fi
  record "$id" FAIL "$title" "$log"
  return 1
}

skip() {
  record "$1" SKIP "$2" "-"
}

check_tools() {
  local missing=0
  local tool
  for tool in git node npm npx curl; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "필수 도구 없음: $tool"
      missing=1
    fi
  done
  if [ "$RUN_IOS" -eq 1 ]; then
    if ! command -v /usr/bin/plutil >/dev/null 2>&1; then
      echo "필수 도구 없음: /usr/bin/plutil"
      missing=1
    fi
  fi
  if [ "$RUN_IOS" -eq 1 ] && [ "$QUICK" -eq 0 ]; then
    for tool in xcodebuild /usr/libexec/PlistBuddy; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "iOS 검사 도구 없음: $tool"
        missing=1
      fi
    done
  fi
  return "$missing"
}

check_repository_state() {
  cd "$REPO_ROOT" || return 1
  echo "commit=$(git rev-parse HEAD)"
  echo "branch=$(git branch --show-current)"
  if [ -n "$(git status --porcelain)" ]; then
    echo "주의: 작업 트리가 깨끗하지 않습니다. 아래 변경도 검사 대상에 포함됩니다."
    git status --short
  else
    echo "작업 트리: clean"
  fi
}

check_tracked_sensitive_files() {
  cd "$REPO_ROOT" || return 1
  local found=0
  local path
  while IFS= read -r path; do
    case "$path" in
      *.p8|*.p12|*.mobileprovision|*.cer|*.key|*.pem|*/.env|*/.dev.vars|.env|.dev.vars)
        echo "민감 파일이 Git에 추적됨: $path"
        found=1
        ;;
    esac
  done < <(git ls-files)
  return "$found"
}

validate_app_icon() {
  cd "$REPO_ROOT" || return 1
  node scripts/validate-app-icon.mjs
}

validate_privacy_declarations() {
  cd "$REPO_ROOT" || return 1
  node scripts/validate-privacy-declarations.mjs
}

check_ios_server_secrets() {
  cd "$REPO_ROOT" || return 1
  local files pattern
  pattern='^[[:space:]]*(NAVER_CLIENT_ID|NAVER_CLIENT_SECRET|KAKAO_REST_API_KEY|DATA_GO_KR_SERVICE_KEY)[[:space:]]*=[[:space:]]*[^$\[(]'
  files="$(find "$IOS_DIR" -path "$IOS_DIR/Pods" -prune -o -name '*.xcconfig' -type f -print0 \
    | xargs -0 grep -IlE "$pattern" 2>/dev/null || true)"
  if [ -n "$files" ]; then
    echo "Release 번들에 포함될 수 있는 서버용 API 자격 증명 발견:"
    printf '%s\n' "$files"
    echo "값은 보안을 위해 출력하지 않았습니다. Worker Secret만 사용해야 합니다."
    return 1
  fi
  if grep -Eq '<key>(NAVER_CLIENT_ID|NAVER_CLIENT_SECRET|KAKAO_REST_API_KEY|DATA_GO_KR_SERVICE_KEY)</key>' \
    "$IOS_DIR/Dog_kindergarden/Info.plist"; then
    echo "iOS Info.plist에 서버용 API 키 항목이 남아 있습니다."
    return 1
  fi
  echo "iOS 설정에서 서버용 Naver·Kakao REST·공공데이터 자격 증명을 찾지 못했습니다."
}

check_repository_consistency() {
  cd "$REPO_ROOT" || return 1
  if git ls-files --error-unmatch Dog_kindergarden/All_data.csv >/dev/null 2>&1; then
    echo "경고: docs/PLAN.md에서 재확인을 요구한 Dog_kindergarden/All_data.csv가 Git에 남아 있습니다."
    return 2
  fi
  echo "Dog_kindergarden/All_data.csv는 Git 추적 대상이 아닙니다."
}

backend_dry_run() {
  cd "$BACKEND_DIR" || return 1
  WRANGLER_LOG_PATH="$LOG_DIR/wrangler-debug.log" \
    npx wrangler deploy --dry-run --outdir "$WORK_DIR/worker-dry-run"
}

backend_migrations() {
  cd "$BACKEND_DIR" || return 1
  CI=1 WRANGLER_LOG_PATH="$LOG_DIR/wrangler-debug.log" \
    npx wrangler d1 migrations apply dog_kindergarden_db \
    --local \
    --persist-to "$WORK_DIR/d1"
}

start_worker() {
  local log="$LOG_DIR/B04-worker.log"
  local env_file="$WORK_DIR/release-smoke.env"

  # 개발자 로컬의 .dev.vars 유무에 따라 회귀 결과가 달라지지 않도록
  # 출시 점검 전용 환경 파일만 명시적으로 로드한다. 외부 API Secret은
  # 의도적으로 넣지 않아 Secret 미설정(503) 경로를 항상 검증한다.
  umask 077
  cat > "$env_file" <<EOF
ALLOW_DEV_AUTH=true
INTERNAL_API_KEY=$INTERNAL_KEY
EOF
  (
    cd "$BACKEND_DIR" || exit 1
    exec env WRANGLER_LOG_PATH="$LOG_DIR/wrangler-debug.log" npx wrangler dev \
      --local \
      --persist-to "$WORK_DIR/d1" \
      --port "$PORT" \
      --env-file "$env_file"
  ) >"$log" 2>&1 &
  WORKER_PID=$!

  local count=0
  while [ "$count" -lt 60 ]; do
    if ! kill -0 "$WORKER_PID" 2>/dev/null; then
      echo "로컬 Worker가 준비 전에 종료됐습니다."
      return 1
    fi
    if curl --silent --show-error --fail "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
      echo "로컬 Worker 준비 완료: 127.0.0.1:$PORT"
      return 0
    fi
    count=$((count + 1))
    sleep 1
  done
  echo "로컬 Worker 준비 시간 초과"
  return 1
}

backend_regression() {
  cd "$BACKEND_DIR" || return 1
  API_BASE_URL="http://127.0.0.1:$PORT" \
    INTERNAL_API_KEY="$INTERNAL_KEY" \
    npm run test:auth
}

ios_release_build() {
  cd "$IOS_DIR" || return 1
  xcodebuild \
    -workspace Dog_kindergarden.xcworkspace \
    -scheme Dog_kindergarden \
    -configuration Release \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$WORK_DIR/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

ios_release_bundle_gate() {
  local app
  app="$(find "$WORK_DIR/DerivedData/Build/Products" -type d -path '*Release-iphonesimulator/*.app' -print -quit 2>/dev/null)"
  if [ -z "$app" ]; then
    echo "검사할 Release .app을 찾지 못했습니다."
    return 1
  fi

  local failed=0
  local key value
  for key in NAVER_CLIENT_ID NAVER_CLIENT_SECRET KAKAO_REST_API_KEY DATA_GO_KR_SERVICE_KEY; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/Info.plist" 2>/dev/null || true)"
    if [ -n "$value" ]; then
      echo "Release 앱 Info.plist에 금지된 $key 항목이 포함되어 있습니다(값은 출력하지 않음)."
      failed=1
    fi
  done
  if [ "$failed" -eq 0 ]; then
    echo "Release 앱 Info.plist에 서버용 API 자격 증명이 없습니다."
  fi

  local executable
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist" 2>/dev/null || true)"
  if [ -n "$executable" ] && [ -f "$app/$executable" ]; then
    if strings "$app/$executable" | grep -Eq '개발자 진입|운영자 진입'; then
      echo "Release 실행 파일에서 개발용 진입 문구를 발견했습니다."
      failed=1
    else
      echo "Release 실행 파일에서 개발용 진입 문구를 찾지 못했습니다."
    fi
  else
    echo "Release 실행 파일을 찾지 못해 디버그 진입 문구를 검사할 수 없습니다."
    failed=1
  fi
  return "$failed"
}

ios_app_source_warning_gate() {
  local build_log="$LOG_DIR/I01.log"
  if [ ! -f "$build_log" ]; then
    echo "iOS Release 빌드 로그를 찾지 못했습니다: $build_log"
    return 1
  fi

  local source_prefix="$IOS_DIR/Dog_kindergarden/"
  local warnings
  warnings="$(awk -v prefix="$source_prefix" '
    index($0, prefix) == 1 && $0 ~ /:[0-9]+:[0-9]+: warning:/ { print }
  ' "$build_log")"

  if [ -n "$warnings" ]; then
    echo "맡겨멍 앱 소스에서 Release 컴파일러 경고를 발견했습니다:"
    printf '%s\n' "$warnings"
    echo "Pods·Xcode 도구 경고는 이 검사에서 제외합니다."
    return 1
  fi

  echo "맡겨멍 앱 소스의 Release 컴파일러 경고가 없습니다."
  echo "Pods·Xcode 도구 경고는 앱 소스 경고와 분리해 관리합니다."
}

ios_minimum_version_gate() {
  local app
  app="$(find "$WORK_DIR/DerivedData/Build/Products" -type d -path '*Release-iphonesimulator/*.app' -print -quit 2>/dev/null)"
  if [ -z "$app" ]; then
    echo "검사할 Release .app을 찾지 못했습니다."
    return 1
  fi

  local minimum_os
  minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist" 2>/dev/null || true)"
  if [ "$minimum_os" != "$EXPECTED_MIN_IOS" ]; then
    echo "Release 앱 최소 지원 버전이 예상과 다릅니다: ${minimum_os:-미설정} (예상: $EXPECTED_MIN_IOS)"
    echo "의도하지 않은 지원 기기 축소를 막기 위해 배포를 중단합니다."
    return 1
  fi

  echo "Release 앱 최소 지원 버전 확인: iOS $minimum_os"
}

ios_store_identity_gate() {
  local app
  app="$(find "$WORK_DIR/DerivedData/Build/Products" -type d -path '*Release-iphonesimulator/*.app' -print -quit 2>/dev/null)"
  if [ -z "$app" ]; then
    echo "검사할 Release .app을 찾지 못했습니다."
    return 1
  fi

  local display_name category failed
  display_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$app/Info.plist" 2>/dev/null || true)"
  category="$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$app/Info.plist" 2>/dev/null || true)"
  failed=0

  if [ "$display_name" != "$EXPECTED_DISPLAY_NAME" ]; then
    echo "Release 앱 표시 이름 불일치: ${display_name:-미설정} (예상: $EXPECTED_DISPLAY_NAME)"
    failed=1
  else
    echo "Release 앱 표시 이름 확인: $display_name"
  fi

  if [ "$category" != "$EXPECTED_APP_CATEGORY" ]; then
    echo "Release 앱 카테고리 불일치: ${category:-미설정} (예상: $EXPECTED_APP_CATEGORY)"
    failed=1
  else
    echo "Release 앱 카테고리 확인: $category"
  fi

  return "$failed"
}

ios_privacy_manifest_gate() {
  local app bundled_manifest source_manifest
  app="$(find "$WORK_DIR/DerivedData/Build/Products" -type d -path '*Release-iphonesimulator/*.app' -print -quit 2>/dev/null)"
  if [ -z "$app" ]; then
    echo "검사할 Release .app을 찾지 못했습니다."
    return 1
  fi

  bundled_manifest="$app/PrivacyInfo.xcprivacy"
  source_manifest="$IOS_DIR/Dog_kindergarden/PrivacyInfo.xcprivacy"
  if [ ! -f "$bundled_manifest" ]; then
    echo "Release 앱 루트에 PrivacyInfo.xcprivacy가 없습니다."
    return 1
  fi
  if ! cmp -s "$source_manifest" "$bundled_manifest"; then
    echo "Release 앱의 PrivacyInfo.xcprivacy가 소스 선언과 다릅니다."
    return 1
  fi

  node "$REPO_ROOT/scripts/validate-privacy-declarations.mjs" "$bundled_manifest"
  echo "Release 앱 루트 Privacy Manifest 포함 및 소스 일치 확인"
}

ios_permission_declarations_gate() {
  local app info_plist full_access_description background_mode background_identifier failed key
  app="$(find "$WORK_DIR/DerivedData/Build/Products" -type d -path '*Release-iphonesimulator/*.app' -print -quit 2>/dev/null)"
  if [ -z "$app" ]; then
    echo "검사할 Release .app을 찾지 못했습니다."
    return 1
  fi

  info_plist="$app/Info.plist"
  failed=0
  full_access_description="$(/usr/libexec/PlistBuddy -c 'Print :NSCalendarsFullAccessUsageDescription' "$info_plist" 2>/dev/null || true)"
  if [ -z "$full_access_description" ]; then
    echo "캘린더 전체 접근 설명이 없습니다."
    failed=1
  else
    echo "캘린더 전체 접근 설명 확인"
  fi

  for key in NSCalendarsUsageDescription NSCalendarsWriteOnlyAccessUsageDescription NSCameraUsageDescription NSPhotoLibraryUsageDescription NSLocationWhenInUseUsageDescription NSLocationAlwaysAndWhenInUseUsageDescription; do
    if /usr/libexec/PlistBuddy -c "Print :$key" "$info_plist" >/dev/null 2>&1; then
      echo "현재 기능에서 사용하지 않는 권한 설명이 남아 있습니다: $key"
      failed=1
    fi
  done

  background_mode="$(/usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes:0' "$info_plist" 2>/dev/null || true)"
  background_identifier="$(/usr/libexec/PlistBuddy -c 'Print :BGTaskSchedulerPermittedIdentifiers:0' "$info_plist" 2>/dev/null || true)"
  if [ "$background_mode" != "fetch" ]; then
    echo "알림 피드 갱신용 Background Fetch 선언이 없습니다."
    failed=1
  elif /usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes:1' "$info_plist" >/dev/null 2>&1; then
    echo "검토되지 않은 추가 Background Mode가 선언되어 있습니다."
    failed=1
  else
    echo "실사용 Background Fetch 선언 확인"
  fi
  if [ "$background_identifier" != "net.suyoung.Dog-kindergarden.refresh" ]; then
    echo "BGTask 식별자가 앱 코드와 다릅니다: ${background_identifier:-미설정}"
    failed=1
  elif /usr/libexec/PlistBuddy -c 'Print :BGTaskSchedulerPermittedIdentifiers:1' "$info_plist" >/dev/null 2>&1; then
    echo "검토되지 않은 추가 BGTask 식별자가 선언되어 있습니다."
    failed=1
  else
    echo "BGTask 식별자 일치 확인: $background_identifier"
  fi

  return "$failed"
}

write_report() {
  local commit branch generated overall
  commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  branch="$(git -C "$REPO_ROOT" branch --show-current)"
  generated="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  if [ "$FAILURES" -eq 0 ]; then overall="PASS"; else overall="FAIL"; fi

  {
    echo "# 로컬 Release Smoke 결과"
    echo
    echo "- 실행 시각: $generated"
    echo "- Git 브랜치: \`$branch\`"
    echo "- Git 커밋: \`$commit\`"
    echo "- 종합 결과: **$overall**"
    echo "- 실패: ${FAILURES}건"
    echo "- 경고: ${WARNINGS}건"
    echo "- 결과 경로: \`$RESULT_DIR\`"
    echo
    echo "## 자동 검사"
    echo
    echo "| ID | 결과 | 항목 | 로그 |"
    echo "|---|---|---|---|"
    while IFS=$'\t' read -r id status title log_path; do
      if [ "$log_path" = "-" ]; then
        echo "| $id | $status | $title | - |"
      else
        echo "| $id | $status | $title | \`$log_path\` |"
      fi
    done < "$SUMMARY_FILE"
    echo
    echo "## 판정 범위"
    echo
    echo "이 결과는 로컬 정적 검사, 임시 D1 기반 API 회귀, iOS Simulator Release 빌드만 다룹니다."
    echo "실제 iPhone, 카카오·Apple 실계정, APNs, TestFlight, 권한 설정 변경 및 두 기기 간 흐름은 자동 통과로 간주하지 않습니다."
    echo "수동 결과는 \`docs/RELEASE_TEST_RESULT_TEMPLATE.md\`에 별도로 기록하세요."
  } > "$REPORT_FILE"
}

echo "맡겨멍 Release Audit smoke 시작"
echo "결과 디렉터리: $RESULT_DIR"
echo

run_command A01 "필수 로컬 도구 확인" check_tools || true
run_command A02 "검사 대상 Git 상태 기록" check_repository_state || true
run_command A03 "민감 파일 Git 추적 여부" check_tracked_sensitive_files || true
run_command A04 "App Icon 소스 규격 검사" validate_app_icon || true

if [ "$RUN_IOS" -eq 1 ]; then
  run_command A05 "Privacy Manifest·App Privacy 입력안 일치 검사" validate_privacy_declarations || true
  run_command S01 "iOS 설정의 서버용 API 자격 증명 차단" check_ios_server_secrets || true
  consistency_log="$LOG_DIR/S02.log"
  if check_repository_consistency >"$consistency_log" 2>&1; then
    record S02 PASS "저장소와 출시 문서 일치 검사" "$consistency_log"
  else
    consistency_status=$?
    if [ "$consistency_status" -eq 2 ]; then
      record S02 WARN "저장소와 출시 문서 일치 검사" "$consistency_log"
    else
      record S02 FAIL "저장소와 출시 문서 일치 검사" "$consistency_log"
    fi
  fi
else
  skip A05 "Privacy Manifest·App Privacy 입력안 일치 검사"
  skip S01 "iOS 설정의 서버용 API 자격 증명 차단"
  skip S02 "저장소와 출시 문서 일치 검사"
fi

if [ "$RUN_BACKEND" -eq 1 ]; then
  run_command B01 "Cloudflare Worker 배포 번들 dry-run" backend_dry_run || true
  if run_command B02 "빈 로컬 D1에 전체 마이그레이션 적용" backend_migrations; then
    if run_command B03 "격리된 로컬 Worker 시작" start_worker; then
      run_command B04 "API 인증·권한 회귀 테스트" backend_regression || true
    else
      skip B04 "API 인증·권한 회귀 테스트(Worker 시작 실패)"
    fi
  else
    skip B03 "격리된 로컬 Worker 시작(마이그레이션 실패)"
    skip B04 "API 인증·권한 회귀 테스트(마이그레이션 실패)"
  fi
else
  skip B01 "Cloudflare Worker 배포 번들 dry-run"
  skip B02 "빈 로컬 D1에 전체 마이그레이션 적용"
  skip B03 "격리된 로컬 Worker 시작"
  skip B04 "API 인증·권한 회귀 테스트"
fi

if [ "$RUN_IOS" -eq 1 ] && [ "$QUICK" -eq 0 ]; then
  if run_command I01 "iOS Simulator Release configuration 빌드" ios_release_build; then
    run_command I02 "Release 번들의 Secret·디버그 진입 검사" ios_release_bundle_gate || true
    run_command I03 "맡겨멍 앱 소스 Release 경고 차단" ios_app_source_warning_gate || true
    run_command I04 "Release 최소 지원 버전 고정" ios_minimum_version_gate || true
    run_command I05 "App Store 표시 이름·카테고리 고정" ios_store_identity_gate || true
    run_command I06 "Release Privacy Manifest 포함·내용 검사" ios_privacy_manifest_gate || true
    run_command I07 "사용 권한·Background Mode 최소 선언 검사" ios_permission_declarations_gate || true
  else
    skip I02 "Release 번들의 Secret·디버그 진입 검사(빌드 실패)"
    skip I03 "맡겨멍 앱 소스 Release 경고 차단(빌드 실패)"
    skip I04 "Release 최소 지원 버전 고정(빌드 실패)"
    skip I05 "App Store 표시 이름·카테고리 고정(빌드 실패)"
    skip I06 "Release Privacy Manifest 포함·내용 검사(빌드 실패)"
    skip I07 "사용 권한·Background Mode 최소 선언 검사(빌드 실패)"
  fi
else
  skip I01 "iOS Simulator Release configuration 빌드"
  skip I02 "Release 번들의 Secret·디버그 진입 검사"
  skip I03 "맡겨멍 앱 소스 Release 경고 차단"
  skip I04 "Release 최소 지원 버전 고정"
  skip I05 "App Store 표시 이름·카테고리 고정"
  skip I06 "Release Privacy Manifest 포함·내용 검사"
  skip I07 "사용 권한·Background Mode 최소 선언 검사"
fi

write_report

echo
echo "결과 보고서: $REPORT_FILE"
if [ "$FAILURES" -gt 0 ]; then
  echo "종합 결과: FAIL (${FAILURES}개 실패, ${WARNINGS}개 경고)"
  exit 1
fi
echo "종합 결과: PASS (${WARNINGS}개 경고)"
