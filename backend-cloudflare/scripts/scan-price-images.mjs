#!/usr/bin/env node
/**
 * 네이버 플레이스 상세페이지의 "가격표 이미지로 보기" 버튼이 참조하는 이미지를
 * 비전 AI(Cloudflare Workers AI)로 읽어 가격 텍스트를 추출한다.
 *
 * 배경:
 * - 네이버 Apollo State의 placeDetail.menuImages 필드가 그 버튼의 실제 데이터 소스다
 *   (2026-08-09 재조사 — 이전에 확인했던 Menu.images는 이름이 비슷한 별개 필드로 항상 비어있었음).
 * - 버튼 유무와 menuImages 존재 여부가 100% 일치함을 5개 가게로 교차검증함.
 * - "업체사진" 전부를 비전 AI로 훑던 이전 방식은 느리고(가게당 최대 4회 호출) 오탐 위험도 컸는데,
 *   menuImages로 후보를 구조적으로 좁히면 비전 호출이 실제 가격표일 가능성이 높은 이미지에만 든다.
 *
 * 원칙:
 * - 캡차/로그인/차단 우회 안 함 — 일반 GET으로 받아지는 공개 HTML만 읽음
 * - 네이버가 막히면(연속 fetch 실패) 진행 상황을 저장하고 중단 — 다음 실행 시 이어서 처리
 *
 * 사용:
 *   node scripts/scan-price-images.mjs --input=crawl-results/price-image-scan-input-2026-08-09.json
 */

import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fetchText, parseApolloState, parseArgs, sleep } from "./lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendDir = path.resolve(__dirname, "..");
const resultDir = path.join(backendDir, "crawl-results");
const args = parseArgs(process.argv.slice(2));
const input = path.resolve(backendDir, String(args.input ?? "crawl-results/price-image-scan-input-2026-08-09.json"));
const checkpointPath = path.join(resultDir, "price-image-scan-progress.json");
const outPath = path.join(resultDir, "price-image-scan-result.json");

const VISION_ENDPOINT = "https://matgyeomung-api.dog-kindergarden.workers.dev/api/internal/vision-price-ocr";
// llava-1.5-7b-hf는 프롬프트를 그대로 되풀이하거나 없는 가격을 지어내는 사례가 확인되어(2026-08-09) 교체.
// llama-3.2-11b-vision-instruct는 같은 8장 재검증에서 오탐 0건.
const VISION_MODEL = "@cf/meta/llama-3.2-11b-vision-instruct";
const MAX_PHOTOS_PER_STORE = 8;
const MAX_CONSECUTIVE_FAILS = 5;

mkdirSync(resultDir, { recursive: true });

const targets = JSON.parse(readFileSync(input, "utf8"));
const done = existsSync(checkpointPath) ? JSON.parse(readFileSync(checkpointPath, "utf8")) : [];
const doneKeys = new Set(done.map((r) => r.store_key));
const remaining = targets.filter((t) => !doneKeys.has(t.store_key));

console.log(`전체 대상 ${targets.length}건, 이미 처리 ${done.length}건, 남은 ${remaining.length}건`);

main().catch((err) => {
  console.error("❌ 가격 이미지 스캔 실패:", err?.message ?? err);
  process.exit(1);
});

async function main() {
  const results = [...done];
  let consecutiveFails = 0;

  for (const [idx, target] of remaining.entries()) {
    console.log(`(${idx + 1}/${remaining.length}) ${target.store_name} (${target.place_id})`);

    const detailUrl = `https://pcmap.place.naver.com/place/${target.place_id}/home`;
    const html = await fetchText(detailUrl);
    if (!html) {
      consecutiveFails++;
      console.log(`  ⚠️ 상세페이지 fetch 실패 (연속 ${consecutiveFails}회)`);
      if (consecutiveFails >= MAX_CONSECUTIVE_FAILS) {
        console.log(`🛑 네이버 차단 의심 — ${MAX_CONSECUTIVE_FAILS}회 연속 실패, 중단하고 진행상황 저장`);
        break;
      }
      results.push({ ...target, status: "detail-fetch-failed" });
      writeFileSync(checkpointPath, JSON.stringify(results, null, 2));
      continue;
    }
    consecutiveFails = 0;

    const state = parseApolloState(html);
    if (!state) {
      results.push({ ...target, status: "no-apollo-state" });
      writeFileSync(checkpointPath, JSON.stringify(results, null, 2));
      continue;
    }

    const menuImages = extractMenuImages(state);

    if (menuImages.length === 0) {
      results.push({ ...target, status: "no-menu-images" });
      writeFileSync(checkpointPath, JSON.stringify(results, null, 2));
      await sleep(1200);
      continue;
    }

    const hits = [];
    for (const imageUrl of menuImages.slice(0, MAX_PHOTOS_PER_STORE)) {
      const verdict = await checkPriceImage(imageUrl);
      await sleep(400);
      if (verdict) hits.push({ image_url: imageUrl, price_info: verdict });
    }

    if (hits.length > 0) {
      console.log(`  ✅ 가격표 텍스트 추출: ${hits.map((h) => h.price_info).join(" | ").slice(0, 100)}`);
      results.push({
        ...target,
        status: "found",
        price_info: hits.map((h) => h.price_info).join(" | "),
        images: hits,
      });
    } else {
      results.push({ ...target, status: "menu-images-not-readable", menu_image_count: menuImages.length });
    }
    writeFileSync(checkpointPath, JSON.stringify(results, null, 2));

    await sleep(1200 + Math.random() * 400);
  }

  writeFileSync(outPath, JSON.stringify(results, null, 2));
  const foundCount = results.filter((r) => r.status === "found").length;
  console.log(`\n완료: 총 ${results.length}건 처리 / 가격표 이미지 발견 ${foundCount}건`);
  console.log(`결과: ${path.relative(backendDir, outPath)}`);
}

async function checkPriceImage(imageUrl) {
  try {
    const res = await fetch(VISION_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ image_url: imageUrl, model: VISION_MODEL }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return extractPriceInfo(String(data.result ?? "").trim());
  } catch {
    return null;
  }
}

// 모델이 지시한 '가격표: ...' 형식을 항상 정확히 지키지는 않아(실측 확인) 두 단계로 판정한다.
function extractPriceInfo(text) {
  const idx = text.indexOf("가격표:");
  if (idx !== -1) {
    const extracted = text.slice(idx + "가격표:".length).trim();
    if (/\d/.test(extracted)) return extracted;
  }
  // 형식을 안 지켰어도 원화 금액 패턴이 다수면(단발성 언급이 아니라 실제 표) 가격표로 인정
  const wonMatches = text.match(/[0-9][0-9,]*\s*원/g) ?? [];
  if (wonMatches.length >= 2) return text;
  return null;
}

function extractMenuImages(state) {
  const rootQuery = state.ROOT_QUERY;
  if (!rootQuery) return [];
  const placeDetailKey = Object.keys(rootQuery).find((k) => k.startsWith("placeDetail"));
  if (!placeDetailKey) return [];
  const menuImages = rootQuery[placeDetailKey]?.menuImages;
  if (!Array.isArray(menuImages)) return [];
  return menuImages.map((m) => m?.imageUrl).filter(Boolean);
}

