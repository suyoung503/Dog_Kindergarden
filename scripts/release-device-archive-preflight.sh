#!/usr/bin/env bash

# App Store 서명·업로드 전에 iPhone용 Release Archive가 실제 기기 아키텍처로
# 완성되는지와 완성 번들에 출시 필수 정보가 포함됐는지 로컬에서 검사한다.
# CODE_SIGNING_ALLOWED=NO를 사용하므로 최종 서명 Archive 검증을 대체하지 않는다.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$REPO_ROOT/Dog_kindergarden"

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RESULT_DIR="${RESULT_DIR:-/tmp/matgyeomung-device-archive-$RUN_ID}"
ARCHIVE_PATH="$RESULT_DIR/Matgyeomung.xcarchive"
DERIVED_DATA_PATH="$RESULT_DIR/DerivedData"
BUILD_LOG="$RESULT_DIR/archive.log"
REPORT_FILE="$RESULT_DIR/archive-preflight-result.md"

# 2026-10-19 현재 App Store Connect 업로드 최소 요구사항.
# 실제 제출일에는 Apple Upcoming Requirements를 다시 확인해야 한다.
MIN_XCODE_MAJOR="${MIN_XCODE_MAJOR:-26}"
MIN_IPHONEOS_SDK_MAJOR="${MIN_IPHONEOS_SDK_MAJOR:-26}"
EXPECTED_MIN_IOS="17.0"
EXPECTED_DISPLAY_NAME="맡겨멍"
EXPECTED_APP_CATEGORY="public.app-category.lifestyle"

fail() {
  echo "실패: $*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true
}

for tool in xcodebuild xcrun lipo strings node /usr/libexec/PlistBuddy; do
  command -v "$tool" >/dev/null 2>&1 || fail "필수 도구를 찾지 못했습니다: $tool"
done

xcode_version="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
xcode_major="${xcode_version%%.*}"
sdk_major="${sdk_version%%.*}"

case "$xcode_major" in (*[!0-9]*|'') fail "Xcode 버전을 해석하지 못했습니다: $xcode_version" ;; esac
case "$sdk_major" in (*[!0-9]*|'') fail "iPhoneOS SDK 버전을 해석하지 못했습니다: $sdk_version" ;; esac

[ "$xcode_major" -ge "$MIN_XCODE_MAJOR" ] || \
  fail "Xcode $xcode_version은 현재 업로드 최소 기준 Xcode $MIN_XCODE_MAJOR보다 낮습니다."
[ "$sdk_major" -ge "$MIN_IPHONEOS_SDK_MAJOR" ] || \
  fail "iPhoneOS SDK $sdk_version은 현재 업로드 최소 기준 SDK $MIN_IPHONEOS_SDK_MAJOR보다 낮습니다."

mkdir -p "$RESULT_DIR"

echo "iPhone용 unsigned Release Archive 생성 중"
echo "- Xcode: $xcode_version"
echo "- iPhoneOS SDK: $sdk_version"
echo "- 결과: $RESULT_DIR"

if ! (
  cd "$IOS_DIR" &&
  xcodebuild archive \
    -workspace Dog_kindergarden.xcworkspace \
    -scheme Dog_kindergarden \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO
) >"$BUILD_LOG" 2>&1; then
  echo "Archive 생성에 실패했습니다. 마지막 로그:" >&2
  tail -120 "$BUILD_LOG" >&2
  exit 1
fi

app_path="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null)"
[ -n "$app_path" ] || fail "Archive 안에서 .app 번들을 찾지 못했습니다."

info_plist="$app_path/Info.plist"
[ -f "$info_plist" ] || fail "완성 앱의 Info.plist를 찾지 못했습니다."

executable_name="$(plist_value CFBundleExecutable "$info_plist")"
executable_path="$app_path/$executable_name"
[ -n "$executable_name" ] && [ -f "$executable_path" ] || fail "완성 앱의 실행 파일을 찾지 못했습니다."

architectures="$(lipo -archs "$executable_path")"
case " $architectures " in (*" arm64 "*) ;; (*) fail "실제 iPhone용 arm64 실행 파일이 아닙니다: $architectures" ;; esac
case " $architectures " in (*" x86_64 "*) fail "Archive 실행 파일에 Simulator x86_64가 포함됐습니다." ;; esac

minimum_os="$(plist_value MinimumOSVersion "$info_plist")"
display_name="$(plist_value CFBundleDisplayName "$info_plist")"
category="$(plist_value LSApplicationCategoryType "$info_plist")"
bundle_id="$(plist_value CFBundleIdentifier "$info_plist")"
marketing_version="$(plist_value CFBundleShortVersionString "$info_plist")"
build_number="$(plist_value CFBundleVersion "$info_plist")"

[ "$minimum_os" = "$EXPECTED_MIN_IOS" ] || fail "최소 지원 버전 불일치: ${minimum_os:-미설정}"
[ "$display_name" = "$EXPECTED_DISPLAY_NAME" ] || fail "앱 표시 이름 불일치: ${display_name:-미설정}"
[ "$category" = "$EXPECTED_APP_CATEGORY" ] || fail "앱 카테고리 불일치: ${category:-미설정}"

for key in NAVER_CLIENT_ID NAVER_CLIENT_SECRET KAKAO_REST_API_KEY DATA_GO_KR_SERVICE_KEY INTERNAL_API_KEY; do
  [ -z "$(plist_value "$key" "$info_plist")" ] || fail "완성 앱 Info.plist에 서버용 Secret 항목 $key가 포함됐습니다."
done

if strings "$executable_path" | grep -Eq '개발자 진입|운영자 진입'; then
  fail "완성 앱 실행 파일에서 개발용 진입 문구를 발견했습니다."
fi

privacy_manifest="$app_path/PrivacyInfo.xcprivacy"
[ -f "$privacy_manifest" ] || fail "완성 앱 루트에 PrivacyInfo.xcprivacy가 없습니다."
cmp -s "$IOS_DIR/Dog_kindergarden/PrivacyInfo.xcprivacy" "$privacy_manifest" || \
  fail "완성 앱의 Privacy Manifest가 소스 선언과 다릅니다."
node "$REPO_ROOT/scripts/validate-privacy-declarations.mjs" "$privacy_manifest" >"$RESULT_DIR/privacy-validation.log" 2>&1 || {
  cat "$RESULT_DIR/privacy-validation.log" >&2
  fail "완성 앱의 Privacy Manifest 검증에 실패했습니다."
}

if grep -E "^$IOS_DIR/Dog_kindergarden/.*:[0-9]+:[0-9]+: warning:" "$BUILD_LOG" >"$RESULT_DIR/app-source-warnings.log"; then
  cat "$RESULT_DIR/app-source-warnings.log" >&2
  fail "맡겨멍 앱 소스의 Release 컴파일러 경고가 있습니다."
fi

cat >"$REPORT_FILE" <<EOF
# iPhone용 Release Archive 사전검사 결과

- 결과: **PASS**
- 검사 시각: $(date '+%Y-%m-%d %H:%M:%S %Z')
- Xcode: $xcode_version
- iPhoneOS SDK: $sdk_version
- 앱: $display_name $marketing_version ($build_number)
- Bundle ID: $bundle_id
- 아키텍처: $architectures
- 최소 iOS: $minimum_os
- 카테고리: $category
- Archive: \`$ARCHIVE_PATH\`
- 빌드 로그: \`$BUILD_LOG\`

## 통과 항목

- 실제 iPhone용 arm64 Release Archive 생성
- 서버 Secret·개발용 진입 문구 미포함
- 표시 이름·카테고리·최소 iOS 고정
- Privacy Manifest 번들 포함·입력안 일치
- 맡겨멍 앱 소스 Release 경고 없음

## 남은 수동 확인

이 검사는 서명하지 않은 로컬 Archive 검사입니다. 제출 후보에서는 Apple Distribution 서명으로 Archive한 뒤 Organizer의 Validate App과 App Store Connect 업로드를 별도로 완료해야 합니다. 실제 제출일에는 Apple의 필수 Xcode·SDK 버전도 다시 확인해야 합니다.
EOF

echo "Archive 사전검사 PASS"
echo "- 앱: $display_name $marketing_version ($build_number)"
echo "- 아키텍처: $architectures"
echo "- 최소 iOS: $minimum_os"
echo "- 보고서: $REPORT_FILE"
echo "주의: unsigned 검사이므로 최종 서명 Archive·Validate App·업로드 검증은 별도입니다."
