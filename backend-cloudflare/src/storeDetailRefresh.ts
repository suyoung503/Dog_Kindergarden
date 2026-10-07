const NAVER_PLACE_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

const DEFAULT_LONGITUDE = "126.9779692";
const DEFAULT_LATITUDE = "37.5662952";
const MAX_IMAGES = 5;

const SEARCH_QUERY_OVERRIDES: Record<string, string> = {
  "제주네 애견유치원": "제주네 애견",
  "놀러오개 애견유치원 애견호텔 애견미용 서초점": "놀러오개 서초점",
  "디어캐닌 DEAR CANINE": "디어캐닌",
  "도기프렌즈 웰니스센터": "도기프렌즈 강아지유치원",
};

type JsonRecord = Record<string, unknown>;

type RefreshTarget = {
  store_id: number;
  name: string;
  latitude: number | null;
  longitude: number | null;
};

type PlaceMatch = {
  id: string;
  name: string;
  imageUrl: string;
};

export type StoreDetailRefreshResult = {
  checked: number;
  matched: number;
  updatedHours: number;
  updatedImages: number;
};

export async function refreshStaleStoreDetails(
  db: D1Database,
  limit = 8,
): Promise<StoreDetailRefreshResult> {
  const { results } = await db
    .prepare(
      `
      SELECT store_id, name, latitude, longitude
      FROM stores
      WHERE is_curated = 1
      ORDER BY COALESCE(details_checked_at, '1970-01-01T00:00:00.000Z') ASC, store_id ASC
      LIMIT ?
    `,
    )
    .bind(limit)
    .all<RefreshTarget>();

  const summary: StoreDetailRefreshResult = {
    checked: 0,
    matched: 0,
    updatedHours: 0,
    updatedImages: 0,
  };

  for (const store of results) {
    const checkedAt = new Date().toISOString();
    const detail = await fetchStoreDetail(store);
    summary.checked += 1;

    if (!detail) {
      await markChecked(db, store.store_id, checkedAt);
      await sleep(250);
      continue;
    }

    summary.matched += 1;
    if (detail.openTime) summary.updatedHours += 1;
    if (detail.imageUrls.length) summary.updatedImages += 1;

    const statements = [
      db
        .prepare(
          `
          UPDATE stores
          SET open_time = CASE WHEN ? <> '' THEN ? ELSE open_time END,
              image_url = CASE WHEN ? <> '' THEN ? ELSE image_url END,
              details_checked_at = ?
          WHERE store_id = ?
        `,
        )
        .bind(
          detail.openTime,
          detail.openTime,
          detail.imageUrls[0] ?? "",
          detail.imageUrls[0] ?? "",
          checkedAt,
          store.store_id,
        ),
    ];

    if (detail.imageUrls.length) {
      statements.push(
        db.prepare(`DELETE FROM store_images WHERE store_id = ?`).bind(store.store_id),
      );
      for (const [index, imageUrl] of detail.imageUrls.entries()) {
        statements.push(
          db
            .prepare(
              `INSERT INTO store_images (store_id, image_url, sort_order) VALUES (?, ?, ?)`,
            )
            .bind(store.store_id, imageUrl, index),
        );
      }
    }

    await db.batch(statements);
    await sleep(250);
  }

  return summary;
}

async function fetchStoreDetail(store: RefreshTarget): Promise<{
  openTime: string;
  imageUrls: string[];
} | null> {
  const query = SEARCH_QUERY_OVERRIDES[store.name] ?? store.name.trim();
  if (!query) return null;

  const longitude = store.longitude ? String(store.longitude) : DEFAULT_LONGITUDE;
  const latitude = store.latitude ? String(store.latitude) : DEFAULT_LATITUDE;
  const listUrl =
    `https://pcmap.place.naver.com/place/list?query=${encodeURIComponent(query)}` +
    `&x=${longitude}&y=${latitude}&clientX=${longitude}&clientY=${latitude}` +
    "&display=5&locale=ko&svcName=map_pcv5";

  const listState = parseApolloState(await fetchText(listUrl));
  if (!listState) return null;

  const place = pickMatchingPlace(listState, query);
  if (!place) return null;

  const detailUrl = `https://pcmap.place.naver.com/place/${place.id}/review/visitor`;
  const detailState = parseApolloState(await fetchText(detailUrl));
  if (!detailState) return null;

  const base = asRecord(detailState[`PlaceDetailBase:${place.id}`]) ?? {};
  const openTime =
    extractStructuredOpeningHours(detailState) || formatOpeningHours(base.openingHours);
  const imageUrls = extractBusinessImages(detailState, place.id, place.imageUrl);

  return { openTime, imageUrls };
}

async function markChecked(db: D1Database, storeId: number, checkedAt: string) {
  await db
    .prepare(`UPDATE stores SET details_checked_at = ? WHERE store_id = ?`)
    .bind(checkedAt, storeId)
    .run();
}

async function fetchText(url: string): Promise<string> {
  try {
    const response = await fetch(url, {
      headers: {
        "User-Agent": NAVER_PLACE_USER_AGENT,
        Referer: "https://map.naver.com/",
        "Accept-Language": "ko-KR,ko;q=0.9",
      },
    });
    return response.ok ? await response.text() : "";
  } catch {
    return "";
  }
}

function parseApolloState(html: string): JsonRecord | null {
  const match = html.match(/window\.__APOLLO_STATE__\s*=\s*(\{[\s\S]*?\});/);
  if (!match) return null;
  try {
    return asRecord(JSON.parse(match[1]));
  } catch {
    return null;
  }
}

function pickMatchingPlace(state: JsonRecord, storeName: string): PlaceMatch | null {
  const rootQuery = asRecord(state.ROOT_QUERY);
  if (!rootQuery) return null;
  const listKey = Object.keys(rootQuery).find((key) => key.startsWith("placeList("));
  if (!listKey) return null;

  const placeList = asRecord(rootQuery[listKey]);
  const businesses = asRecord(placeList?.businesses);
  const items = asArray(businesses?.items);

  for (const rawItem of items) {
    const item = asRecord(rawItem);
    const reference = stringValue(item?.__ref);
    const id = reference.replace("PlaceListBusinessesItem:", "");
    if (!id) continue;

    const candidate = asRecord(state[`PlaceListBusinessesItem:${id}`]);
    const candidateName = stringValue(candidate?.name);
    if (namesLikelyMatch(storeName, candidateName)) {
      return {
        id,
        name: candidateName,
        imageUrl: stringValue(candidate?.imageUrl),
      };
    }
  }
  return null;
}

function extractStructuredOpeningHours(state: JsonRecord): string {
  const rootQuery = asRecord(state.ROOT_QUERY);
  if (!rootQuery) return "";
  const detailKey = Object.keys(rootQuery).find((key) => key.startsWith("placeDetail("));
  if (!detailKey) return "";
  const placeDetail = asRecord(rootQuery[detailKey]);
  const schedules = asArray(placeDetail?.newBusinessHours);
  if (!schedules.length) return "";

  const sections: string[] = [];
  for (const rawSchedule of schedules) {
    const schedule = asRecord(rawSchedule);
    if (!schedule) continue;
    const grouped = new Map<string, string[]>();

    for (const rawItem of asArray(schedule.businessHours)) {
      const item = asRecord(rawItem);
      if (!item) continue;
      const label = formatWorkingHours(item);
      if (!label) continue;
      const days = grouped.get(label) ?? [];
      const day = stringValue(item.day);
      if (day) days.push(day);
      grouped.set(label, days);
    }

    const rows = [...grouped.entries()].map(
      ([label, days]) => `${days.length ? `${days.join("·")} ` : ""}${label}`,
    );
    const freeText = cleanText(stringValue(schedule.freeText));
    if (freeText) rows.push(freeText);

    if (rows.length) {
      const scheduleName = cleanText(stringValue(schedule.name));
      const prefix = schedules.length > 1 && scheduleName ? `${scheduleName}: ` : "";
      sections.push(prefix + rows.join(" / "));
    }
  }

  return unique(sections).join("\n").slice(0, 1000);
}

function formatWorkingHours(item: JsonRecord): string {
  const parts: string[] = [];
  const hours = asRecord(item.businessHours);
  const start = stringValue(hours?.start);
  const end = stringValue(hours?.end);
  if (start && end) parts.push(`${start}~${end}`);
  else {
    const description = cleanText(stringValue(item.description));
    if (description) parts.push(description);
  }

  const breakHours = asRecord(item.breakHours);
  const breakStart = stringValue(breakHours?.start);
  const breakEnd = stringValue(breakHours?.end);
  if (breakStart && breakEnd) parts.push(`휴게 ${breakStart}~${breakEnd}`);

  for (const rawBreak of asArray(item.breakHours)) {
    const rest = asRecord(rawBreak);
    const restStart = stringValue(rest?.start);
    const restEnd = stringValue(rest?.end);
    if (restStart && restEnd) parts.push(`휴게 ${restStart}~${restEnd}`);
  }

  const lastOrder = asRecord(item.lastOrderTimes);
  const lastOrderStart = stringValue(lastOrder?.start);
  if (lastOrderStart) parts.push(`라스트오더 ${lastOrderStart}`);

  for (const rawLast of asArray(item.lastOrderTimes)) {
    const last = asRecord(rawLast);
    const value = stringValue(last?.time) || stringValue(last?.start) || stringValue(rawLast);
    if (value) parts.push(`라스트오더 ${value}`);
  }

  return unique(parts).join(", ");
}

function formatOpeningHours(value: unknown): string {
  if (typeof value === "string") return cleanText(value);
  if (Array.isArray(value)) {
    return value.map(formatOpeningHourItem).filter(Boolean).join(" / ").slice(0, 500);
  }

  const record = asRecord(value);
  if (!record) return "";
  const values: string[] = [];
  for (const [key, item] of Object.entries(record)) {
    if (item === null || item === undefined || typeof item === "object") continue;
    if (/time|hour|day|description|name|text/i.test(key)) values.push(String(item));
  }
  return unique(values.map(cleanText)).join(" / ").slice(0, 500);
}

function formatOpeningHourItem(value: unknown): string {
  if (typeof value === "string") return cleanText(value);
  const item = asRecord(value);
  if (!item) return "";
  const day = stringValue(item.day) || stringValue(item.dayOfWeek) || stringValue(item.name);
  const start =
    stringValue(item.start) ||
    stringValue(item.startTime) ||
    stringValue(item.open) ||
    stringValue(item.openTime);
  const end =
    stringValue(item.end) ||
    stringValue(item.endTime) ||
    stringValue(item.close) ||
    stringValue(item.closeTime);
  const text = cleanText(stringValue(item.text) || stringValue(item.description));
  return cleanText(text || [day, start && end ? `${start}~${end}` : start || end].filter(Boolean).join(" "));
}

function extractBusinessImages(
  state: JsonRecord,
  placeId: string,
  representativeImage: string,
): string[] {
  const businessPhotos = Object.entries(state)
    .filter(([key, raw]) => {
      const value = asRecord(raw);
      return (
        key.startsWith(`PlaceDetailTopPhotoItem:${placeId}_business_`) &&
        stringValue(value?.mediaFormat) === "image" &&
        stringValue(value?.mediaSource) === "business"
      );
    })
    .sort(([left], [right]) => numericSuffix(left) - numericSuffix(right))
    .map(([, raw]) => {
      const value = asRecord(raw);
      return stringValue(value?.originalUrl) || stringValue(value?.thumbnailUrl);
    });

  return unique([representativeImage, ...businessPhotos]).slice(0, MAX_IMAGES);
}

function namesLikelyMatch(storeName: string, placeName: string): boolean {
  if (namesLikelyMatchExact(storeName, placeName)) return true;
  const alias = storeName.match(/\(([^)]+)\)/)?.[1]?.trim() ?? "";
  return alias ? namesLikelyMatchExact(alias, placeName) : false;
}

function namesLikelyMatchExact(storeName: string, placeName: string): boolean {
  const flatStore = flattenName(storeName);
  const flatPlace = flattenName(placeName);
  if (!flatStore || !flatPlace) return false;
  if (
    flatStore === flatPlace ||
    flatStore.includes(flatPlace) ||
    flatPlace.includes(flatStore)
  ) {
    return true;
  }

  const storeTokens = nameTokens(storeName);
  const placeTokens = nameTokens(placeName);
  return isSubset(storeTokens, placeTokens) || isSubset(placeTokens, storeTokens);
}

function flattenName(value: string): string {
  return value.toLowerCase().replace(/[\s&/,·()\-_.'"“”|]/g, "");
}

function nameTokens(value: string): Set<string> {
  return new Set(
    value
      .toLowerCase()
      .split(/[\s&/,·]+/)
      .map((token) => token.replace(/[()\-_.'"“”|]/g, "").trim())
      .filter(Boolean),
  );
}

function isSubset(left: Set<string>, right: Set<string>): boolean {
  for (const value of left) if (!right.has(value)) return false;
  return left.size > 0;
}

function numericSuffix(value: string): number {
  return Number(value.match(/_(\d+)$/)?.[1] ?? 999);
}

function asRecord(value: unknown): JsonRecord | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as JsonRecord)
    : null;
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function stringValue(value: unknown): string {
  return typeof value === "string" || typeof value === "number" ? String(value) : "";
}

function cleanText(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function unique(values: string[]): string[] {
  return [...new Set(values.filter(Boolean))];
}

function sleep(milliseconds: number) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
