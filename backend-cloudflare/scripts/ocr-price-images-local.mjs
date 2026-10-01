#!/usr/bin/env node
/**
 * 네이버 플레이스 menuImages 가격표를 macOS Vision으로 읽는다.
 * 생성형 모델을 쓰지 않고, 로컬 OCR에서 서로 다른 금액과 서비스 문맥이 함께 잡힌
 * 결과만 로컬 D1에 넣는다.
 * macOS/Xcode가 있는 개발 환경 전용이며, 교차검증된 결과만 로컬 D1에 넣는다.
 */

import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs, sleep, sqlString, unique } from "./lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendDir = path.resolve(__dirname, "..");
const resultDir = path.join(backendDir, "crawl-results");
const args = parseArgs(process.argv.slice(2));
const input = path.resolve(backendDir, String(args.input ?? "crawl-results/price-ocr-input-2026-10-01.json"));
const offset = Number(args.offset ?? 0);
const limit = Number(args.limit ?? 10);
const maxImages = Number(args["max-images"] ?? 8);
const applyLocal = Boolean(args["apply-local"]);
const binaryPath = path.join(tmpdir(), "matgyeomung-vision-price-ocr");
const workDir = path.join(tmpdir(), `matgyeomung-price-ocr-${process.pid}`);

mkdirSync(resultDir, { recursive: true });
mkdirSync(workDir, { recursive: true });

main().finally(() => {
  try { rmSync(workDir, { recursive: true, force: true }); } catch { /* 무시 */ }
}).catch((error) => {
  console.error("❌ 로컬 가격표 OCR 실패:", error?.message ?? error);
  process.exit(1);
});

async function main() {
  compileVisionHelper();
  const targets = JSON.parse(readFileSync(input, "utf8")).slice(offset, offset + limit);
  const results = [];
  console.log(`🚀 로컬 Vision 가격표 OCR: ${offset + 1}~${offset + targets.length}번째`);

  for (const [targetIndex, target] of targets.entries()) {
    console.log(`(${targetIndex + 1}/${targets.length}) ${target.store_name}`);
    const hits = [];
    const imageUrls = unique(target.menu_images ?? []).slice(0, maxImages);

    for (const [imageIndex, imageUrl] of imageUrls.entries()) {
      const imagePath = path.join(workDir, `${targetIndex}-${imageIndex}.img`);
      let response;
      try {
        response = await fetch(imageUrl, { signal: AbortSignal.timeout(20_000) });
      } catch {
        continue;
      }
      if (!response.ok) continue;
      writeFileSync(imagePath, Buffer.from(await response.arrayBuffer()));

      const ocr = spawnSync(binaryPath, [imagePath], { encoding: "utf8", maxBuffer: 2_000_000 });
      if (ocr.status !== 0) continue;
      const local = summarizePriceText(ocr.stdout);
      const crossCheck = "local-only";
      const verified = isHighConfidenceLocal(local);
      if (local.price_info) {
        hits.push({
          image_url: imageUrl,
          verified,
          cross_check: crossCheck,
          price_info: verified ? local.price_info : "",
          local_summary: local.price_info,
          local_amounts: local.amounts,
          raw_ocr: cleanText(ocr.stdout).slice(0, 3000),
        });
      }
      await sleep(150);
    }

    const verifiedPrices = hits.filter((hit) => hit.verified).map((hit) => hit.price_info);
    const reviewPrices = hits.filter((hit) => !hit.verified).map((hit) => hit.local_summary);
    const priceInfo = unique(verifiedPrices).join(" | ").slice(0, 1600);
    const confidence = priceInfo ? "high" : reviewPrices.length ? "review" : "none";
    const preview = priceInfo || unique(reviewPrices).join(" | ");
    console.log(preview ? `  ${confidence === "high" ? "✅" : "🔎"} ${confidence} — ${preview.slice(0, 140)}` : "  ⚠️ 인식 가능한 가격 없음");
    results.push({ ...target, status: priceInfo ? "found" : reviewPrices.length ? "review" : "not-readable", confidence, price_info: priceInfo, review_text: unique(reviewPrices).join(" | ").slice(0, 1600), images: hits });
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const outJson = path.join(resultDir, `local-price-ocr-${stamp}.json`);
  const outSql = path.join(resultDir, `local-price-ocr-${stamp}.sql`);
  writeFileSync(outJson, JSON.stringify({ generated_at: new Date().toISOString(), offset, count: results.length, results }, null, 2));
  writeFileSync(outSql, buildSql(results));
  console.log(`완료: high ${results.filter((item) => item.confidence === "high").length} / 검토 ${results.filter((item) => item.confidence === "review").length}`);
  console.log(`✅ JSON 저장: ${path.relative(backendDir, outJson)}`);

  if (applyLocal) applySql(outSql);
}

function compileVisionHelper() {
  const source = path.join(__dirname, "vision-price-ocr.swift");
  const result = spawnSync("xcrun", ["swiftc", source, "-o", binaryPath], {
    encoding: "utf8",
    env: {
      ...process.env,
      SWIFT_MODULECACHE_PATH: path.join(tmpdir(), "matgyeomung-swift-module-cache"),
      CLANG_MODULE_CACHE_PATH: path.join(tmpdir(), "matgyeomung-clang-module-cache"),
    },
  });
  if (result.status !== 0) throw new Error(result.stderr || "Vision OCR helper compile failed");
}

function summarizePriceText(raw) {
  const lines = String(raw ?? "")
    .split(/\r?\n/)
    .map(cleanText)
    .filter(Boolean);
  const rows = [];
  let section = "";
  let context = [];

  for (const line of lines) {
    const amounts = extractAmounts(line);
    if (amounts.length) {
      const ownLabel = cleanText(line.replace(/[0-9][0-9,.]*/g, " ").replace(/원/g, " "));
      const contextLabel = context.slice(-2).join(" ");
      const label = ownLabel || contextLabel || section;
      if (label && !isNoise(label)) {
        // 한 줄에 여러 금액이 있는 표는 대개 체중/횟수별 열이다. 범위로 단정하지 않고 나열한다.
        const normalizedAmounts = amounts.map((amount) => `${amount.toLocaleString("ko-KR")}원`).join(" · ");
        const prefix = section && !label.includes(section) ? `${section} ` : "";
        rows.push(cleanText(`${prefix}${label} ${normalizedAmounts}`));
      }
      context = [];
      continue;
    }

    if (isNoise(line) || line.length > 45) continue;
    if (/(유치원|호텔|데이\s*케어|놀이방|돌봄|교육|교정|픽업|드랍|미용|목욕|스파|회원권|정기권|이용권|입장료)/i.test(line)) {
      section = line;
      context = [];
    } else {
      context.push(line);
      if (context.length > 3) context.shift();
    }
  }

  return {
    price_info: unique(rows).join(" / ").slice(0, 1200),
    amounts: unique(lines.flatMap(extractAmounts)),
  };
}

function isHighConfidenceLocal(local) {
  if (!local.price_info || unique(local.amounts).length < 2) return false;
  return /(유치원|호텔|데이\s*케어|놀이방|돌봄|교육|교정|픽업|드랍|셔틀|미용|목욕|스파|회원권|정기권|이용권|입장료|회|박|시간|kg)/i.test(local.price_info);
}

function extractAmounts(line) {
  return [...String(line).matchAll(/[0-9][0-9,.]*/g)]
    .map((match) => Number(match[0].replace(/[,.]/g, "")))
    // 전화번호 조각(4481, 5549 등)과 OCR이 소수점 표를 잘못 읽은 값을 가격으로 오인하지 않도록
    // 최소 1,000원, 100원 단위의 금액만 인정한다.
    .filter((value) => Number.isFinite(value) && value >= 1000 && value <= 10_000_000 && value % 100 === 0);
}

function isNoise(value) {
  return /^(?:VAT|부가세|추천!?|BEST|EVENT)$/i.test(value) ||
    /(문의|상담|할인|사용\s*기한|예약|진행|선생님|보호자|공격성|입학|주의|환불)/.test(value);
}

function buildSql(results) {
  const lines = ["BEGIN TRANSACTION;"];
  for (const item of results) {
    if (item.confidence !== "high" || !item.price_info) continue;
    lines.push(`\nUPDATE stores\nSET price_info = ${sqlString(item.price_info)}\nWHERE store_key = ${sqlString(item.store_key)}\n  AND is_curated = 1\n  AND (price_info IS NULL OR TRIM(price_info) = '');`);
  }
  lines.push("COMMIT;");
  return lines.join("\n");
}

function applySql(file) {
  const result = spawnSync(
    "npx",
    ["wrangler", "d1", "execute", "dog_kindergarden_db", "--local", "--file", file],
    { cwd: backendDir, stdio: "inherit" },
  );
  if (result.status !== 0) process.exit(result.status ?? 1);
  console.log("✅ 로컬 D1 고신뢰 OCR 가격 반영 완료");
}

function cleanText(value) {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}
