#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const defaultManifestPath = resolve(
  repoRoot,
  "Dog_kindergarden/Dog_kindergarden/PrivacyInfo.xcprivacy",
);
const manifestPath = process.argv[2] ? resolve(process.argv[2]) : defaultManifestPath;
const checklistPath = resolve(repoRoot, "docs/APP_STORE_PRIVACY_CHECKLIST.md");

const expectedDataTypes = [
  "NSPrivacyCollectedDataTypeName",
  "NSPrivacyCollectedDataTypeEmailAddress",
  "NSPrivacyCollectedDataTypePhoneNumber",
  "NSPrivacyCollectedDataTypePhysicalAddress",
  "NSPrivacyCollectedDataTypeUserID",
  "NSPrivacyCollectedDataTypeEmailsOrTextMessages",
  "NSPrivacyCollectedDataTypeOtherUserContent",
  "NSPrivacyCollectedDataTypePhotosorVideos",
  "NSPrivacyCollectedDataTypeProductInteraction",
];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function unique(values) {
  return [...new Set(values)];
}

function sorted(values) {
  return [...values].sort((left, right) => left.localeCompare(right));
}

assert(existsSync(manifestPath), `Privacy Manifest를 찾지 못했습니다: ${manifestPath}`);
assert(existsSync(checklistPath), `App Privacy 체크리스트를 찾지 못했습니다: ${checklistPath}`);

let manifest;
try {
  const json = execFileSync(
    "/usr/bin/plutil",
    ["-convert", "json", "-o", "-", manifestPath],
    { encoding: "utf8" },
  );
  manifest = JSON.parse(json);
} catch (error) {
  throw new Error(`Privacy Manifest를 읽지 못했습니다: ${error.message}`);
}

assert(manifest.NSPrivacyTracking === false, "앱은 추적하지 않으므로 NSPrivacyTracking은 false여야 합니다.");
assert(
  Array.isArray(manifest.NSPrivacyTrackingDomains) && manifest.NSPrivacyTrackingDomains.length === 0,
  "추적 도메인은 빈 배열이어야 합니다.",
);

const collectedDataTypes = manifest.NSPrivacyCollectedDataTypes;
assert(Array.isArray(collectedDataTypes), "NSPrivacyCollectedDataTypes 배열이 없습니다.");

const actualDataTypes = collectedDataTypes.map((entry) => entry.NSPrivacyCollectedDataType);
assert(
  unique(actualDataTypes).length === actualDataTypes.length,
  "Privacy Manifest에 중복된 수집 데이터 유형이 있습니다.",
);
assert(
  JSON.stringify(sorted(actualDataTypes)) === JSON.stringify(sorted(expectedDataTypes)),
  [
    "Privacy Manifest의 수집 데이터 유형이 App Privacy 입력안과 다릅니다.",
    `예상: ${sorted(expectedDataTypes).join(", ")}`,
    `실제: ${sorted(actualDataTypes).join(", ")}`,
  ].join("\n"),
);

for (const entry of collectedDataTypes) {
  const type = entry.NSPrivacyCollectedDataType;
  assert(entry.NSPrivacyCollectedDataTypeLinked === true, `${type}: 사용자 연결 여부는 true여야 합니다.`);
  assert(entry.NSPrivacyCollectedDataTypeTracking === false, `${type}: 추적 사용 여부는 false여야 합니다.`);
  assert(
    Array.isArray(entry.NSPrivacyCollectedDataTypePurposes) &&
      entry.NSPrivacyCollectedDataTypePurposes.length === 1 &&
      entry.NSPrivacyCollectedDataTypePurposes[0] === "NSPrivacyCollectedDataTypePurposeAppFunctionality",
    `${type}: 수집 목적은 App Functionality 하나여야 합니다.`,
  );
}

const accessedAPITypes = manifest.NSPrivacyAccessedAPITypes;
assert(Array.isArray(accessedAPITypes), "NSPrivacyAccessedAPITypes 배열이 없습니다.");
const userDefaultsDeclaration = accessedAPITypes.find(
  (entry) => entry.NSPrivacyAccessedAPIType === "NSPrivacyAccessedAPICategoryUserDefaults",
);
assert(userDefaultsDeclaration, "UserDefaults Required Reason API 선언이 없습니다.");
assert(
  Array.isArray(userDefaultsDeclaration.NSPrivacyAccessedAPITypeReasons) &&
    userDefaultsDeclaration.NSPrivacyAccessedAPITypeReasons.includes("CA92.1"),
  "UserDefaults 사용 사유 CA92.1이 선언되어 있지 않습니다.",
);

const checklist = readFileSync(checklistPath, "utf8");
for (const type of expectedDataTypes) {
  assert(checklist.includes(`\`${type}\``), `App Privacy 체크리스트에서 ${type} 매핑을 찾지 못했습니다.`);
}
assert(
  checklist.includes("`NSPrivacyTracking = false`") && checklist.includes("`CA92.1`"),
  "App Privacy 체크리스트의 추적·Required Reason API 설명이 누락되었습니다.",
);

console.log(`Privacy Manifest: ${manifestPath}`);
console.log(`수집 데이터 유형: ${actualDataTypes.length}개 (모두 사용자 연결, 추적 안 함, 앱 기능 목적)`);
console.log("Required Reason API: UserDefaults / CA92.1");
console.log("Privacy Manifest와 App Privacy 입력안 일치 검사 통과");
