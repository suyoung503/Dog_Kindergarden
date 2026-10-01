#!/usr/bin/env node
/**
 * 네이버 플레이스 공개 페이지에서 가게 상세 보강 정보를 수집한다.
 *
 * 수집 대상:
 * - 영업/운영시간: 네이버에 노출된 영업시간, 메뉴·업체 소개에 명시된 운영시간
 * - 추가 이미지: 업체가 직접 등록한 사진만 최대 5장(방문자 사진은 제외)
 * - 편의 태그: 대형견 가능, 픽업/픽드랍, 운동장/놀이터
 *
 * 태그 판정 원칙:
 * - 업체 정보·가격표·업체 소개를 우선하고, 없으면 공개 방문자/블로그 리뷰 문구를 보조 근거로 쓴다.
 * - 긍정 근거가 있을 때만 1로 갱신한다. 키워드가 없다는 이유로 0(불가)이라고 단정하지 않는다.
 * - "대형견 불가", "픽업 불가"처럼 부정 표현이 가까이 있으면 긍정 판정에서 제외한다.
 * - 근거 문장은 DB 컬럼을 늘리지 않고 결과 JSON에 남긴다.
 *
 * 원칙:
 * - 캡차·로그인·차단을 우회하지 않고 일반 GET으로 제공되는 공개 HTML만 읽는다.
 * - 네이버 요청 사이에 지연을 두고 연속 실패 시 중단한다.
 *
 * 사용:
 *   node scripts/crawl-store-enrichment.mjs --limit=5
 *   node scripts/crawl-store-enrichment.mjs --limit=50 --apply-local
 */

import { mkdirSync, unlinkSync, writeFileSync } from "node:fs";
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
const limit = Number(args.limit ?? 50);
const applyLocal = Boolean(args["apply-local"]);
const offset = Number(args.offset ?? 0);
const targetName = String(args.name ?? args["store-name"] ?? "").trim();
const MAX_CONSECUTIVE_FAILS = 5;
const MAX_EXTRA_IMAGES = 5;

const DEFAULT_X = "126.9779692";
const DEFAULT_Y = "37.5662952";
const STORES_API = "https://matgyeomung-api.dog-kindergarden.workers.dev/api/stores";

const SEARCH_QUERY_OVERRIDES = {
  "제주네 애견유치원": "제주네 애견",
  "놀러오개 애견유치원 애견호텔 애견미용 서초점": "놀러오개 서초점",
  "디어캐닌 DEAR CANINE": "디어캐닌",
  "도기프렌즈 웰니스센터": "도기프렌즈 강아지유치원",
};

// 네이버 플레이스 검색에서 사라졌지만 업체가 직접 관리하는 공개 프로필이 확인되는 예외.
// 일반 블로그/광고성 모음글은 사용하지 않고, 최근 활동이 표시되는 업체 프로필만 수동 검증 후 둔다.
const VERIFIED_FALLBACK_DETAILS = {
  "HRC 런 클럽 독피트니스 한남점": {
    source_url: "https://www.daangn.com/kr/local-profile/hrc-%EB%9F%B0-%ED%81%B4%EB%9F%BD-%EB%B0%98%EB%A0%A4%EA%B2%AC-%EB%9F%AC%EB%8B%9D-%EC%97%B0%EC%8A%B5%EC%9E%A5-uacw7kf25srw/",
    open_time: "매일 08:00~24:00",
    image_urls: [
      "https://img.kr.gcp-karroter.net/business-profile/bizPlatform/profile/27010621/1749369229364/Y3Y1dmVMVEVud2xiWGdHOUVTQzFw.jpeg?q=95&s=1440x1440&t=inside&service=business-profile",
      "https://img.kr.gcp-karroter.net/capri/bizPlatform/profile/27010621/1749274042217/SU1HXzcyMjQuanBlZw==.jpeg?q=95&s=1440x1440&t=inside&service=business-profile",
      "https://img.kr.gcp-karroter.net/capri/bizPlatform/profile/27010621/1749274042218/SU1HXzcyMTIuanBlZw==.jpeg?q=95&s=1440x1440&t=inside&service=business-profile",
      "https://img.kr.gcp-karroter.net/capri/bizPlatform/profile/27010621/1749274042481/SU1HXzcxOTIuanBlZw==.jpeg?q=95&s=1440x1440&t=inside&service=business-profile",
    ],
  },
};

const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const outJson = path.join(resultDir, `store-enrichment-${stamp}.json`);
const outSql = path.join(resultDir, `store-enrichment-${stamp}.sql`);

mkdirSync(resultDir, { recursive: true });

main().catch((error) => {
  console.error("❌ 가게 상세 보강 실패:", error?.message ?? error);
  process.exit(1);
});

async function main() {
  const response = await fetch(STORES_API);
  if (!response.ok) throw new Error(`가게 목록 조회 실패: ${response.status}`);
  const stores = await response.json();
  const filteredStores = targetName
    ? stores.filter((store) => String(store.name ?? "").includes(targetName))
    : stores;
  const targets = filteredStores.slice(offset, offset + limit);

  if (targetName && targets.length === 0) {
    throw new Error(`가게 목록에서 이름을 찾지 못했습니다: ${targetName}`);
  }

  console.log(
    targetName
      ? `🚀 상세 보강 시작: '${targetName}' 검색 결과 ${filteredStores.length}곳`
      : `🚀 상세 보강 시작: 전체 ${stores.length}곳 중 ${offset + 1}~${offset + targets.length}번째`,
  );

  const results = [];
  let consecutiveFails = 0;

  for (const [index, store] of targets.entries()) {
    console.log(`(${index + 1}/${targets.length}) ${store.name}`);
    const outcome = await fetchEnrichment(store);
    results.push({
      store_key: store.store_key,
      store_name: store.name,
      ...outcome,
    });

    if (outcome.status === "list-fetch-failed" || outcome.status === "detail-fetch-failed") {
      consecutiveFails += 1;
    } else {
      consecutiveFails = 0;
    }

    if (outcome.matched) {
      const tags = [
        outcome.large_dog ? "대형견" : "",
        outcome.pickup ? "픽업" : "",
        outcome.playground ? "운동장" : "",
      ].filter(Boolean);
      console.log(
        `  ✅ 사진 ${outcome.image_urls.length}장 / 영업시간 ${outcome.open_time || "미확인"}` +
          `${tags.length ? ` / ${tags.join(", ")}` : ""}`,
      );
    } else {
      console.log(`  ⚠️ ${outcome.status}`);
    }

    if (consecutiveFails >= MAX_CONSECUTIVE_FAILS) {
      console.log(`🛑 ${MAX_CONSECUTIVE_FAILS}회 연속 fetch 실패 — 현재 결과를 저장하고 중단`);
      break;
    }

    if (index < targets.length - 1) await sleep(900 + Math.random() * 500);
  }

  writeFileSync(
    outJson,
    JSON.stringify(
      {
        generated_at: new Date().toISOString(),
        offset,
        count: results.length,
        results,
      },
      null,
      2,
    ),
  );
  writeFileSync(outSql, buildSql(results));

  const matched = results.filter((item) => item.matched);
  console.log(`\n완료: 처리 ${results.length} / 매칭 ${matched.length}`);
  console.log(`- 영업시간: ${matched.filter((item) => item.open_time).length}`);
  console.log(`- 추가 이미지: ${matched.filter((item) => item.image_urls.length > 1).length}`);
  console.log(`- 대형견: ${matched.filter((item) => item.large_dog).length}`);
  console.log(`- 픽업: ${matched.filter((item) => item.pickup).length}`);
  console.log(`- 운동장: ${matched.filter((item) => item.playground).length}`);
  console.log(`✅ JSON 저장: ${path.relative(backendDir, outJson)}`);
  console.log(`✅ SQL 저장: ${path.relative(backendDir, outSql)}`);

  if (applyLocal) applyResultsToLocal(results);
}

async function fetchEnrichment(store) {
  const query = SEARCH_QUERY_OVERRIDES[store.name] ?? String(store.name ?? "").trim();
  if (!query) return emptyOutcome("empty-query");

  const x = store.longitude ? String(store.longitude) : DEFAULT_X;
  const y = store.latitude ? String(store.latitude) : DEFAULT_Y;
  const listUrl = `https://pcmap.place.naver.com/place/list?query=${encodeURIComponent(query)}&x=${x}&y=${y}&clientX=${x}&clientY=${y}&display=5&locale=ko&svcName=map_pcv5`;
  const listHtml = await fetchText(listUrl);
  if (!listHtml) return emptyOutcome("list-fetch-failed", listUrl);

  const listState = parseApolloState(listHtml);
  if (!listState) return emptyOutcome("list-no-apollo-state", listUrl);

  const picked = pickMatchingPlace(listState, query);
  if (!picked) return fallbackOutcome(store, "no-confident-match", listUrl);

  const detailUrl = `https://pcmap.place.naver.com/place/${picked.id}/review/visitor`;
  const detailHtml = await fetchText(detailUrl);
  if (!detailHtml) return emptyOutcome("detail-fetch-failed", detailUrl, picked);

  const detailState = parseApolloState(detailHtml);
  if (!detailState) return emptyOutcome("detail-no-apollo-state", detailUrl, picked);

  const base = detailState[`PlaceDetailBase:${picked.id}`] ?? {};
  const imageUrls = extractBusinessImages(detailState, picked.id, picked.imageUrl);
  const evidenceSources = extractEvidenceSources(detailState, base, detailHtml);
  const flags = extractFlags(evidenceSources);

  return {
    matched: true,
    status: "matched",
    place_id: picked.id,
    place_name: picked.name,
    source_url: detailUrl,
    open_time: extractOpenTime(detailState, base, evidenceSources),
    image_url: imageUrls[0] ?? picked.imageUrl ?? "",
    image_urls: imageUrls,
    large_dog: flags.large_dog.value,
    pickup: flags.pickup.value,
    playground: flags.playground.value,
    evidence: {
      large_dog: flags.large_dog.evidence,
      pickup: flags.pickup.evidence,
      playground: flags.playground.evidence,
    },
  };
}

function fallbackOutcome(store, originalStatus, originalUrl) {
  const fallback = VERIFIED_FALLBACK_DETAILS[store.name];
  if (!fallback) return emptyOutcome(originalStatus, originalUrl);
  const imageUrls = unique(fallback.image_urls ?? []).slice(0, MAX_EXTRA_IMAGES);
  return {
    matched: true,
    status: "matched-fallback-profile",
    place_id: "",
    place_name: store.name,
    source_url: fallback.source_url,
    open_time: fallback.open_time ?? "",
    image_url: imageUrls[0] ?? "",
    image_urls: imageUrls,
    large_dog: Boolean(fallback.large_dog),
    pickup: Boolean(fallback.pickup),
    playground: Boolean(fallback.playground),
    evidence: fallback.evidence ?? { large_dog: [], pickup: [], playground: [] },
  };
}

function emptyOutcome(status, sourceUrl = "", picked = null) {
  return {
    matched: false,
    status,
    place_id: picked?.id ?? "",
    place_name: picked?.name ?? "",
    source_url: sourceUrl,
    open_time: "",
    image_url: "",
    image_urls: [],
    large_dog: false,
    pickup: false,
    playground: false,
    evidence: { large_dog: [], pickup: [], playground: [] },
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
      return { id, name: candidate.name ?? "", imageUrl: candidate.imageUrl ?? "" };
    }
  }
  return null;
}

function extractBusinessImages(state, placeId, representativeImage) {
  const businessPhotos = Object.entries(state)
    .filter(([key, value]) =>
      key.startsWith(`PlaceDetailTopPhotoItem:${placeId}_business_`) &&
      value?.mediaFormat === "image" &&
      value?.mediaSource === "business",
    )
    .sort(([a], [b]) => numericSuffix(a) - numericSuffix(b))
    .map(([, value]) => value.originalUrl ?? value.thumbnailUrl)
    .filter(Boolean);

  return unique([representativeImage, ...businessPhotos]).slice(0, MAX_EXTRA_IMAGES);
}

function numericSuffix(value) {
  return Number(String(value).match(/_(\d+)$/)?.[1] ?? 999);
}

function extractEvidenceSources(state, base, html) {
  const official = [];
  const page = [];
  const review = [];

  official.push(base.name, base.category, base.road, ...(base.conveniences ?? []));

  const rootQuery = state.ROOT_QUERY ?? {};
  const placeDetailKey = Object.keys(rootQuery).find((key) => key.startsWith("placeDetail("));
  const placeDetail = rootQuery[placeDetailKey] ?? {};
  official.push(
    placeDetail.description,
    ...(placeDetail.informationTab?.keywordList ?? []),
    placeDetail.informationTab?.parkingInfo?.description,
  );

  for (const facilityRef of placeDetail.informationTab?.facilities ?? []) {
    const facility = facilityRef?.__ref ? state[facilityRef.__ref] : facilityRef;
    official.push(facility?.name, facility?.description);
  }

  for (const [key, value] of Object.entries(state)) {
    if (key.startsWith("Menu:")) {
      official.push(value?.name, value?.description);
    } else if (key.startsWith("FsasReview:")) {
      review.push(value?.title, value?.contents);
    } else if (key.startsWith("VisitorReview:")) {
      review.push(value?.body, value?.reply?.body);
    }
  }

  // Apollo 객체 밖의 서버 렌더링 영역에 현재 영업시간·편의 문구가 들어오는 경우가 있다.
  page.push(htmlToVisibleText(html).slice(0, 30000));

  return {
    official: unique(official.map(cleanText)).filter(Boolean),
    page: unique(page.map(cleanText)).filter(Boolean),
    review: unique(review.map(cleanText)).filter(Boolean),
  };
}

function extractFlags(sources) {
  return {
    large_dog: detectFlag(sources, {
      officialPositive: [
        /(?:대형견|중대형견)\s*(?:유치원|호텔|호텔링|케어|가능|환영|전용|분리|입실|이용|가격|요금)/i,
        /소형견\s*[,·/]?\s*중형견\s*[,·/]?\s*대형견/i,
      ],
      reviewPositive: [
        /(?:대형견|중대형견)[^.!?\n]{0,45}(?:맡기|다니|이용|입실|호텔|유치원|케어|분리|공간|친구|있었|많아|많았|전문)/i,
        /(?:맡기|다니|이용|입실)[^.!?\n]{0,35}(?:대형견|중대형견)/i,
      ],
      negative: [
        /대형견[^.!?\n]{0,20}(?:불가|금지|제한|입장\s*불가|이용\s*불가|받지\s*않|힘들|어렵|무서워|없|못\s*보)/i,
        /대형견보다는/i,
      ],
    }),
    pickup: detectFlag(sources, {
      officialPositive: [
        /픽업\s*(?:서비스|가능|운영|차량|요금|비용|편도|왕복|\()/i,
        /(?:정기권?\s*)?픽업\s*[/&]\s*(?:드랍|드롭|샌딩)/i,
        /픽[드드]랍|픽드롭/i,
        /펫\s*셔틀/i,
        /등하원\s*(?:차량|서비스|운행)/i,
        /(?:등원|하원)\s*차량/i,
        /차량\s*운행/i,
      ],
      reviewPositive: [
        /픽업(?:도|까지)?\s*해\s*주/i,
        /픽업을?\s*(?:부탁|이용)/i,
        /픽[드드]랍|픽드롭/i,
        /펫\s*셔틀/i,
        /등하원\s*(?:차량|서비스|운행)/i,
        /차량\s*운행/i,
      ],
      negative: [/(?:픽업|픽드랍|픽드롭|셔틀)[^.!?\n]{0,10}(?:불가|안\s*함|없음|중단)/i],
      reviewNegative: [/픽업하러/i, /픽업할\s*수/i, /픽업이?\s*마감/i, /픽업\s*[/&]\s*드롭하기/i],
    }),
    playground: detectFlag(sources, {
      officialPositive: [
        /^(?:반려견|애견)놀이터$/i,
        /(?:실내|실외|야외|옥상|루프탑|테라스|잔디|넓은|전용)[^.!?\n]{0,25}(?:운동장|놀이터)/i,
        /(?:운동장|놀이터)[^.!?\n]{0,25}(?:있|보유|갖추|마련|시설|공간|이용|운영)/i,
        /반려견\s*(?:전용\s*)?마당/i,
      ],
      reviewPositive: [
        /(?:내부|실내|실외|야외|옥상|루프탑|테라스|잔디|넓은)[^.!?\n]{0,25}(?:운동장|놀이터)/i,
        /(?:운동장|놀이터)[^.!?\n]{0,30}(?:있|보유|갖추|마련|공간|넓|이용|깔려)/i,
        /유치원에\s*있는\s*(?:마당|운동장)/i,
      ],
      negative: [/(?:운동장|놀이터|마당)[^.!?\n]{0,10}(?:없음|불가|폐쇄|이용\s*불가)/i],
      reviewNegative: [/(?:운동장|놀이터)[^.!?\n]{0,20}(?:데려가|소풍|대관)/i, /(?:애견)?놀이터에서\s*만난/i],
    }),
  };
}

function detectFlag(sources, patterns) {
  // 업체가 직접 올린 정보가 있으면 가장 신뢰한다. 리뷰는 더 엄격한 문맥 패턴으로만 보조한다.
  const groups = [
    { texts: sources.official, positive: patterns.officialPositive ?? [] },
    { texts: sources.review, positive: patterns.reviewPositive ?? [] },
  ];
  for (const { texts, positive } of groups) {
    const evidence = [];
    for (const text of texts) {
      const negatives = [...(patterns.negative ?? []), ...(texts === sources.review ? patterns.reviewNegative ?? [] : [])];
      if (negatives.some((pattern) => pattern.test(text))) continue;
      if (positive.some((pattern) => pattern.test(text))) {
        evidence.push(shortEvidence(text, positive));
      }
    }
    if (evidence.length) return { value: true, evidence: unique(evidence).slice(0, 3) };
  }
  return { value: false, evidence: [] };
}

function shortEvidence(text, patterns) {
  const match = patterns.map((pattern) => text.match(pattern)).find(Boolean);
  if (!match) return text.slice(0, 180);
  const start = Math.max(0, match.index - 60);
  const end = Math.min(text.length, match.index + match[0].length + 80);
  return text.slice(start, end).trim();
}

function extractOpenTime(state, base, sources) {
  const structured = extractStructuredOpeningHours(state) || formatOpeningHours(base.openingHours);
  if (structured) return structured;

  const candidates = [...sources.official, ...sources.page, ...sources.review];
  const patterns = [
    /(?:영업시간|운영시간|이용시간|유치원\s*운영|호텔\s*운영)\s*[:：]?\s*([^.!?\n]{0,70}?(?:\d{1,2}(?::\d{2})?\s*(?:~|-|–)\s*\d{1,2}(?::\d{2})?|24시간|연중무휴))/i,
    /((?:매일|평일|주말|월(?:요일)?(?:\s*~\s*금(?:요일)?)?|토(?:요일)?|일(?:요일)?)\s*[:：]?\s*\d{1,2}:\d{2}\s*(?:~|-|–)\s*\d{1,2}:\d{2})/i,
    /((?:24시간\s*(?:365일\s*)?연중무휴|연중무휴))/i,
  ];

  const found = [];
  for (const text of candidates) {
    for (const pattern of patterns) {
      const match = text.match(pattern);
      const value = cleanText(match?.[1] ?? match?.[0] ?? "");
      if (value && /\d|연중무휴/.test(value)) found.push(value);
    }
  }
  return unique(found).slice(0, 4).join(" / ").slice(0, 500);
}

function extractStructuredOpeningHours(state) {
  const rootQuery = state.ROOT_QUERY ?? {};
  const placeDetailKey = Object.keys(rootQuery).find((key) => key.startsWith("placeDetail("));
  const schedules = rootQuery[placeDetailKey]?.newBusinessHours;
  if (!Array.isArray(schedules) || schedules.length === 0) return "";

  const sections = [];
  for (const schedule of schedules) {
    const grouped = new Map();
    for (const item of schedule?.businessHours ?? []) {
      const label = formatWorkingHours(item);
      if (!label) continue;
      const days = grouped.get(label) ?? [];
      if (item?.day) days.push(item.day);
      grouped.set(label, days);
    }

    const rows = [...grouped.entries()].map(([label, days]) =>
      `${days.length ? days.join("·") + " " : ""}${label}`,
    );
    if (schedule?.freeText) rows.push(cleanText(schedule.freeText));

    if (rows.length) {
      const prefix = schedules.length > 1 && schedule?.name ? `${schedule.name}: ` : "";
      sections.push(prefix + rows.join(" / "));
    }
  }
  return unique(sections).join("\n").slice(0, 1000);
}

function formatWorkingHours(item) {
  if (!item) return "";
  const hours = item.businessHours;
  const parts = [];
  if (hours?.start && hours?.end) parts.push(`${hours.start}~${hours.end}`);
  else if (item.description) parts.push(cleanText(item.description));

  if (item.breakHours?.start && item.breakHours?.end) {
    parts.push(`휴게 ${item.breakHours.start}~${item.breakHours.end}`);
  }
  if (Array.isArray(item.breakHours)) {
    for (const rest of item.breakHours) {
      if (rest?.start && rest?.end) parts.push(`휴게 ${rest.start}~${rest.end}`);
    }
  }
  if (item.lastOrderTimes?.start) parts.push(`라스트오더 ${item.lastOrderTimes.start}`);
  if (Array.isArray(item.lastOrderTimes)) {
    for (const last of item.lastOrderTimes) {
      const value = last?.time ?? last?.start ?? last;
      if (value) parts.push(`라스트오더 ${value}`);
    }
  }
  return unique(parts).join(", ");
}

function formatOpeningHours(openingHours) {
  if (!openingHours) return "";
  if (typeof openingHours === "string") return cleanText(openingHours);
  if (Array.isArray(openingHours)) {
    return openingHours.map(formatOpeningHourItem).filter(Boolean).join(" / ").slice(0, 500);
  }

  const values = [];
  for (const [key, value] of Object.entries(openingHours)) {
    if (value === null || value === undefined || typeof value === "object") continue;
    if (/time|hour|day|description|name|text/i.test(key)) values.push(String(value));
  }
  return unique(values.map(cleanText)).filter(Boolean).join(" / ").slice(0, 500);
}

function formatOpeningHourItem(item) {
  if (!item) return "";
  if (typeof item === "string") return cleanText(item);
  const day = item.day ?? item.dayOfWeek ?? item.name ?? "";
  const start = item.start ?? item.startTime ?? item.open ?? item.openTime ?? "";
  const end = item.end ?? item.endTime ?? item.close ?? item.closeTime ?? "";
  const text = item.text ?? item.description ?? "";
  return cleanText(text || [day, start && end ? `${start}~${end}` : start || end].filter(Boolean).join(" "));
}

function htmlToVisibleText(html) {
  return String(html ?? "")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function cleanText(value) {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function buildSql(results) {
  const lines = ["BEGIN TRANSACTION;"];

  for (const result of results) {
    if (!result.matched) continue;

    const updates = [];
    if (result.open_time) {
      updates.push(`open_time = CASE WHEN open_time IS NULL OR TRIM(open_time) = '' THEN ${sqlString(result.open_time)} ELSE open_time END`);
    }
    if (result.image_url) {
      updates.push(`image_url = CASE WHEN image_url IS NULL OR TRIM(image_url) = '' THEN ${sqlString(result.image_url)} ELSE image_url END`);
    }
    if (result.large_dog) updates.push("large_dog = 1");
    if (result.pickup) updates.push("pickup = 1");
    if (result.playground) updates.push("playground = 1");

    if (updates.length) {
      lines.push(`\nUPDATE stores\nSET ${updates.join(",\n    ")}\nWHERE store_key = ${sqlString(result.store_key)};`);
    }

    for (const [index, imageUrl] of result.image_urls.entries()) {
      lines.push(`\nINSERT OR IGNORE INTO store_images (store_id, image_url, sort_order)\nSELECT store_id, ${sqlString(imageUrl)}, ${index}\nFROM stores\nWHERE store_key = ${sqlString(result.store_key)};`);
    }
  }

  lines.push("COMMIT;");
  return lines.join("\n");
}

function applyResultsToLocal(results) {
  // Wrangler/Miniflare는 큰 SQL 파일을 한 번에 넣으면 SQLITE_TOOBIG이 날 수 있어 가게 20곳씩 나눈다.
  const matched = results.filter((item) => item.matched);
  for (let index = 0; index < matched.length; index += 20) {
    const chunk = matched.slice(index, index + 20);
    const chunkPath = path.join(resultDir, `.store-enrichment-apply-${process.pid}-${index / 20}.sql`);
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
  console.log("✅ 로컬 D1 상세 보강 반영 완료");
}
