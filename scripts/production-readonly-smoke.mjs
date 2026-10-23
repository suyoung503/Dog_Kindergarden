#!/usr/bin/env node

const baseURL = (process.env.PRODUCTION_API_BASE_URL ??
  "https://matgyeomung-api.dog-kindergarden.workers.dev").replace(/\/$/, "");

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function check(name, path, validate) {
  try {
    const response = await fetch(`${baseURL}${path}`, {
      headers: { "User-Agent": "matgyeomung-production-readonly-smoke/1.0" },
      signal: AbortSignal.timeout(15_000),
    });
    const body = await response.text();
    await validate(response, body);
    passed += 1;
    console.log(`[PASS] ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`[FAIL] ${name}: ${error.message}`);
  }
}

function requireProtectedStatus(expected) {
  return (response) => {
    assert(response.status === expected, `HTTP ${response.status}, 예상 ${expected}`);
    assert(
      response.headers.get("cache-control") === "private, no-store",
      "보호 API에 private, no-store가 없습니다.",
    );
    assert(
      response.headers.get("x-content-type-options") === "nosniff",
      "보호 API에 nosniff가 없습니다.",
    );
  };
}

async function validatePublicPage(response, body, keyword) {
  assert(response.status === 200, `HTTP ${response.status}, 예상 200`);
  assert(response.headers.get("content-type")?.includes("text/html"), "HTML Content-Type이 아닙니다.");
  assert(body.includes(keyword), `필수 문구가 없습니다: ${keyword}`);
  assert(response.headers.get("x-content-type-options") === "nosniff", "nosniff 헤더가 없습니다.");
  assert(response.headers.get("referrer-policy") === "no-referrer", "Referrer-Policy가 다릅니다.");
  assert(response.headers.get("content-security-policy")?.includes("default-src 'none'"), "CSP가 없습니다.");
}

console.log(`맡겨멍 운영 서버 읽기 전용 smoke: ${baseURL}`);

await check("서비스 상태", "/", async (response, body) => {
  assert(response.status === 200, `HTTP ${response.status}, 예상 200`);
  const json = JSON.parse(body);
  assert(json.ok === true && json.service === "맡겨멍 API", "서비스 식별 응답이 다릅니다.");
});

await check("개인정보처리방침", "/privacy", (response, body) =>
  validatePublicPage(response, body, "보유기간과 파기"));
await check("고객지원", "/support", (response, body) =>
  validatePublicPage(response, body, "yikum503@naver.com"));

await check("공개 가게 목록", "/api/stores", async (response, body) => {
  assert(response.status === 200, `HTTP ${response.status}, 예상 200`);
  const stores = JSON.parse(body);
  assert(Array.isArray(stores), "가게 목록이 배열이 아닙니다.");
  assert(stores.length > 0, "운영 가게 목록이 비어 있습니다.");
  assert(stores.every((store) => Number.isInteger(store.store_id) && store.name), "필수 가게 필드가 없습니다.");
});

await check("공개 공지 목록", "/api/notices", async (response, body) => {
  assert(response.status === 200, `HTTP ${response.status}, 예상 200`);
  assert(Array.isArray(JSON.parse(body)), "공지 목록이 배열이 아닙니다.");
});

const protectedRoutes = [
  ["타인 예약 무인증 차단", "/api/users/1/reservations"],
  ["사장님 가게 무인증 차단", "/api/owners/1/stores"],
  ["운영자 승인함 무인증 차단", "/api/owner-applications"],
  ["고객센터 무인증 차단", "/api/support/conversation"],
];

for (const [name, path] of protectedRoutes) {
  await check(name, path, requireProtectedStatus(401));
}

console.log(`\n결과: ${failed === 0 ? "PASS" : "FAIL"} (${passed}개 통과, ${failed}개 실패)`);
if (failed > 0) process.exit(1);
