#!/usr/bin/env node
/**
 * 네이버 플레이스 공개 페이지(서버 렌더링 Apollo State)에서 가게 가격 정보를 수집한다.
 *
 * 목적:
 * - 네이버맵에서 가게 이름 검색 시 나오는 첫 번째 결과의 가격/요금 메뉴를 수집
 *
 * 배경:
 * - 이전 버전은 Chrome을 AppleScript로 조작해 화면 텍스트를 읽었으나, 검색 결과 목록이
 *   교차 출처(map.naver.com → pcmap.place.naver.com) iframe 안에 있어 DOM 접근이
 *   항상 null이라 100% 실패했다(브라우저 동일 출처 정책).
 * - 같은 목록/상세 화면이 서버 렌더링될 때 window.__APOLLO_STATE__에 값(JSON)이 그대로
 *   내려오므로, Chrome 없이 공개 HTML을 fetch해 그 값을 읽는 편이 더 정확하고 안정적이다.
 *
 * 원칙:
 * - 캡차/로그인/차단 우회 안 함 — 일반 GET으로 받아지는 공개 HTML만 읽음
 * - hidePrice가 true인 가게는 업주가 가격 비공개 처리한 것이므로 수집하지 않음
 * - 결과는 crawl-results/*.json/sql에 저장
 *
 * 사용:
 *   node scripts/scrape-naver-place-prices.mjs --input=crawl-results/xxx.json --limit=5
 *
 * DB 반영:
 *   node scripts/scrape-naver-place-prices.mjs --input=crawl-results/xxx.json --limit=5 --apply-local
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fetchText, namesLikelyMatch, parseApolloState, parseArgs, sleep, sqlString, unique } from "./lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendDir = path.resolve(__dirname, "..");
const resultDir = path.join(backendDir, "crawl-results");
const args = parseArgs(process.argv.slice(2));
const input = args.input ? path.resolve(backendDir, String(args.input)) : latestJson();
const limit = Number(args.limit ?? 5);
const applyLocal = Boolean(args["apply-local"]);

// 가게 좌표를 모를 때 쓰는 기본 검색 중심점(서울시청) — 검색 순위가 위치에 살짝 가중되므로
// 입력 JSON에 latitude/longitude가 있으면 그 값을 우선 쓴다.
const DEFAULT_X = "126.9779692";
const DEFAULT_Y = "37.5662952";

if (!input) {
  console.error("❌ input JSON이 없습니다. 먼저 npm run crawl:seoul 로 대상 JSON을 만드세요.");
  process.exit(1);
}

mkdirSync(resultDir, { recursive: true });

const source = JSON.parse(readFileSync(input, "utf8"));
const targets = (source.results ?? []).slice(0, limit);
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const outJson = path.join(resultDir, `naver-place-prices-${stamp}.json`);
const outSql = path.join(resultDir, `naver-place-prices-${stamp}.sql`);

main().catch((err) => {
  console.error("❌ 네이버 플레이스 가격 수집 실패:", err?.message ?? err);
  process.exit(1);
});

async function main() {
  console.log(`🚀 네이버 플레이스 가격 수집 시작: ${path.relative(backendDir, input)}, limit=${targets.length}`);

  const results = [];
  for (const [idx, item] of targets.entries()) {
    const query = String(item.store_name ?? "").trim();
    const x = item.longitude ? String(item.longitude) : DEFAULT_X;
    const y = item.latitude ? String(item.latitude) : DEFAULT_Y;
    console.log(`(${idx + 1}/${targets.length}) ${item.store_name}`);

    const outcome = await fetchFirstPlacePrice(query, x, y);
    results.push({
      store_key: item.store_key,
      store_name: item.store_name,
      query,
      ...outcome,
    });
    console.log(
      outcome.matched
        ? `  ✅ ${outcome.place_name} — ${outcome.price_info.slice(0, 100)}`
        : `  ⚠️ ${outcome.click_result}`,
    );

    if (idx < targets.length - 1) await sleep(800 + Math.random() * 400);
  }

  writeFileSync(
    outJson,
    JSON.stringify({ input: path.relative(backendDir, input), count: results.length, results }, null, 2),
  );
  writeFileSync(outSql, buildSql(results));
  console.log(`✅ JSON 저장: ${path.relative(backendDir, outJson)}`);
  console.log(`✅ SQL 저장: ${path.relative(backendDir, outSql)}`);

  if (applyLocal) {
    const res = spawnSync("npx", ["wrangler", "d1", "execute", "dog_kindergarden_db", "--local", "--file", outSql], {
      cwd: backendDir,
      stdio: "inherit",
    });
    if (res.status !== 0) process.exit(res.status ?? 1);
    console.log("✅ 로컬 D1 가격 반영 완료");
  }
}

async function fetchFirstPlacePrice(query, x, y) {
  if (!query) return { source_url: "", click_result: "empty-query", price_info: "", matched: false };

  const listUrl = `https://pcmap.place.naver.com/place/list?query=${encodeURIComponent(query)}&x=${x}&y=${y}&clientX=${x}&clientY=${y}&display=5&locale=ko&svcName=map_pcv5`;
  const listHtml = await fetchText(listUrl);
  if (!listHtml) return { source_url: listUrl, click_result: "list-fetch-failed", price_info: "", matched: false };

  const listState = parseApolloState(listHtml);
  if (!listState) return { source_url: listUrl, click_result: "list-no-apollo-state", price_info: "", matched: false };

  const picked = pickMatchingPlaceId(listState, query);
  if (!picked) return { source_url: listUrl, click_result: "no-confident-match", price_info: "", matched: false };

  const { id: firstId, name: placeName } = picked;
  const detailUrl = `https://pcmap.place.naver.com/place/${firstId}/home`;
  const detailHtml = await fetchText(detailUrl);
  if (!detailHtml) {
    return { place_id: firstId, place_name: placeName, source_url: detailUrl, click_result: "detail-fetch-failed", price_info: "", matched: false };
  }

  const detailState = parseApolloState(detailHtml);
  if (!detailState) {
    return { place_id: firstId, place_name: placeName, source_url: detailUrl, click_result: "detail-no-apollo-state", price_info: "", matched: false };
  }

  const base = detailState[`PlaceDetailBase:${firstId}`];
  if (base?.hidePrice) {
    return { place_id: firstId, place_name: placeName, source_url: detailUrl, click_result: "hide-price", price_info: "", matched: false };
  }

  const priceInfo = extractMenuPriceInfo(detailState);
  return {
    place_id: firstId,
    place_name: placeName,
    source_url: detailUrl,
    click_result: priceInfo ? "matched" : "no-menu-data",
    price_info: priceInfo,
    matched: Boolean(priceInfo),
  };
}

// 검색 1위를 무조건 채택하면 안 된다 — 실측 결과 "대학로 애견카페" 검색 1위가 전혀 다른
// 업종의 "미어캣파크 이색 체험 동물 카페"였고(2위가 정답), "견생유치원"(서울) 검색은
// 결과 전부가 30km 넘게 떨어진 인천 업체였으며, "THE 발라당호텔"은 좌표가 1m 차이인
// "THE발라당고양이호텔"(고양이 전용 지점)이 1위였다 — 같은 건물이라 거리 필터로도 못 거른다.
// 그래서 이름이 실질적으로 같다고 볼 수 있는 후보만 채택하고, 없으면 매칭 실패로 둔다.
function pickMatchingPlaceId(state, storeName) {
  const rootQuery = state.ROOT_QUERY ?? {};
  const key = Object.keys(rootQuery).find((k) => k.startsWith("placeList("));
  if (!key) return null;
  const items = rootQuery[key]?.businesses?.items ?? [];

  for (const item of items) {
    const id = (item?.__ref ?? "").replace("PlaceListBusinessesItem:", "");
    if (!id) continue;
    const name = state[`PlaceListBusinessesItem:${id}`]?.name ?? "";
    if (namesLikelyMatch(storeName, name)) return { id, name };
  }
  return null;
}

function extractMenuPriceInfo(state) {
  // 일부 가게는 메뉴란을 안내문구(예: "문자 주시면 2원")로 채워둬서 실제 가격이 아닌
  // 값이 섞여 들어온다 — 애견 돌봄/미용 요금이 1,000원 밑으로 내려갈 일은 없으므로 걸러낸다.
  const menus = Object.entries(state)
    .filter(([k, v]) => k.startsWith("Menu:") && v?.name && Number(v?.price) >= 1000)
    .sort((a, b) => (a[1].index ?? 0) - (b[1].index ?? 0))
    .map(([, v]) => `${v.name} ${formatWon(v.price)}`);
  return unique(menus).slice(0, 12).join(" / ").slice(0, 1000);
}

function formatWon(price) {
  const n = Number(price);
  if (!Number.isFinite(n) || n <= 0) return String(price);
  return `${n.toLocaleString("ko-KR")}원`;
}

function buildSql(results) {
  const lines = ["BEGIN TRANSACTION;"];
  for (const r of results) {
    if (!r.price_info) continue;
    lines.push(`
UPDATE stores
SET price_info = ${sqlString(r.price_info)}
WHERE store_key = ${sqlString(r.store_key)};`);
  }
  lines.push("COMMIT;");
  return lines.join("\n");
}

function latestJson() {
  try {
    const res = spawnSync("bash", ["-lc", "ls -t crawl-results/seoul-store-details-*.json 2>/dev/null | head -1"], {
      cwd: backendDir,
      encoding: "utf8",
    });
    const p = res.stdout.trim();
    return p ? path.join(backendDir, p) : "";
  } catch {
    return "";
  }
}

