#!/usr/bin/env node
/**
 * 큐레이션 가게 중 가격이 비어 있는 곳을 대상으로 네이버 플레이스의 구조화 메뉴 가격을 재수집한다.
 *
 * - 이전 상세 보강 결과의 place_id를 재사용해 불필요한 검색 요청을 줄인다.
 * - Menu.price처럼 네이버가 구조화해 제공한 금액만 자동 반영한다.
 * - 가격표 이미지는 URL만 OCR 후보로 저장하고, 불확실한 OCR 문구를 DB에 자동 반영하지 않는다.
 * - 로컬 D1에는 기존 price_info가 빈 경우에만 채운다.
 *
 * 사용:
 *   node scripts/crawl-store-prices.mjs --offset=0 --limit=40
 *   node scripts/crawl-store-prices.mjs --offset=0 --limit=40 --apply-local
 */

import { mkdirSync, readFileSync, readdirSync, unlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  fetchText,
  namesLikelyMatch,
  parseApolloState,
  parseArgs,
  sleep,
  sqlString,
  unique,
} from "./lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendDir = path.resolve(__dirname, "..");
const resultDir = path.join(backendDir, "crawl-results");
const args = parseArgs(process.argv.slice(2));
const offset = Number(args.offset ?? 0);
const limit = Number(args.limit ?? 40);
const applyLocal = Boolean(args["apply-local"]);
const refresh = Boolean(args.refresh);
const overwrite = Boolean(args.overwrite);
const targetName = String(args.name ?? args["store-name"] ?? "").trim();
const MAX_CONSECUTIVE_FAILS = 5;

const STORES_API = "https://matgyeomung-api.dog-kindergarden.workers.dev/api/stores";
const DEFAULT_X = "126.9779692";
const DEFAULT_Y = "37.5662952";

const EXCLUDED_STORE_KEYS = new Set([
  "매일행복하개|서울특별시 양천구 신정중앙로 **, 양정빌딩 *층 (신정동)",
]);

const SEARCH_QUERY_OVERRIDES = {
  "제주네 애견유치원": "제주네 애견",
  "놀러오개 애견유치원 애견호텔 애견미용 서초점": "놀러오개 서초점",
  "디어캐닌 DEAR CANINE": "디어캐닌",
  "도기프렌즈 웰니스센터": "도기프렌즈 강아지유치원",
};

mkdirSync(resultDir, { recursive: true });

main().catch((error) => {
  console.error("❌ 가격 보강 실패:", error?.message ?? error);
  process.exit(1);
});

async function main() {
  const response = await fetch(STORES_API);
  if (!response.ok) throw new Error(`가게 목록 조회 실패: ${response.status}`);

  const allStores = await response.json();
  const missingPriceStores = allStores.filter(
    (store) =>
      !EXCLUDED_STORE_KEYS.has(store.store_key) &&
      (refresh || !String(store.price_info ?? "").trim()) &&
      (!targetName || String(store.name ?? "").includes(targetName)),
  );
  const targets = missingPriceStores.slice(offset, offset + limit);
  const cachedPlaces = loadCachedPlaces();
  const results = [];
  let consecutiveFails = 0;

  console.log(
    `🚀 가격 보강 시작: 가격 공백 ${missingPriceStores.length}곳 중 ${offset + 1}~${offset + targets.length}번째`,
  );

  for (const [index, store] of targets.entries()) {
    console.log(`(${index + 1}/${targets.length}) ${store.name}`);
    const cached = cachedPlaces.get(store.store_key);
    const outcome = await fetchPrice(store, cached);
    results.push({ store_key: store.store_key, store_name: store.name, ...outcome });

    if (outcome.status === "list-fetch-failed" || outcome.status === "detail-fetch-failed") {
      consecutiveFails += 1;
    } else {
      consecutiveFails = 0;
    }

    if (outcome.price_info) {
      console.log(`  ✅ ${outcome.price_info.slice(0, 130)}`);
    } else if (outcome.menu_images.length) {
      console.log(`  📷 구조화 가격 없음 / 가격표 이미지 ${outcome.menu_images.length}장`);
    } else {
      console.log(`  ⚠️ ${outcome.status}`);
    }

    if (consecutiveFails >= MAX_CONSECUTIVE_FAILS) {
      console.log(`🛑 ${MAX_CONSECUTIVE_FAILS}회 연속 fetch 실패 — 저장 후 중단`);
      break;
    }
    if (index < targets.length - 1) await sleep(700 + Math.random() * 500);
  }

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const outJson = path.join(resultDir, `store-prices-${stamp}.json`);
  const outSql = path.join(resultDir, `store-prices-${stamp}.sql`);
  writeFileSync(
    outJson,
    JSON.stringify(
      {
        generated_at: new Date().toISOString(),
        offset,
        count: results.length,
        structured_price_count: results.filter((item) => item.price_info).length,
        ocr_candidate_count: results.filter((item) => item.menu_images.length).length,
        results,
      },
      null,
      2,
    ),
  );
  writeFileSync(outSql, buildSql(results));

  console.log(`\n완료: 처리 ${results.length}`);
  console.log(`- 구조화 가격 확보: ${results.filter((item) => item.price_info).length}`);
  console.log(`- 가격표 이미지 후보: ${results.filter((item) => item.menu_images.length).length}`);
  console.log(`✅ JSON 저장: ${path.relative(backendDir, outJson)}`);
  console.log(`✅ SQL 저장: ${path.relative(backendDir, outSql)}`);

  if (applyLocal) applyResultsToLocal(results);
}

async function fetchPrice(store, cached) {
  let place = cached?.place_id
    ? { id: cached.place_id, name: cached.place_name ?? store.name }
    : null;

  if (!place) {
    const query = SEARCH_QUERY_OVERRIDES[store.name] ?? String(store.name ?? "").trim();
    if (!query) return emptyOutcome("empty-query");
    const x = store.longitude ? String(store.longitude) : DEFAULT_X;
    const y = store.latitude ? String(store.latitude) : DEFAULT_Y;
    const listUrl = `https://pcmap.place.naver.com/place/list?query=${encodeURIComponent(query)}&x=${x}&y=${y}&clientX=${x}&clientY=${y}&display=5&locale=ko&svcName=map_pcv5`;
    const listHtml = await fetchText(listUrl);
    if (!listHtml) return emptyOutcome("list-fetch-failed", listUrl);
    const listState = parseApolloState(listHtml);
    if (!listState) return emptyOutcome("list-no-apollo-state", listUrl);
    place = pickMatchingPlace(listState, query);
    if (!place) return emptyOutcome("no-confident-match", listUrl);
  }

  const detailUrl = `https://pcmap.place.naver.com/place/${place.id}/home`;
  const detailHtml = await fetchText(detailUrl);
  if (!detailHtml) return emptyOutcome("detail-fetch-failed", detailUrl, place);
  const detailState = parseApolloState(detailHtml);
  if (!detailState) return emptyOutcome("detail-no-apollo-state", detailUrl, place);

  const base = detailState[`PlaceDetailBase:${place.id}`] ?? {};
  if (base.hidePrice) return emptyOutcome("hide-price", detailUrl, place);

  const priceInfo = extractStructuredPrices(detailState);
  const menuImages = extractMenuImages(detailState);
  return {
    matched: true,
    status: priceInfo ? "structured-price" : menuImages.length ? "ocr-candidate" : "no-price-data",
    place_id: place.id,
    place_name: place.name,
    source_url: detailUrl,
    price_info: priceInfo,
    menu_images: menuImages,
  };
}

function emptyOutcome(status, sourceUrl = "", place = null) {
  return {
    matched: false,
    status,
    place_id: place?.id ?? "",
    place_name: place?.name ?? "",
    source_url: sourceUrl,
    price_info: "",
    menu_images: [],
  };
}

function pickMatchingPlace(state, storeName) {
  const rootQuery = state.ROOT_QUERY ?? {};
  const key = Object.keys(rootQuery).find((item) => item.startsWith("placeList("));
  if (!key) return null;
  for (const item of rootQuery[key]?.businesses?.items ?? []) {
    const id = (item?.__ref ?? "").replace("PlaceListBusinessesItem:", "");
    if (!id) continue;
    const candidate = state[`PlaceListBusinessesItem:${id}`] ?? {};
    if (namesLikelyMatch(storeName, candidate.name ?? "")) {
      return { id, name: candidate.name ?? "" };
    }
  }
  return null;
}

function extractStructuredPrices(state) {
  const rows = Object.entries(state)
    .filter(([key, value]) => key.startsWith("Menu:") && value?.name)
    .sort(([, a], [, b]) => Number(a?.index ?? 0) - Number(b?.index ?? 0))
    .map(([, value]) => formatMenu(value))
    .filter(Boolean);
  return unique(rows).slice(0, 15).join(" / ").slice(0, 1200);
}

function formatMenu(menu) {
  const name = cleanText(menu?.name);
  if (!name) return "";

  const raw = menu?.price;
  if (typeof raw === "number" && Number.isFinite(raw) && raw >= 1000) {
    return `${name} ${formatWon(raw)}`;
  }

  const text = cleanText(raw);
  if (/가격\s*변동|변동/i.test(text)) return `${name} 가격 변동`;

  // 네이버는 가격 범위를 "20000~30000"처럼 문자열로 내려준다. 숫자가 둘 이상일 때
  // 문자를 모두 지워 합치면 2,000,030,000원이 되므로 각 금액을 따로 파싱한다.
  const amounts = [...text.matchAll(/[0-9][0-9,]*/g)]
    .map((match) => Number(match[0].replaceAll(",", "")))
    .filter((value) => Number.isFinite(value) && value >= 1000);
  if (amounts.length >= 2) {
    return `${name} ${unique(amounts).map(formatWon).join("~")}`;
  }
  if (amounts.length === 1) {
    const suffix = /부터/.test(text) ? "부터" : "";
    return `${name} ${formatWon(amounts[0])}${suffix}`;
  }

  // 서비스명 자체에 명시된 원화 금액은 보존하되, 0원 안내·단순 숫자는 가격으로 보지 않는다.
  const embedded = [...name.matchAll(/([1-9][0-9]{0,2}(?:,[0-9]{3})+)\s*원?/g)]
    .map((match) => Number(match[1].replaceAll(",", "")))
    .filter((value) => value >= 1000);
  return embedded.length ? name : "";
}

function formatWon(value) {
  return `${Number(value).toLocaleString("ko-KR")}원`;
}

function extractMenuImages(state) {
  const rootQuery = state.ROOT_QUERY ?? {};
  const placeDetailKey = Object.keys(rootQuery).find((key) => key.startsWith("placeDetail("));
  const menuImages = rootQuery[placeDetailKey]?.menuImages;
  if (!Array.isArray(menuImages)) return [];
  return unique(menuImages.map((item) => item?.imageUrl).filter(Boolean)).slice(0, 8);
}

function loadCachedPlaces() {
  const files = readdirSync(resultDir)
    .filter((name) => /^store-enrichment-.*\.json$/.test(name))
    .sort();
  const map = new Map();
  for (const file of files) {
    try {
      const data = JSON.parse(readFileSync(path.join(resultDir, file), "utf8"));
      for (const item of data.results ?? []) {
        if (item.store_key && item.place_id && item.matched) {
          map.set(item.store_key, { place_id: item.place_id, place_name: item.place_name });
        }
      }
    } catch {
      // 손상된 과거 결과 파일은 건너뛴다.
    }
  }
  return map;
}

function buildSql(results) {
  const lines = ["BEGIN TRANSACTION;"];
  for (const item of results) {
    if (!item.price_info) continue;
    const emptyOnly = overwrite ? "" : "\n  AND (price_info IS NULL OR TRIM(price_info) = '')";
    lines.push(`\nUPDATE stores\nSET price_info = ${sqlString(item.price_info)}\nWHERE store_key = ${sqlString(item.store_key)}\n  AND is_curated = 1${emptyOnly};`);
  }
  lines.push("COMMIT;");
  return lines.join("\n");
}

function applyResultsToLocal(results) {
  const priced = results.filter((item) => item.price_info);
  if (!priced.length) {
    console.log("ℹ️ 로컬 D1에 반영할 새 구조화 가격이 없습니다.");
    return;
  }

  for (let index = 0; index < priced.length; index += 25) {
    const chunk = priced.slice(index, index + 25);
    const chunkPath = path.join(resultDir, `.store-prices-apply-${process.pid}-${index / 25}.sql`);
    writeFileSync(chunkPath, buildSql(chunk));
    try {
      const result = spawnSync(
        "npx",
        ["wrangler", "d1", "execute", "dog_kindergarden_db", "--local", "--file", chunkPath],
        { cwd: backendDir, stdio: "inherit" },
      );
      if (result.status !== 0) process.exit(result.status ?? 1);
    } finally {
      try { unlinkSync(chunkPath); } catch { /* 이미 지워졌으면 무시 */ }
    }
  }
  console.log("✅ 로컬 D1 구조화 가격 반영 완료");
}

function cleanText(value) {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}
