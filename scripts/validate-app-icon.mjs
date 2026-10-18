#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const iconSetDirectory = join(
  repoRoot,
  "Dog_kindergarden/Dog_kindergarden/Assets.xcassets/AppIcon.appiconset",
);
const catalogPath = join(iconSetDirectory, "Contents.json");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function readPNGMetadata(buffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  assert(buffer.subarray(0, 8).equals(signature), "App Icon이 PNG 파일이 아닙니다.");

  let offset = 8;
  let metadata = null;
  let hasTransparencyChunk = false;

  while (offset + 12 <= buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const dataStart = offset + 8;
    const nextOffset = dataStart + length + 4;
    assert(nextOffset <= buffer.length, `손상된 PNG 청크를 발견했습니다: ${type}`);

    if (type === "IHDR") {
      assert(length === 13, "PNG IHDR 길이가 올바르지 않습니다.");
      metadata = {
        width: buffer.readUInt32BE(dataStart),
        height: buffer.readUInt32BE(dataStart + 4),
        bitDepth: buffer[dataStart + 8],
        colorType: buffer[dataStart + 9],
      };
    }
    if (type === "tRNS") hasTransparencyChunk = true;
    offset = nextOffset;
    if (type === "IEND") break;
  }

  assert(metadata, "PNG IHDR 정보를 찾지 못했습니다.");
  return { ...metadata, hasTransparencyChunk };
}

const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
const defaultIcons = catalog.images.filter(
  (item) =>
    item.platform === "ios" &&
    item.idiom === "universal" &&
    item.size === "1024x1024" &&
    !item.appearances,
);

assert(defaultIcons.length === 1, "기본 iOS 1024×1024 App Icon 항목은 정확히 1개여야 합니다.");
const filename = defaultIcons[0].filename;
assert(typeof filename === "string" && filename.length > 0, "기본 App Icon 파일명이 비어 있습니다.");

const iconPath = join(iconSetDirectory, filename);
const icon = readFileSync(iconPath);
const metadata = readPNGMetadata(icon);

assert(
  metadata.width === 1024 && metadata.height === 1024,
  `App Icon 크기가 1024×1024가 아닙니다: ${metadata.width}×${metadata.height}`,
);
assert(metadata.bitDepth === 8, `App Icon 비트 깊이가 8-bit가 아닙니다: ${metadata.bitDepth}-bit`);
assert(metadata.colorType === 2, `App Icon이 투명도 없는 RGB PNG가 아닙니다: color type ${metadata.colorType}`);
assert(!metadata.hasTransparencyChunk, "App Icon PNG에 투명도(tRNS) 청크가 포함되어 있습니다.");

const digest = createHash("sha256").update(icon).digest("hex");
console.log(`App Icon 파일: ${filename}`);
console.log(`규격: ${metadata.width}×${metadata.height}, 8-bit RGB, alpha 없음`);
console.log(`SHA-256: ${digest}`);
console.log("App Icon 소스 규격 검사 통과");
