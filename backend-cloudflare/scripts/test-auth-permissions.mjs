#!/usr/bin/env node

/**
 * 로컬 Worker 인증·권한 회귀 테스트.
 *
 * 실행 전:
 *   npx wrangler dev --local --var ALLOW_DEV_AUTH:true --var INTERNAL_API_KEY:test-key
 *   INTERNAL_API_KEY=test-key npm run test:auth
 */

const base = (process.env.API_BASE_URL ?? "http://127.0.0.1:8787").replace(/\/$/, "");
const internalKey = process.env.INTERNAL_API_KEY ?? "";
if (!internalKey) throw new Error("INTERNAL_API_KEY 환경변수가 필요합니다.");

const results = [];

async function request(method, path, { body, token, internal } = {}) {
  const headers = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (token) headers.Authorization = `Bearer ${token}`;
  if (internal) headers["X-Internal-Key"] = internal;
  const response = await fetch(`${base}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { status: response.status, data };
}

function expect(name, actual, expected) {
  const ok = actual === expected;
  results.push({ name, ok, actual, expected });
  if (!ok) throw new Error(`${name}: expected ${expected}, got ${actual}`);
}

function expectOneOf(name, actual, expected) {
  const ok = expected.includes(actual);
  results.push({ name, ok, actual, expected });
  if (!ok) throw new Error(`${name}: expected ${expected.join("/")}, got ${actual}`);
}

const guardianLogin = await request("POST", "/api/auth/dev", {
  body: { identity: "auth-test-guardian", nickname: "권한테스트 보호자", is_owner: false },
});
expectOneOf("보호자 로컬 로그인", guardianLogin.status, [200, 201]);
const guardianId = guardianLogin.data.user_id;
const guardianToken = guardianLogin.data.session_token;

const ownerLogin = await request("POST", "/api/auth/dev", {
  body: { identity: "auth-test-owner", nickname: "권한테스트 사장님", is_owner: true },
});
expectOneOf("사장님 로컬 로그인", ownerLogin.status, [200, 201]);
const ownerId = ownerLogin.data.user_id;
const ownerToken = ownerLogin.data.session_token;

const otherOwnerLogin = await request("POST", "/api/auth/dev", {
  body: { identity: "auth-test-other-owner", nickname: "다른 사장님", is_owner: true },
});
expectOneOf("다른 사장님 로컬 로그인", otherOwnerLogin.status, [200, 201]);
const otherOwnerId = otherOwnerLogin.data.user_id;
const otherOwnerToken = otherOwnerLogin.data.session_token;

const adminLogin = await request("POST", "/api/auth/dev", {
  body: {
    identity: "auth-test-admin",
    nickname: "권한테스트 운영자",
    is_owner: false,
    is_admin: true,
  },
});
expectOneOf("운영자 로컬 로그인", adminLogin.status, [200, 201]);
const adminToken = adminLogin.data.session_token;

expect(
  "가입 역할 위조 차단",
  (await request("POST", "/api/auth/dev", {
    body: { identity: "auth-test-guardian", nickname: "위조 사장님", is_owner: true },
  })).status,
  409,
);

expect(
  "무인증 개인정보 조회 차단",
  (await request("GET", `/api/users/${guardianId}/reservations`)).status,
  401,
);
expect(
  "타인 예약 조회 차단",
  (await request("GET", `/api/users/${ownerId}/reservations`, { token: guardianToken })).status,
  403,
);
expect(
  "위조 세션 토큰 차단",
  (await request("GET", `/api/users/${guardianId}/reservations`, { token: "forged-session-token" })).status,
  401,
);
expect(
  "위조 카카오 토큰 차단",
  (await request("POST", "/api/auth/kakao", {
    body: { access_token: "forged-token", is_owner: false },
  })).status,
  401,
);

const runId = Date.now();
const store = {
  store_key: `auth-regression-store-${runId}`,
  store_name: "권한 회귀 테스트 가게",
  store_address: "서울 테스트구",
  store_type: "유치원",
};
expect(
  "내부 키 없는 관리자 API 차단",
  (await request("POST", "/api/admin/stores/import", { body: store })).status,
  401,
);
expect(
  "잘못된 내부 키 차단",
  (await request("POST", "/api/admin/stores/import", {
    body: store,
    internal: "wrong-internal-key",
  })).status,
  401,
);
expect(
  "내부 키 관리자 API 허용",
  (await request("POST", "/api/admin/stores/import", {
    body: store,
    internal: internalKey,
  })).status,
  201,
);
expect(
  "보호자 가게 소유권 등록 차단",
  (await request("POST", "/api/stores/claim", {
    body: { user_id: guardianId, ...store },
    token: guardianToken,
  })).status,
  403,
);
const ownerApplication = await request("POST", "/api/stores/claim", {
    body: { user_id: ownerId, ...store },
    token: ownerToken,
});
expect("사장님 가게 등록 요청 생성", ownerApplication.status, 201);
expect("등록 요청은 승인 대기", ownerApplication.data.status, "PENDING");
const applicationId = ownerApplication.data.application_id;

expect(
  "일반 사용자의 운영자 요청함 접근 차단",
  (await request("GET", "/api/owner-applications", { token: guardianToken })).status,
  403,
);
const adminApplications = await request("GET", "/api/owner-applications", {
  token: adminToken,
});
expect("운영자 요청함 접근", adminApplications.status, 200);
expect(
  "운영자 요청함에 신청 노출",
  adminApplications.data.some((item) => item.application_id === applicationId),
  true,
);
const pendingCount = await request("GET", "/api/owner-applications/pending-count", {
  token: adminToken,
});
expect("운영자 승인 대기 수 조회", pendingCount.status, 200);
expect("승인 대기 수 반영", pendingCount.data.count > 0, true);
const ownerStoresBeforeApproval = await request("GET", `/api/owners/${ownerId}/stores`, {
  token: ownerToken,
});
expect(
  "승인 전 owner_id 미연결",
  ownerStoresBeforeApproval.data.some((item) => item.store_key === store.store_key),
  false,
);
expect(
  "운영자 가게 등록 승인",
  (await request("PATCH", `/api/owner-applications/${applicationId}/approve`, {
    token: adminToken,
  })).status,
  200,
);
const ownerStoresAfterApproval = await request("GET", `/api/owners/${ownerId}/stores`, {
  token: ownerToken,
});
expect(
  "승인 후 owner_id 연결",
  ownerStoresAfterApproval.data.some((item) => item.store_key === store.store_key),
  true,
);
expect(
  "다른 사장님의 승인 완료 가게 등록 차단",
  (await request("POST", "/api/stores/claim", {
    body: { user_id: otherOwnerId, ...store },
    token: otherOwnerToken,
  })).status,
  409,
);

const rejectedStore = {
  store_key: `auth-regression-rejected-${runId}`,
  store_name: "거절 회귀 테스트 가게",
  store_address: "서울 테스트구",
  store_type: "호텔",
};
expect(
  "거절용 가게 내부 등록",
  (await request("POST", "/api/admin/stores/import", {
    body: rejectedStore,
    internal: internalKey,
  })).status,
  201,
);
const rejectedApplication = await request("POST", "/api/stores/claim", {
  body: { user_id: otherOwnerId, ...rejectedStore },
  token: otherOwnerToken,
});
expect("거절용 등록 요청 생성", rejectedApplication.status, 201);
expect(
  "운영자 가게 등록 거절",
  (await request("PATCH", `/api/owner-applications/${rejectedApplication.data.application_id}/reject`, {
    token: adminToken,
  })).status,
  200,
);
const otherOwnerStores = await request("GET", `/api/owners/${otherOwnerId}/stores`, {
  token: otherOwnerToken,
});
expect(
  "거절 후 owner_id 미연결",
  otherOwnerStores.data.some((item) => item.store_key === rejectedStore.store_key),
  false,
);

const guardianPet = await request("POST", `/api/users/${guardianId}/pets`, {
  body: { name: "보호자 강아지" },
  token: guardianToken,
});
expect("본인 강아지 등록", guardianPet.status, 201);
const ownerPet = await request("POST", `/api/users/${ownerId}/pets`, {
  body: { name: "사장님 강아지" },
  token: ownerToken,
});
expect("사장님 강아지 등록", ownerPet.status, 201);
expect(
  "타인 강아지 목록 조회 차단",
  (await request("GET", `/api/users/${guardianId}/pets`, { token: ownerToken })).status,
  403,
);
expect(
  "타인 강아지 삭제 차단",
  (await request("DELETE", `/api/pets/${guardianPet.data.pet_id}`, { token: ownerToken })).status,
  404,
);

const reservation = {
  user_id: guardianId,
  pet_id: ownerPet.data.pet_id,
  ...store,
  start_date: "2026-10-10 (토)",
  end_date: "2026-10-10 (토)",
  reservation_type: "종일권",
  request_message: "",
};
expect(
  "타인 강아지 예약 차단",
  (await request("POST", "/api/reservations", {
    body: reservation,
    token: guardianToken,
  })).status,
  403,
);

reservation.pet_id = guardianPet.data.pet_id;
const createdReservation = await request("POST", "/api/reservations", {
  body: reservation,
  token: guardianToken,
});
expect("본인 예약 생성", createdReservation.status, 201);
const reservationId = createdReservation.data.reservation_id;
const roomId = createdReservation.data.room_id;

expect(
  "타인 예약 취소 차단",
  (await request("PATCH", `/api/reservations/${reservationId}/cancel`, {
    token: otherOwnerToken,
    body: { by_owner: true },
  })).status,
  403,
);
expect(
  "다른 사장님 예약 조회 차단",
  (await request("GET", `/api/owners/${ownerId}/reservations/pending`, {
    token: otherOwnerToken,
  })).status,
  403,
);

expect(
  "보호자 예약 확정 차단",
  (await request("PATCH", `/api/reservations/${reservationId}/confirm`, {
    token: guardianToken,
  })).status,
  403,
);
expect(
  "다른 사장님 예약 확정 차단",
  (await request("PATCH", `/api/reservations/${reservationId}/confirm`, {
    token: otherOwnerToken,
  })).status,
  403,
);
expect(
  "가게 사장님 예약 확정",
  (await request("PATCH", `/api/reservations/${reservationId}/confirm`, {
    token: ownerToken,
  })).status,
  200,
);
const beforeRepeat = await request("GET", `/api/chatrooms/${roomId}/messages`, {
  token: guardianToken,
});
expect(
  "확정 재호출 성공",
  (await request("PATCH", `/api/reservations/${reservationId}/confirm`, {
    token: ownerToken,
  })).status,
  200,
);
const afterRepeat = await request("GET", `/api/chatrooms/${roomId}/messages`, {
  token: guardianToken,
});
expect("확정 메시지 중복 방지", afterRepeat.data.length, beforeRepeat.data.length);

expect(
  "보호자 알림장 작성 차단",
  (await request("POST", `/api/reservations/${reservationId}/diaries`, {
    body: { content: "위조 알림장" },
    token: guardianToken,
  })).status,
  403,
);
expect(
  "가게 사장님 알림장 작성",
  (await request("POST", `/api/reservations/${reservationId}/diaries`, {
    body: { content: "정상 알림장" },
    token: ownerToken,
  })).status,
  200,
);
expect(
  "다른 사장님 알림장 조회 차단",
  (await request("GET", `/api/reservations/${reservationId}/diaries`, {
    token: otherOwnerToken,
  })).status,
  403,
);
expect(
  "다른 사장님 채팅방 접근 차단",
  (await request("GET", `/api/chatrooms/${roomId}/messages`, {
    token: otherOwnerToken,
  })).status,
  403,
);
expect(
  "채팅 발신자 위조 차단",
  (await request("POST", `/api/chatrooms/${roomId}/messages`, {
    body: { sender_id: ownerId, content: "위조 발신" },
    token: guardianToken,
  })).status,
  403,
);
expect(
  "없는 예약 취소 404",
  (await request("PATCH", "/api/reservations/999999999/cancel", {
    token: guardianToken,
  })).status,
  404,
);
expect(
  "보호자 본인 예약 취소",
  (await request("PATCH", `/api/reservations/${reservationId}/cancel`, {
    token: guardianToken,
  })).status,
  200,
);
expect(
  "취소 예약 재확정 차단",
  (await request("PATCH", `/api/reservations/${reservationId}/confirm`, {
    token: ownerToken,
  })).status,
  409,
);

expect(
  "다른 사장님 자신의 조회는 허용",
  (await request("GET", `/api/owners/${otherOwnerId}/reservations/pending`, {
    token: otherOwnerToken,
  })).status,
  200,
);

expect(
  "로그아웃 서버 세션 폐기",
  (await request("POST", "/api/auth/logout", { token: guardianToken })).status,
  200,
);
expect(
  "폐기 토큰 재사용 차단",
  (await request("GET", `/api/users/${guardianId}/pets`, { token: guardianToken })).status,
  401,
);

console.log(JSON.stringify({
  passed: results.filter((result) => result.ok).length,
  total: results.length,
  results,
}, null, 2));
