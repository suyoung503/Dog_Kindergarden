#!/usr/bin/env node
/**
 * 네이버 플레이스 검색 결과의 category 필드로 업종을 확인한다.
 * 애견카페/미용/용품/병원/분양 등으로 뜨면 배제 후보로 표시한다.
 *
 * 사용:
 *   node scripts/check-naver-category.mjs --input=path.json
 */
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fetchText, namesLikelyMatch, parseApolloState, parseArgs, sleep } from "./lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendDir = path.resolve(__dirname, "..");
const resultDir = path.join(backendDir, "crawl-results");
const args = parseArgs(process.argv.slice(2));
const input = path.resolve(process.cwd(), String(args.input));
const outPath = args.out ? path.resolve(process.cwd(), String(args.out)) : path.join(resultDir, `category-check-result-${new Date().toISOString().replace(/[:.]/g, "-")}.json`);

const DEFAULT_X = "126.9779692";
const DEFAULT_Y = "37.5662952";

const EXCLUDE_CATEGORIES = [
  "미용", "카페", "용품", "병원", "분양", "펫샵", "포토", "장례", "약국",
];

mkdirSync(resultDir, { recursive: true });

main().catch((err) => {
  console.error("실패:", err?.message ?? err);
  process.exit(1);
});

async function main() {
  const source = JSON.parse(readFileSync(input, "utf8"));
  const targets = source.results ?? [];
  console.log(`카테고리 조회 시작: ${targets.length}곳`);

  const results = [];
  for (const [idx, item] of targets.entries()) {
    const query = String(item.store_name ?? "").trim();
    const outcome = await fetchCategory(query);
    const excludeHit = outcome.category ? EXCLUDE_CATEGORIES.find((kw) => outcome.category.includes(kw)) : null;
    results.push({
      store_key: item.store_key,
      store_name: item.store_name,
      ...outcome,
      exclude_suggested: Boolean(excludeHit),
      exclude_reason: excludeHit ?? "",
    });
    console.log(`(${idx + 1}/${targets.length}) ${item.store_name} -> ${outcome.category ?? outcome.status}${excludeHit ? " [배제후보:" + excludeHit + "]" : ""}`);

    if (idx < targets.length - 1) await sleep(700 + Math.random() * 400);
    if ((idx + 1) % 20 === 0) writeFileSync(outPath, JSON.stringify({ input: path.relative(backendDir, input), count: results.length, results }, null, 2));
  }

  writeFileSync(outPath, JSON.stringify({ input: path.relative(backendDir, input), count: results.length, results }, null, 2));
  console.log(`완료. 저장: ${path.relative(backendDir, outPath)}`);
}

async function fetchCategory(query) {
  if (!query) return { status: "empty-query" };
  const x = DEFAULT_X, y = DEFAULT_Y;
  const listUrl = `https://pcmap.place.naver.com/place/list?query=${encodeURIComponent(query)}&x=${x}&y=${y}&clientX=${x}&clientY=${y}&display=5&locale=ko&svcName=map_pcv5`;
  const html = await fetchText(listUrl);
  if (!html) return { status: "fetch-failed" };

  const state = parseApolloState(html);
  if (!state) return { status: "no-apollo-state" };

  const picked = pickMatchingPlace(state, query);
  if (!picked) return { status: "no-confident-match" };

  return {
    status: "matched",
    place_id: picked.id,
    place_name: picked.name,
    category: picked.category,
    categoryCodeList: picked.categoryCodeList,
  };
}

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
      return { id, name, category: obj?.category ?? "", categoryCodeList: obj?.categoryCodeList ?? [] };
    }
  }
  return null;
}

