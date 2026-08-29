#!/usr/bin/env node
/**
 * 네이버 플레이스 검색 결과 목록이 제공하는 대표 이미지(imageUrl)로 stores.image_url을 채운다.
 *
 * 배경:
 * - 배포 API 기준 큐레이션 291곳 중 19곳만 image_url이 있었다(2026-08-21 확인) — 이전 크롤링은
 *   가격표 수집 위주였고 이미지는 거의 수집되지 않았다.
 * - 가격/카테고리 스크립트가 이미 여는 검색 목록 페이지(Apollo State의 PlaceListBusinessesItem)에
 *   업체가 등록한 대표 이미지 URL이 imageUrl 필드로 그대로 들어있다 — 상세페이지를 추가로 열 필요 없다.
 *
 * 원칙:
 * - 캡차/로그인/차단 우회 안 함 — 일반 GET으로 받아지는 공개 HTML만 읽음
 * - 이미 image_url이 있는 가게는 기본적으로 건너뜀(--all로 강제 재수집), SQL도 빈 값일 때만 채움
 * - 네이버가 막히면(연속 fetch 실패) 지금까지 결과를 저장하고 중단
 *
 * 사용:
 *   node scripts/crawl-store-images.mjs --limit=5
 *
 * DB 반영:
 *   node scripts/crawl-store-images.mjs --limit=5 --apply-local
 */

import { mkdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fetchText, namesLikelyMatch, parseApolloState, parseArgs, sleep, sqlString } from "./lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendDir = path.resolve(__dirname, "..");
const resultDir = path.join(backendDir, "crawl-results");
const args = parseArgs(process.argv.slice(2));
const limit = Number(args.limit ?? 5);
const applyLocal = Boolean(args["apply-local"]);
const includeAll = Boolean(args.all);
const MAX_CONSECUTIVE_FAILS = 5;

// 가게 좌표를 모를 때 쓰는 기본 검색 중심점(서울시청) — 검색 순위가 위치에 살짝 가중되므로
// store.latitude/longitude가 있으면 그 값을 우선 쓴다.
const DEFAULT_X = "126.9779692";
const DEFAULT_Y = "37.5662952";

// 등록된 상호명 그대로 검색하면 네이버 플레이스에서 안 걸리는 예외 케이스.
// 실제 네이버 등록명이 더 짧거나 표기가 달라 --limit 재실행으로는 못 살리는 곳만 추가한다.
const SEARCH_QUERY_OVERRIDES = {
  "제주네 애견유치원": "제주네 애견",
  "놀러오개 애견유치원 애견호텔 애견미용 서초점": "놀러오개 서초점",
};

const STORES_API = "https://matgyeomung-api.dog-kindergarden.workers.dev/api/stores";
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const outJson = path.join(resultDir, `store-images-${stamp}.json`);
const outSql = path.join(resultDir, `store-images-${stamp}.sql`);

mkdirSync(resultDir, { recursive: true });

main().catch((err) => {
  console.error("❌ 대표이미지 수집 실패:", err?.message ?? err);
  process.exit(1);
});

async function main() {
  const res = await fetch(STORES_API);
  if (!res.ok) throw new Error(`가게 목록 조회 실패: ${res.status}`);
  const stores = await res.json();

  const targets = stores.filter((s) => includeAll || !s.image_url).slice(0, limit);
  console.log(`🚀 대표이미지 수집 시작: 전체 ${stores.length}곳 중 대상 ${targets.length}곳`);

  const results = [];
  let consecutiveFails = 0;

  for (const [idx, store] of targets.entries()) {
    console.log(`(${idx + 1}/${targets.length}) ${store.name}`);

    const outcome = await fetchRepresentativeImage(store);
    if (outcome.click_result === "list-fetch-failed") {
      consecutiveFails++;
      if (consecutiveFails >= MAX_CONSECUTIVE_FAILS) {
        console.log(`🛑 네이버 차단 의심 — ${MAX_CONSECUTIVE_FAILS}회 연속 실패, 중단하고 지금까지 결과 저장`);
        break;
      }
    } else {
      consecutiveFails = 0;
    }

    results.push({ store_key: store.store_key, store_name: store.name, ...outcome });
    console.log(
      outcome.matched
        ? `  ✅ ${outcome.place_name} — ${outcome.image_url}`
        : `  ⚠️ ${outcome.click_result}`,
    );

    if (idx < targets.length - 1) await sleep(800 + Math.random() * 400);
  }

  writeFileSync(outJson, JSON.stringify({ count: results.length, results }, null, 2));
  writeFileSync(outSql, buildSql(results, includeAll));
  const foundCount = results.filter((r) => r.matched).length;
  console.log(`\n완료: 총 ${results.length}건 처리 / 이미지 발견 ${foundCount}건`);
  console.log(`✅ JSON 저장: ${path.relative(backendDir, outJson)}`);
  console.log(`✅ SQL 저장: ${path.relative(backendDir, outSql)}`);

  if (applyLocal) {
    const r = spawnSync("npx", ["wrangler", "d1", "execute", "dog_kindergarden_db", "--local", "--file", outSql], {
      cwd: backendDir,
      stdio: "inherit",
    });
    if (r.status !== 0) process.exit(r.status ?? 1);
    console.log("✅ 로컬 D1 반영 완료");
  }
}

async function fetchRepresentativeImage(store) {
  const query = SEARCH_QUERY_OVERRIDES[store.name] ?? String(store.name ?? "").trim();
  if (!query) return { click_result: "empty-query", image_url: "", matched: false };

  const x = store.longitude ? String(store.longitude) : DEFAULT_X;
  const y = store.latitude ? String(store.latitude) : DEFAULT_Y;
  const listUrl = `https://pcmap.place.naver.com/place/list?query=${encodeURIComponent(query)}&x=${x}&y=${y}&clientX=${x}&clientY=${y}&display=5&locale=ko&svcName=map_pcv5`;

  const html = await fetchText(listUrl);
  if (!html) return { source_url: listUrl, click_result: "list-fetch-failed", image_url: "", matched: false };

  const state = parseApolloState(html);
  if (!state) return { source_url: listUrl, click_result: "list-no-apollo-state", image_url: "", matched: false };

  const picked = pickMatchingPlace(state, query);
  if (!picked) return { source_url: listUrl, click_result: "no-confident-match", image_url: "", matched: false };

  if (!picked.imageUrl) {
    return { place_id: picked.id, place_name: picked.name, source_url: listUrl, click_result: "no-image", image_url: "", matched: false };
  }

  return {
    place_id: picked.id,
    place_name: picked.name,
    source_url: listUrl,
    click_result: "matched",
    image_url: picked.imageUrl,
    matched: true,
  };
}

// scrape-naver-place-prices.mjs의 pickMatchingPlaceId와 동일한 원칙(이름이 실질적으로 같은
// 후보만 채택) — 대표이미지 오매칭은 엉뚱한 가게 사진을 노출하는 눈에 띄는 버그라 더 엄격히 다룬다.
function pickMatchingPlace(state, storeName) {
  const rootQuery = state.ROOT_QUERY ?? {};
  const key = Object.keys(rootQuery).find((k) => k.startsWith("placeList("));
  if (!key) return null;
  const items = rootQuery[key]?.businesses?.items ?? [];

  for (const item of items) {
    const id = (item?.__ref ?? "").replace("PlaceListBusinessesItem:", "");
    if (!id) continue;
    const obj = state[`PlaceListBusinessesItem:${id}`];
    const name = obj?.name ?? "";
    if (namesLikelyMatch(storeName, name)) {
      return { id, name, imageUrl: obj?.imageUrl ?? "" };
    }
  }
  return null;
}

function buildSql(results, overwrite) {
  const guard = overwrite ? "" : " AND (image_url IS NULL OR image_url = '')";
  const lines = ["BEGIN TRANSACTION;"];
  for (const r of results) {
    if (!r.image_url) continue;
    lines.push(`
UPDATE stores
SET image_url = ${sqlString(r.image_url)}
WHERE store_key = ${sqlString(r.store_key)}${guard};`);
  }
  lines.push("COMMIT;");
  return lines.join("\n");
}
