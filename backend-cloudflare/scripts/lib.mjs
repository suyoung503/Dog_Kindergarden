/**
 * scripts/ 하위 크롤링 스크립트들이 공유하는 유틸리티.
 * 네이버 플레이스 Apollo State 파싱, 이름 매칭, SQL 이스케이프 등 여러 스크립트에서
 * 동일하게 쓰이던 로직을 한 곳으로 모았다.
 */

export const NAVER_PLACE_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function parseArgs(argv) {
  const out = {};
  for (const arg of argv) {
    if (arg.startsWith("--")) {
      const [key, value] = arg.slice(2).split("=");
      out[key] = value ?? true;
    }
  }
  return out;
}

export async function fetchText(url) {
  try {
    const res = await fetch(url, {
      headers: {
        "User-Agent": NAVER_PLACE_UA,
        "Referer": "https://map.naver.com/",
        "Accept-Language": "ko-KR,ko;q=0.9",
      },
    });
    if (!res.ok) return "";
    return await res.text();
  } catch {
    return "";
  }
}

export function parseApolloState(html) {
  const m = html.match(/window\.__APOLLO_STATE__\s*=\s*(\{[\s\S]*?\});/);
  if (!m) return null;
  try {
    return JSON.parse(m[1]);
  } catch {
    return null;
  }
}

export function flattenName(s) {
  return String(s ?? "")
    .toLowerCase()
    .replace(/[\s&/,·()\-_.'"“”|]/g, "");
}

export function nameTokens(s) {
  return new Set(
    String(s ?? "")
      .toLowerCase()
      .split(/[\s&/,·]+/)
      .map((t) => t.replace(/[()\-_.'"“”|]/g, "").trim())
      .filter(Boolean),
  );
}

export function isSubset(a, b) {
  for (const v of a) if (!b.has(v)) return false;
  return a.size > 0;
}

// 검색 1위를 무조건 채택하면 안 된다 — 실측 결과 "대학로 애견카페" 검색 1위가 전혀 다른
// 업종의 "미어캣파크 이색 체험 동물 카페"였고(2위가 정답), "견생유치원"(서울) 검색은
// 결과 전부가 30km 넘게 떨어진 인천 업체였으며, "THE 발라당호텔"은 좌표가 1m 차이인
// "THE발라당고양이호텔"(고양이 전용 지점)이 1위였다 — 같은 건물이라 거리 필터로도 못 거른다.
// 그래서 이름이 실질적으로 같다고 볼 수 있는 후보만 채택하고, 없으면 매칭 실패로 둔다.
export function namesLikelyMatch(storeName, placeName) {
  if (namesLikelyMatchExact(storeName, placeName)) return true;
  // "waldog(왈독)"처럼 영문명(한글별칭) 형태면 괄호 안 별칭만 따로도 대조해본다 —
  // 네이버 등록명("왈독 강아지 유치원...")엔 영문명이 안 붙어있어 원문 그대로는 안 걸림.
  const alias = parenAlias(storeName);
  return alias ? namesLikelyMatchExact(alias, placeName) : false;
}

function namesLikelyMatchExact(storeName, placeName) {
  const flatA = flattenName(storeName);
  const flatB = flattenName(placeName);
  if (!flatA || !flatB) return false;
  if (flatA === flatB || flatA.includes(flatB) || flatB.includes(flatA)) return true;

  const tokensA = nameTokens(storeName);
  const tokensB = nameTokens(placeName);
  return isSubset(tokensA, tokensB) || isSubset(tokensB, tokensA);
}

function parenAlias(name) {
  const m = String(name ?? "").match(/\(([^)]+)\)/);
  return m ? m[1].trim() : "";
}

export function sqlString(value) {
  if (value === null || value === undefined) return "NULL";
  return `'${String(value).replace(/'/g, "''")}'`;
}

export function unique(values) {
  return [...new Set(values.filter(Boolean))];
}
