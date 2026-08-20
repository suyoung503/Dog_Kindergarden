#!/usr/bin/env node
/**
 * 서울 애견 유치원/호텔 상세 보강 데이터 수집 스크립트
 *
 * - 기준 목록: data.go.kr 동물위탁관리업 API
 * - 보강 정보: Naver Local/Blog API + 업체 홈페이지 HTML(가능한 경우)
 * - DB 저장: stores.image_url, stores.large_dog/pickup/playground/price_info + store_images
 * - 메타정보(source/source_url/crawled_at)는 DB가 아니라 crawl-results/*.json에만 저장
 *
 * 주의:
 * - 네이버 지도 내부 비공개 API 우회/로그인/캡차 회피는 하지 않는다.
 * - 홈페이지 HTML은 robots/서비스 정책에 맞게 공개 접근 가능한 범위만 fetch한다.
 */

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs, sleep, sqlString, unique } from "./lib.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const backendDir = path.resolve(__dirname, "..");
const repoRoot = path.resolve(backendDir, "..");
const defaultXcconfig = path.join(repoRoot, "Dog_kindergarden/Base.lproj/Config/Create.xcconfig");
const resultDir = path.join(backendDir, "crawl-results");

const args = parseArgs(process.argv.slice(2));
const limit = Number(args.limit ?? 50);
const region = String(args.region ?? "서울");
const applyLocal = Boolean(args["apply-local"]);
const xcconfigPath = String(args.xcconfig ?? defaultXcconfig);
const maxExtraImages = Number(args["max-extra-images"] ?? 4);

const config = readXcconfig(xcconfigPath);
const DATA_GO_KR_SERVICE_KEY = process.env.DATA_GO_KR_SERVICE_KEY ?? config.DATA_GO_KR_SERVICE_KEY;
const NAVER_CLIENT_ID = process.env.NAVER_CLIENT_ID ?? config.NAVER_CLIENT_ID;
const NAVER_CLIENT_SECRET = process.env.NAVER_CLIENT_SECRET ?? config.NAVER_CLIENT_SECRET;
const KAKAO_REST_API_KEY = process.env.KAKAO_REST_API_KEY ?? config.KAKAO_REST_API_KEY;

assertSecret("DATA_GO_KR_SERVICE_KEY", DATA_GO_KR_SERVICE_KEY);
assertSecret("NAVER_CLIENT_ID", NAVER_CLIENT_ID);
assertSecret("NAVER_CLIENT_SECRET", NAVER_CLIENT_SECRET);

mkdirSync(resultDir, { recursive: true });

const now = new Date();
const stamp = now.toISOString().replace(/[:.]/g, "-");
const jsonPath = path.join(resultDir, `seoul-store-details-${stamp}.json`);
const sqlPath = path.join(resultDir, `seoul-store-details-${stamp}.sql`);

main().catch((error) => {
  console.error("❌ 수집 실패:", error?.message ?? error);
  process.exit(1);
});

async function main() {
  console.log(`🚀 ${region} 가게 상세 보강 수집 시작: limit=${limit}`);

  const publicStores = await fetchAnimalBoardingStores();
  const targets = publicStores
    .filter((s) => s.address.startsWith(region))
    .filter((s) => isDogCareTarget(s.name))
    .slice(0, limit);

  console.log(`📍 ${region} 대상 ${targets.length}개 선정`);

  const results = [];
  for (const [index, store] of targets.entries()) {
    await sleep(250);
    console.log(`(${index + 1}/${targets.length}) ${store.name}`);
    const detail = await enrichStore(store);
    results.push(detail);
  }

  const sql = buildSql(results);
  writeFileSync(jsonPath, JSON.stringify({ crawled_at: now.toISOString(), count: results.length, results }, null, 2));
  writeFileSync(sqlPath, sql);

  console.log(`✅ JSON 저장: ${relative(jsonPath)}`);
  console.log(`✅ SQL 저장: ${relative(sqlPath)}`);

  if (applyLocal) {
    console.log("🧩 로컬 D1 반영 중...");
    const res = spawnSync(
      "npx",
      ["wrangler", "d1", "execute", "dog_kindergarden_db", "--local", "--file", sqlPath],
      { cwd: backendDir, stdio: "inherit" },
    );
    if (res.status !== 0) process.exit(res.status ?? 1);
    console.log("✅ 로컬 D1 반영 완료");
  } else {
    console.log("ℹ️ DB 반영은 하지 않았습니다. 반영하려면 --apply-local 옵션을 사용하세요.");
  }
}

async function enrichStore(store) {
  const regionPrefix = store.address.split(/\s+/).slice(0, 2).join(" ");
  const local = await naverLocalSearch(`${regionPrefix} ${store.name}`, store.latitude, store.longitude)
    ?? await naverLocalSearch(store.name, store.latitude, store.longitude);
  await sleep(150);
  const kakaoLocal = await kakaoLocalSearch(store.name, store.latitude, store.longitude);

  await sleep(150);
  const blogs = await naverBlogSearch(`${regionPrefix} ${store.name}`);
  await sleep(150);
  const naverImages = await naverImageSearch(`${regionPrefix} ${store.name}`);
  await sleep(150);
  const kakaoImages = await kakaoImageSearch(`${regionPrefix} ${store.name}`, store.name);

  const homepageUrl = normalizeHomepageUrl(local?.link);
  const homepage = homepageUrl ? await crawlHomepage(homepageUrl) : null;

  const textParts = [
    store.name,
    store.address,
    local?.title,
    local?.category,
    local?.description,
    ...blogs.flatMap((b) => [b.title, b.description]),
    ...kakaoImages.map((i) => i.displaySitename),
    homepage?.title,
    homepage?.description,
    homepage?.text,
  ].filter(Boolean);
  const text = stripHtml(textParts.join("\n"));

  const flags = inferFlags(text);
  const priceInfo = extractPriceInfo(text);
  const images = unique([
    ...(homepage?.images ?? []),
    ...naverImages,
    ...kakaoImages.flatMap((i) => [i.imageUrl, i.thumbnailUrl]),
  ]).slice(0, 1 + maxExtraImages);
  const imageUrl = images[0] ?? "";

  return {
    store_key: store.storeKey,
    store_name: store.name,
    store_address: local?.roadAddress || local?.address || kakaoLocal?.roadAddress || kakaoLocal?.address || store.address,
    phone: local?.telephone || kakaoLocal?.phone || store.phone || "",
    store_type: store.type,
    latitude: local?.latitude ?? kakaoLocal?.latitude ?? store.latitude,
    longitude: local?.longitude ?? kakaoLocal?.longitude ?? store.longitude,
    large_dog: flags.largeDog,
    pickup: flags.pickup,
    playground: flags.playground,
    price_info: priceInfo,
    image_url: imageUrl,
    image_urls: images.slice(1),
    // 아래 메타정보는 DB에 넣지 않고 JSON에만 남긴다.
    meta: {
      source: homepageUrl ? "homepage" : "naver_search",
      source_url: homepageUrl || local?.link || "",
      crawled_at: new Date().toISOString(),
      naver_local_matched: Boolean(local),
      kakao_local_matched: Boolean(kakaoLocal),
      homepage_crawled: Boolean(homepage),
      blog_count: blogs.length,
      image_count_from_naver: naverImages.length,
      image_count_from_kakao: kakaoImages.length,
    },
  };
}

async function fetchAnimalBoardingStores() {
  // data.go.kr는 numOfRows를 1000으로 요청해도 실제로는 100으로 캡핑해서 내려준다
  // (totalCount=9985인데 응답 body.numOfRows가 100으로 echo됨) — 반드시 페이지네이션해야
  // 전국 데이터를 다 받을 수 있다. 1페이지만 받으면 등록순 앞쪽 100개만 보여서 지역 필터를
  // 걸면 대부분 빠진다.
  const numOfRows = 100;
  const items = [];
  let pageNo = 1;
  while (true) {
    const url = new URL("https://apis.data.go.kr/1741000/animal_boarding/info");
    url.searchParams.set("serviceKey", DATA_GO_KR_SERVICE_KEY);
    url.searchParams.set("pageNo", String(pageNo));
    url.searchParams.set("numOfRows", String(numOfRows));
    url.searchParams.set("type", "json");

    const json = await fetchJson(url);
    const body = json?.response?.body;
    const rawItems = body?.items?.item ?? [];
    const pageItems = Array.isArray(rawItems) ? rawItems : rawItems ? [rawItems] : [];
    if (pageItems.length === 0) break;
    items.push(...pageItems);

    const totalCount = Number(body?.totalCount ?? 0);
    if (items.length >= totalCount || pageItems.length < numOfRows) break;
    pageNo += 1;
    await sleep(120);
  }
  console.log(`📦 공공데이터 전체 수신: ${items.length}건`);

  return items.flatMap((item) => {
    const name = String(item.BPLC_NM ?? "").trim();
    const x = Number(item.CRD_INFO_X);
    const y = Number(item.CRD_INFO_Y);
    if (!name || !Number.isFinite(x) || !Number.isFinite(y) || x <= 0 || y <= 0) return [];

    const address = String(item.ROAD_NM_ADDR || item.LOTNO_ADDR || "").trim();
    if (!address) return [];

    const { lat, lon } = tmToWgs84(x, y);
    if (lat < 33 || lat > 39 || lon < 124 || lon > 132) return [];

    return [{
      name,
      address,
      phone: String(item.TELNO ?? "").trim(),
      status: String(item.SALS_STTS_NM ?? "").trim(),
      latitude: lat,
      longitude: lon,
      type: boardingType(name),
      storeKey: `${name}|${address}`,
    }];
  });
}

async function naverLocalSearch(query, lat, lon) {
  const url = new URL("https://naverapihub.apigw.ntruss.com/search/v1/local");
  url.searchParams.set("query", query);
  url.searchParams.set("display", "5");

  const json = await fetchJson(url, naverHeaders());
  const items = json?.items ?? [];
  const candidates = items.flatMap((item) => {
    const x = Number(item.mapx) / 1e7;
    const y = Number(item.mapy) / 1e7;
    if (!Number.isFinite(x) || !Number.isFinite(y)) return [];
    const dist = approxDistanceMeters(lat, lon, y, x);
    return [{ item, dist, latitude: y, longitude: x }];
  });
  const nearest = candidates.sort((a, b) => a.dist - b.dist)[0];
  if (!nearest || nearest.dist > 3000) return null;

  return {
    title: stripHtml(nearest.item.title ?? ""),
    link: nearest.item.link ?? "",
    category: nearest.item.category ?? "",
    description: nearest.item.description ?? "",
    telephone: nearest.item.telephone ?? "",
    address: nearest.item.address ?? "",
    roadAddress: nearest.item.roadAddress ?? "",
    latitude: nearest.latitude,
    longitude: nearest.longitude,
    distance: nearest.dist,
  };
}

async function naverBlogSearch(query) {
  const url = new URL("https://naverapihub.apigw.ntruss.com/search/v1/blog");
  url.searchParams.set("query", query);
  url.searchParams.set("display", "5");
  url.searchParams.set("sort", "sim");

  const json = await fetchJson(url, naverHeaders());
  return (json?.items ?? []).map((item) => ({
    title: stripHtml(item.title ?? ""),
    description: stripHtml(item.description ?? ""),
    link: item.link ?? "",
  }));
}

async function naverImageSearch(query) {
  const url = new URL("https://naverapihub.apigw.ntruss.com/search/v1/image");
  url.searchParams.set("query", query);
  url.searchParams.set("display", String(1 + maxExtraImages));
  url.searchParams.set("sort", "sim");
  url.searchParams.set("filter", "medium");

  try {
    const json = await fetchJson(url, naverHeaders());
    if (json?.error) return [];
    return unique((json?.items ?? [])
      .flatMap((item) => [item.link, item.thumbnail])
      .filter((url) => /^https?:\/\//i.test(url))
      .filter((url) => /\.(jpe?g|png|webp)(\?|#|$)/i.test(url) || /search\.pstatic\.net/i.test(url)));
  } catch {
    return [];
  }
}

async function kakaoLocalSearch(query, lat, lon) {
  if (!KAKAO_REST_API_KEY || /^\[.+\]$/.test(KAKAO_REST_API_KEY)) return null;

  const url = new URL("https://dapi.kakao.com/v2/local/search/keyword.json");
  url.searchParams.set("query", query);
  url.searchParams.set("x", String(lon));
  url.searchParams.set("y", String(lat));
  url.searchParams.set("radius", "3000");
  url.searchParams.set("sort", "distance");

  try {
    const json = await fetchJson(url, kakaoHeaders());
    const doc = json?.documents?.[0];
    if (!doc) return null;
    return {
      title: doc.place_name ?? "",
      phone: doc.phone ?? "",
      address: doc.address_name ?? "",
      roadAddress: doc.road_address_name ?? "",
      latitude: Number(doc.y),
      longitude: Number(doc.x),
      placeUrl: doc.place_url ?? "",
    };
  } catch {
    return null;
  }
}

async function kakaoImageSearch(query, storeName) {
  if (!KAKAO_REST_API_KEY || /^\[.+\]$/.test(KAKAO_REST_API_KEY)) return [];

  const url = new URL("https://dapi.kakao.com/v2/search/image");
  url.searchParams.set("query", query);
  url.searchParams.set("size", String(1 + maxExtraImages));
  url.searchParams.set("sort", "accuracy");

  try {
    const json = await fetchJson(url, kakaoHeaders());
    const tokens = meaningfulTokens(storeName);
    return (json?.documents ?? [])
      .filter((doc) => {
        const haystack = [
          doc.display_sitename,
          doc.doc_url,
          doc.image_url,
        ].join(" ").toLowerCase();
        // 카카오 이미지 검색은 일반 뉴스/블로그 이미지가 섞이므로,
        // 가게명 핵심 토큰이 출처/URL에 보이는 경우만 사용한다.
        return tokens.some((token) => haystack.includes(token.toLowerCase()));
      })
      .map((doc) => ({
        imageUrl: doc.image_url ?? "",
        thumbnailUrl: doc.thumbnail_url ?? "",
        displaySitename: doc.display_sitename ?? "",
      }));
  } catch {
    return [];
  }
}

async function crawlHomepage(url) {
  try {
    const res = await fetch(url, {
      headers: {
        "User-Agent": "Mozilla/5.0 MatgyeomungBot/0.1 (+local development; contact site owner if needed)",
        "Accept": "text/html,application/xhtml+xml",
      },
      signal: AbortSignal.timeout(8000),
      redirect: "follow",
    });
    if (!res.ok) return null;
    const html = await res.text();
    const base = new URL(res.url);
    const title = matchFirst(html, /<title[^>]*>([\s\S]*?)<\/title>/i);
    const description = metaContent(html, "description") || metaProperty(html, "og:description");
    const ogImage = metaProperty(html, "og:image") || metaContent(html, "twitter:image");
    const imgUrls = extractImageUrls(html, base);
    const text = stripHtml(html).slice(0, 60_000);
    return {
      title: stripHtml(title),
      description: stripHtml(description),
      images: unique([absoluteUrl(ogImage, base), ...imgUrls].filter(Boolean)),
      text,
    };
  } catch {
    return null;
  }
}

function buildSql(results) {
  const lines = [
    "BEGIN TRANSACTION;",
    "-- Generated by scripts/crawl-store-details.mjs",
  ];

  for (const r of results) {
    const storeKey = sqlString(r.store_key);
    const name = sqlString(r.store_name);
    const address = sqlString(r.store_address);
    const phone = sqlString(r.phone);
    const storeType = sqlString(r.store_type);
    const priceInfo = sqlString(r.price_info);
    const imageUrl = sqlString(r.image_url);
    const lat = sqlNumber(r.latitude);
    const lon = sqlNumber(r.longitude);
    const pickup = sqlNumber(r.pickup);
    const playground = sqlNumber(r.playground);
    const largeDog = sqlNumber(r.large_dog);

    lines.push(`
INSERT INTO stores (store_key, name, address, phone, status, latitude, longitude, store_type, pickup, playground, large_dog, price_info, image_url)
SELECT ${storeKey}, ${name}, ${address}, ${phone}, '영업', ${lat}, ${lon}, ${storeType}, ${pickup}, ${playground}, ${largeDog}, ${priceInfo}, ${imageUrl}
WHERE NOT EXISTS (SELECT 1 FROM stores WHERE store_key = ${storeKey});

UPDATE stores SET
  name = COALESCE(NULLIF(${name}, ''), name),
  address = COALESCE(NULLIF(${address}, ''), address),
  phone = COALESCE(NULLIF(${phone}, ''), phone),
  latitude = COALESCE(${lat}, latitude),
  longitude = COALESCE(${lon}, longitude),
  store_type = COALESCE(NULLIF(${storeType}, ''), store_type),
  pickup = COALESCE(${pickup}, pickup),
  playground = COALESCE(${playground}, playground),
  large_dog = COALESCE(${largeDog}, large_dog),
  price_info = COALESCE(NULLIF(${priceInfo}, ''), price_info),
  image_url = COALESCE(NULLIF(${imageUrl}, ''), image_url)
WHERE store_key = ${storeKey};`);

    const images = unique([r.image_url, ...(r.image_urls ?? [])].filter(Boolean));
    images.forEach((url, index) => {
      lines.push(`
INSERT OR IGNORE INTO store_images (store_id, image_url, sort_order)
SELECT store_id, ${sqlString(url)}, ${index}
FROM stores
WHERE store_key = ${storeKey}
ORDER BY store_id
LIMIT 1;`);
    });
  }

  lines.push("COMMIT;");
  return lines.join("\n");
}

function inferFlags(text) {
  return {
    largeDog: flagFromText(text, [
      /대형견\s*(가능|환영|ok|OK|수용)/i,
      /중대형견/,
      /소형견부터\s*대형견/,
    ], [
      /소형견\s*(전용|만)/,
      /대형견\s*(불가|제한)/,
      /\b(10|12|15)kg\s*(이하|미만)/i,
    ]),
    pickup: flagFromText(text, [
      /픽업/,
      /픽드랍/,
      /등하원/,
      /차량\s*(운행|서비스)/,
      /셔틀/,
    ], [
      /픽업\s*(불가|안\s*함|미운영)/,
    ]),
    playground: flagFromText(text, [
      /운동장/,
      /놀이터/,
      /루프탑/,
      /실내\s*놀이터/,
      /야외\s*놀이터/,
      /마당/,
      /천연잔디/,
      /잔디\s*운동장/,
    ], []),
  };
}

function flagFromText(text, yesPatterns, noPatterns) {
  if (noPatterns.some((re) => re.test(text))) return 0;
  if (yesPatterns.some((re) => re.test(text))) return 1;
  return 0;
}

function extractPriceInfo(text) {
  const sentences = text
    .split(/[\n\r。.!?]+|(?=(?:소형견|중형견|대형견|유치원|호텔|데이케어|1박|하루|종일|시간|가격|요금|금액))/)
    .map((s) => s.replace(/\s+/g, " ").trim())
    .filter(Boolean);
  const priceLines = sentences.filter((s) =>
    /(가격|요금|금액|이용권|정기권|호텔|유치원|데이케어|1박|하루|종일|시간|소형견|중형견|대형견)/.test(s)
    && /(\d{1,3}(,\d{3})+|\d+\s*만|\d+\s*천)\s*원?/.test(s)
  );
  return unique(priceLines)
    .slice(0, 4)
    .join(" / ")
    .slice(0, 800);
}

function extractImageUrls(html, base) {
  const urls = [];
  const imgRe = /<img\b[^>]*(?:src|data-src|data-original)=["']([^"']+)["'][^>]*>/gi;
  let match;
  while ((match = imgRe.exec(html))) {
    const absolute = absoluteUrl(match[1], base);
    if (absolute && /\.(jpe?g|png|webp)(\?|#|$)/i.test(absolute)) urls.push(absolute);
  }
  return urls;
}

function normalizeHomepageUrl(raw) {
  if (!raw) return "";
  const url = stripHtml(String(raw)).trim();
  if (!/^https?:\/\//i.test(url)) return "";
  const host = safeHost(url);
  if (!host) return "";
  if (/(naver\.com|naver\.me|blog\.naver\.com|instagram\.com|facebook\.com)/i.test(host)) return "";
  return url;
}

function naverHeaders() {
  return {
    "X-NCP-APIGW-API-KEY-ID": NAVER_CLIENT_ID,
    "X-NCP-APIGW-API-KEY": NAVER_CLIENT_SECRET,
  };
}

function kakaoHeaders() {
  return {
    "Authorization": `KakaoAK ${KAKAO_REST_API_KEY}`,
  };
}

async function fetchJson(url, headers = {}) {
  const res = await fetch(url, { headers, signal: AbortSignal.timeout(10000) });
  if (!res.ok) throw new Error(`HTTP ${res.status} ${url}`);
  return await res.json();
}

function readXcconfig(file) {
  const out = {};
  const content = readFileSync(file, "utf8");
  for (const line of content.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("//")) continue;
    const m = trimmed.match(/^([A-Z0-9_]+)\s*=\s*(.+)$/);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}

function assertSecret(name, value) {
  if (!value || /^\[.+\]$/.test(value)) {
    throw new Error(`${name} 값이 없습니다. 환경변수 또는 ${relative(xcconfigPath)}를 확인하세요.`);
  }
}

function isDogCareTarget(name) {
  if (/(고양이|냥|묘|캣|cat)/i.test(name) && !/(강아지|애견|반려견|도그|dog|멍)/i.test(name)) {
    return false;
  }
  // 공공데이터 동물위탁관리업 등록 업체 중 상호명이 "OO애견미용실"류인 곳이 섞여 있다 —
  // 미용+호텔/유치원 겸업 매장(예: "OO애견미용&호텔")은 호텔/유치원 키워드가 함께 있으므로
  // 남기고, 미용 키워드만 있고 호텔/유치원 신호가 전혀 없는 순수 미용실만 배제한다.
  if (/(미용|그루밍|목욕|스파)/i.test(name) && !/(호텔|유치원|스쿨|학교|케어|데이케어)/i.test(name)) {
    return false;
  }
  return /(애견|강아지|반려견|펫|댕댕|멍|도그|dog|호텔|유치원|데이케어|케어|스쿨)/i.test(name);
}

function boardingType(name) {
  if (/호텔/.test(name)) return "호텔";
  if (/(유치원|스쿨|학교|케어|데이케어)/.test(name)) return "유치원";
  return "호텔";
}

function tmToWgs84(x, y) {
  const a = 6378137.0;
  const f = 1.0 / 298.257222101;
  const lat0 = 38.0 * Math.PI / 180.0;
  const lon0 = 127.0 * Math.PI / 180.0;
  const k0 = 1.0;
  const FE = 200000.0;
  const FN = 500000.0;
  const e2 = f * (2 - f);
  const ep2 = e2 / (1 - e2);
  const meridionalArc = (lat) => a * (
    (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256) * lat
    - (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * e2 * e2 * e2 / 1024) * Math.sin(2 * lat)
    + (15 * e2 * e2 / 256 + 45 * e2 * e2 * e2 / 1024) * Math.sin(4 * lat)
    - (35 * e2 * e2 * e2 / 3072) * Math.sin(6 * lat)
  );
  const M0 = meridionalArc(lat0);
  const M = M0 + (y - FN) / k0;
  const mu = M / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256));
  const e1 = (1 - Math.sqrt(1 - e2)) / (1 + Math.sqrt(1 - e2));
  const phi1 = mu
    + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * Math.sin(2 * mu)
    + (21 * e1 * e1 / 16 - 55 * e1 ** 4 / 32) * Math.sin(4 * mu)
    + (151 * e1 ** 3 / 96) * Math.sin(6 * mu)
    + (1097 * e1 ** 4 / 512) * Math.sin(8 * mu);
  const sinPhi1 = Math.sin(phi1), cosPhi1 = Math.cos(phi1), tanPhi1 = Math.tan(phi1);
  const C1 = ep2 * cosPhi1 * cosPhi1;
  const T1 = tanPhi1 * tanPhi1;
  const N1 = a / Math.sqrt(1 - e2 * sinPhi1 * sinPhi1);
  const R1 = a * (1 - e2) / (1 - e2 * sinPhi1 * sinPhi1) ** 1.5;
  const D = (x - FE) / (N1 * k0);
  const lat = phi1 - (N1 * tanPhi1 / R1) *
    (D * D / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * ep2) * D ** 4 / 24
      + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * ep2 - 3 * C1 * C1) * D ** 6 / 720);
  const lon = lon0 + (D - (1 + 2 * T1 + C1) * D ** 3 / 6
    + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * ep2 + 24 * T1 * T1) * D ** 5 / 120) / cosPhi1;
  return { lat: lat * 180 / Math.PI, lon: lon * 180 / Math.PI };
}

function approxDistanceMeters(lat1, lon1, lat2, lon2) {
  const dLat = (lat2 - lat1) * 111_000;
  const dLon = (lon2 - lon1) * 88_800;
  return Math.sqrt(dLat * dLat + dLon * dLon);
}

function stripHtml(s = "") {
  return String(s)
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function metaProperty(html, property) {
  const re = new RegExp(`<meta[^>]+property=["']${escapeRegex(property)}["'][^>]+content=["']([^"']+)["'][^>]*>`, "i");
  return matchFirst(html, re);
}

function metaContent(html, name) {
  const re = new RegExp(`<meta[^>]+name=["']${escapeRegex(name)}["'][^>]+content=["']([^"']+)["'][^>]*>`, "i");
  return matchFirst(html, re);
}

function matchFirst(text, re) {
  return text.match(re)?.[1] ?? "";
}

function absoluteUrl(raw, base) {
  if (!raw) return "";
  try {
    return new URL(raw, base).toString();
  } catch {
    return "";
  }
}

function safeHost(raw) {
  try {
    return new URL(raw).hostname;
  } catch {
    return "";
  }
}

function meaningfulTokens(name) {
  const compact = name.replace(/\s+/g, "");
  const tokens = [compact, ...name.split(/\s+/)]
    .map((s) => s.replace(/[^0-9A-Za-z가-힣_-]/g, ""))
    .filter((s) => s.length >= 3)
    .filter((s) => !["애견호텔", "애견유치원", "호텔", "유치원", "강아지", "반려견"].includes(s));
  return unique(tokens);
}

function sqlNumber(value) {
  return Number.isFinite(Number(value)) ? String(Number(value)) : "NULL";
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function relative(file) {
  return path.relative(repoRoot, file);
}
