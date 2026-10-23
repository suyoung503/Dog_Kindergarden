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

async function request(
  method,
  path,
  { body, rawBody, token, internal, contentType, idempotencyKey } = {},
) {
  const headers = { Accept: "application/json" };
  if (body !== undefined || rawBody !== undefined)
    headers["Content-Type"] = contentType ?? "application/json";
  if (token) headers.Authorization = `Bearer ${token}`;
  if (internal) headers["X-Internal-Key"] = internal;
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  const response = await fetch(`${base}${path}`, {
    method,
    headers,
    body: rawBody !== undefined
      ? rawBody
      : body === undefined
        ? undefined
        : JSON.stringify(body),
  });
  const bytes = new Uint8Array(await response.arrayBuffer());
  const text = new TextDecoder().decode(bytes);
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { status: response.status, data, bytes, headers: response.headers };
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

function notificationPath(userId, cursor) {
  const query = cursor === undefined
    ? ""
    : `?cursor=${encodeURIComponent(JSON.stringify(cursor))}`;
  return `/api/users/${userId}/notifications${query}`;
}

const privacyPolicy = await request("GET", "/privacy");
expect("개인정보처리방침 공개", privacyPolicy.status, 200);
expect(
  "개인정보처리방침 보유기간 표시",
  typeof privacyPolicy.data === "string" && privacyPolicy.data.includes("보유기간과 파기"),
  true,
);
const supportPage = await request("GET", "/support");
expect("고객지원 페이지 공개", supportPage.status, 200);
expect(
  "고객지원 연락처 표시",
  typeof supportPage.data === "string" && supportPage.data.includes("yikum503@naver.com"),
  true,
);
const oversizedRequest = await request("POST", "/api/auth/dev", {
  body: { nickname: "가".repeat(2 * 1024 * 1024) },
});
expect("API 대용량 요청 차단", oversizedRequest.status, 413);
expect("API 대용량 요청 오류 코드", oversizedRequest.data?.code, "PAYLOAD_TOO_LARGE");
const malformedJson = await request("POST", "/api/auth/dev", {
  rawBody: '{"identity":',
});
expect("잘못된 JSON 요청 차단", malformedJson.status, 400);
expect("잘못된 JSON 오류 코드", malformedJson.data?.code, "INVALID_JSON");
const nonObjectJson = await request("POST", "/api/auth/dev", {
  rawBody: "null",
});
expect("객체가 아닌 JSON 요청 차단", nonObjectJson.status, 400);
expect("객체가 아닌 JSON 오류 코드", nonObjectJson.data?.code, "INVALID_JSON");
const arrayJson = await request("POST", "/api/auth/dev", {
  rawBody: "[]",
});
expect("배열 JSON 요청 차단", arrayJson.status, 400);
expect("배열 JSON 오류 코드", arrayJson.data?.code, "INVALID_JSON");
expect(
  "보유기간 정리 API 무인증 차단",
  (await request("POST", "/api/internal/data-retention")).status,
  401,
);
expect(
  "보유기간 정리 API 내부 키 허용",
  (await request("POST", "/api/internal/data-retention", { internal: internalKey })).status,
  200,
);

const guardianLogin = await request("POST", "/api/auth/dev", {
  body: { identity: "auth-test-guardian", nickname: "권한테스트 보호자", is_owner: false },
});
expectOneOf("보호자 로컬 로그인", guardianLogin.status, [200, 201]);
const guardianId = guardianLogin.data.user_id;
const guardianToken = guardianLogin.data.session_token;
const malformedPetRequest = await request("POST", `/api/users/${guardianId}/pets`, {
  token: guardianToken,
  rawBody: '{"name":',
});
expect("인증 API 잘못된 JSON 요청 차단", malformedPetRequest.status, 400);
expect(
  "인증 API 잘못된 JSON 오류 코드",
  malformedPetRequest.data?.code,
  "INVALID_JSON",
);

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

const supportBeforeAdmin = await request("GET", "/api/support/conversation", {
  token: guardianToken,
});
expect("운영자 부재 상태 조회", supportBeforeAdmin.status, 200);
expect("운영자 부재 표시", supportBeforeAdmin.data.admin_available, false);
expect(
  "운영자 부재 시 문의 생성 차단",
  (await request("POST", "/api/support/conversation", { token: guardianToken })).status,
  503,
);

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

const supportConversation = await request("POST", "/api/support/conversation", {
  token: guardianToken,
});
expectOneOf("운영자 등록 후 1:1 문의 생성", supportConversation.status, [200, 201]);
const supportConversationId = supportConversation.data.conversation_id;
expect(
  "일반 사용자의 전체 고객 문의 목록 접근 차단",
  (await request("GET", "/api/support/conversations", { token: guardianToken })).status,
  403,
);
expect(
  "운영자 계정의 일반 사용자 문의 생성 차단",
  (await request("POST", "/api/support/conversation", { token: adminToken })).status,
  403,
);
expect(
  "다른 사용자의 문의 메시지 조회 차단",
  (await request("GET", `/api/support/conversations/${supportConversationId}/messages`, {
    token: ownerToken,
  })).status,
  403,
);
expect(
  "문의 작성자 메시지 전송",
  (await request("POST", `/api/support/conversations/${supportConversationId}/messages`, {
    token: guardianToken,
    body: { content: "운영자에게 보내는 테스트 문의" },
  })).status,
  201,
);
const supportAdminList = await request("GET", "/api/support/conversations", {
  token: adminToken,
});
expect("운영자 고객 문의 목록 조회", supportAdminList.status, 200);
expect(
  "운영자 목록에 사용자 문의 노출",
  supportAdminList.data.some((item) => item.conversation_id === supportConversationId),
  true,
);
expect(
  "운영자 문의 메시지 조회",
  (await request("GET", `/api/support/conversations/${supportConversationId}/messages`, {
    token: adminToken,
  })).status,
  200,
);
expect(
  "운영자 문의 답장",
  (await request("POST", `/api/support/conversations/${supportConversationId}/messages`, {
    token: adminToken,
    body: { content: "운영자 테스트 답변" },
  })).status,
  201,
);
const supportMessagesAfterReply = await request(
  "GET",
  `/api/support/conversations/${supportConversationId}/messages`,
  { token: guardianToken },
);
expect("문의 작성자의 답장 조회", supportMessagesAfterReply.status, 200);
expect(
  "운영자 답장 역할 보존",
  supportMessagesAfterReply.data.some(
    (message) => message.content === "운영자 테스트 답변" && message.sender_role === "ADMIN",
  ),
  true,
);

const adminNotificationBaseline = await request(
  "GET",
  notificationPath(adminLogin.data.user_id),
  { token: adminToken },
);
expect("운영자 알림 기준 커서 생성", adminNotificationBaseline.status, 200);
const guardianNotificationBaseline = await request(
  "GET",
  notificationPath(guardianId),
  { token: guardianToken },
);
expect("보호자 알림 기준 커서 생성", guardianNotificationBaseline.status, 200);
const legacyAdminCursor = {
  message_id: adminNotificationBaseline.data.cursor.message_id,
  request_id: adminNotificationBaseline.data.cursor.request_id,
  canceled_at: adminNotificationBaseline.data.cursor.canceled_at,
};
const legacyCursorNotifications = await request(
  "GET",
  notificationPath(adminLogin.data.user_id, legacyAdminCursor),
  { token: adminToken },
);
expect("구버전 커서 호환 조회", legacyCursorNotifications.status, 200);
expect(
  "구버전 커서에서 과거 문의 알림 폭탄 방지",
  legacyCursorNotifications.data.notifications.some((item) => item.type === "support"),
  false,
);

expect(
  "알림 검증용 사용자 문의 전송",
  (await request("POST", `/api/support/conversations/${supportConversationId}/messages`, {
    token: guardianToken,
    body: { content: "운영자 알림으로 전달될 문의" },
  })).status,
  201,
);
const adminSupportNotifications = await request(
  "GET",
  notificationPath(adminLogin.data.user_id, adminNotificationBaseline.data.cursor),
  { token: adminToken },
);
expect("운영자 문의 알림 조회", adminSupportNotifications.status, 200);
const adminSupportNotification = adminSupportNotifications.data.notifications.find(
  (item) => item.type === "support" && item.conversation_id === supportConversationId,
);
expect(
  "운영자 문의 알림에 대화 연결 포함",
  Boolean(adminSupportNotification),
  true,
);
expect(
  "문의 알림의 안정적 이벤트 식별자",
  adminSupportNotification?.event_id?.startsWith("support:") ?? false,
  true,
);
const repeatedAdminSupportNotifications = await request(
  "GET",
  notificationPath(adminLogin.data.user_id, adminNotificationBaseline.data.cursor),
  { token: adminToken },
);
expect(
  "같은 커서 재조회 시 문의 이벤트 식별자 유지",
  repeatedAdminSupportNotifications.data.notifications.find(
    (item) => item.type === "support" && item.conversation_id === supportConversationId,
  )?.event_id,
  adminSupportNotification.event_id,
);

expect(
  "알림 검증용 운영자 답장 전송",
  (await request("POST", `/api/support/conversations/${supportConversationId}/messages`, {
    token: adminToken,
    body: { content: "보호자 알림으로 전달될 답변" },
  })).status,
  201,
);
const guardianSupportNotifications = await request(
  "GET",
  notificationPath(guardianId, guardianNotificationBaseline.data.cursor),
  { token: guardianToken },
);
expect("보호자 문의 답장 알림 조회", guardianSupportNotifications.status, 200);
expect(
  "보호자 문의 알림에 본인 대화만 포함",
  guardianSupportNotifications.data.notifications.some(
    (item) => item.type === "support" && item.conversation_id === supportConversationId,
  ),
  true,
);
const adminNotificationCursorAfterSupport = adminSupportNotifications.data.cursor;

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
  open_time: "09:00 / 18:00",
  price_info: "종일권 35,000원",
  image_url: "https://example.com/partner-main.jpg",
  image_urls: ["https://example.com/partner-sub.jpg"],
  pickup: true,
  playground: true,
  large_dog: true,
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
const generalStoreDetail = await request(
  "GET",
  `/api/stores/detail?storeKey=${encodeURIComponent(store.store_key)}`,
);
expect("일반 업체 상세 조회", generalStoreDetail.status, 200);
expect("일반 업체 파트너 표시 차단", generalStoreDetail.data.is_partner, false);
expect("일반 업체 예약 capability 차단", generalStoreDetail.data.can_book, false);
expect("일반 업체 채팅 capability 차단", generalStoreDetail.data.can_chat, false);
expect("일반 업체 리뷰 capability 차단", generalStoreDetail.data.can_review, false);
expect("일반 업체 크롤링 영업시간 숨김", generalStoreDetail.data.open_time, null);
expect("일반 업체 크롤링 가격 숨김", generalStoreDetail.data.price_info, null);
expect("일반 업체 크롤링 대표 이미지 숨김", generalStoreDetail.data.image_url, null);
expect("일반 업체 크롤링 추가 이미지 숨김", generalStoreDetail.data.images.length, 0);
expect(
  "일반 업체 채팅방 생성 차단",
  (await request("POST", "/api/chatrooms", {
    body: { user_id: guardianId, ...store },
    token: guardianToken,
  })).status,
  403,
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

const legacyOwnerApplicationNotifications = await request(
  "GET",
  notificationPath(adminLogin.data.user_id, legacyAdminCursor),
  { token: adminToken },
);
expect("구버전 커서의 등록 요청 호환 조회", legacyOwnerApplicationNotifications.status, 200);
expect(
  "구버전 커서에서 과거 등록 요청 알림 폭탄 방지",
  legacyOwnerApplicationNotifications.data.notifications.some(
    (item) => item.type === "owner_application",
  ),
  false,
);

const ownerApplicationNotifications = await request(
  "GET",
  notificationPath(adminLogin.data.user_id, adminNotificationCursorAfterSupport),
  { token: adminToken },
);
expect("운영자 가게 등록 요청 알림 조회", ownerApplicationNotifications.status, 200);
expect(
  "가게 등록 요청 알림에 신청 번호 포함",
  ownerApplicationNotifications.data.notifications.some(
    (item) => item.type === "owner_application" && item.application_id === applicationId,
  ),
  true,
);
expect(
  "등록 요청 알림의 안정적 이벤트 식별자",
  ownerApplicationNotifications.data.notifications.find(
    (item) => item.type === "owner_application" && item.application_id === applicationId,
  )?.event_id,
  `owner_application:${applicationId}`,
);

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
const partnerStoreDetail = await request(
  "GET",
  `/api/stores/detail?storeKey=${encodeURIComponent(store.store_key)}`,
);
expect("승인 업체 파트너 표시", partnerStoreDetail.data.is_partner, true);
expect("승인 업체 예약 capability", partnerStoreDetail.data.can_book, true);
expect("승인 업체 채팅 capability", partnerStoreDetail.data.can_chat, true);
expect("승인 업체 알림장 capability", partnerStoreDetail.data.can_diary, true);
expect("승인 업체 리뷰 capability", partnerStoreDetail.data.can_review, true);
expect("승인 업체도 미검증 영업시간 숨김", partnerStoreDetail.data.open_time, null);
expect("승인 업체도 미검증 가격 숨김", partnerStoreDetail.data.price_info, null);
expect("승인 업체도 미검증 대표 이미지 숨김", partnerStoreDetail.data.image_url, null);
expect("승인 업체도 미검증 이미지 갤러리 숨김", partnerStoreDetail.data.images.length, 0);
expect(
  "장소 보강 API 무인증 차단",
  (await request(
    "GET",
    `/api/store-enrichment/place?storeKey=${encodeURIComponent(store.store_key)}`,
  )).status,
  401,
);
expect(
  "등록되지 않은 가게 보강 차단",
  (await request(
    "GET",
    "/api/store-enrichment/place?storeKey=missing-store",
    { token: guardianToken },
  )).status,
  404,
);
expect(
  "Worker 장소 Secret 미설정 응답",
  (await request(
    "GET",
    `/api/store-enrichment/place?storeKey=${encodeURIComponent(store.store_key)}`,
    { token: guardianToken },
  )).status,
  503,
);
expect(
  "Worker 블로그 Secret 미설정 응답",
  (await request(
    "GET",
    `/api/store-enrichment/blogs?storeKey=${encodeURIComponent(store.store_key)}`,
    { token: guardianToken },
  )).status,
  503,
);
expect(
  "승인 업체 채팅방 생성 허용",
  (await request("POST", "/api/chatrooms", {
    body: { user_id: guardianId, ...store },
    token: guardianToken,
  })).status,
  201,
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
const rejectedStoreDetail = await request(
  "GET",
  `/api/stores/detail?storeKey=${encodeURIComponent(rejectedStore.store_key)}`,
);
expect("거절 업체 파트너 비활성", rejectedStoreDetail.data.is_partner, false);
expect("거절 업체 예약 비활성", rejectedStoreDetail.data.can_book, false);
expect(
  "일반 업체 장소 보강 차단",
  (await request(
    "GET",
    `/api/store-enrichment/place?storeKey=${encodeURIComponent(rejectedStore.store_key)}`,
    { token: guardianToken },
  )).status,
  403,
);

const guardianPet = await request("POST", `/api/users/${guardianId}/pets`, {
  body: {
    name: "보호자 강아지",
    image_url: "data:image/jpeg;base64,/9j/2Q==",
  },
  token: guardianToken,
});
expect("본인 강아지 등록", guardianPet.status, 201);
expect(
  "강아지 갤러리 사진 저장",
  guardianPet.data.image_url,
  "data:image/jpeg;base64,/9j/2Q==",
);
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
expect(
  "일반 업체 예약 생성 차단",
  (await request("POST", "/api/reservations", {
    body: {
      user_id: guardianId,
      pet_id: guardianPet.data.pet_id,
      ...rejectedStore,
      start_date: "2026-10-10 (토)",
      end_date: "2026-10-10 (토)",
      reservation_type: "종일권",
    },
    token: guardianToken,
  })).status,
  403,
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

const malformedCancellation = await request(
  "PATCH",
  `/api/reservations/${reservationId}/cancel`,
  { token: guardianToken, rawBody: '{"by_owner":' },
);
expect("예약 취소 잘못된 JSON 요청 차단", malformedCancellation.status, 400);
expect(
  "예약 취소 잘못된 JSON 오류 코드",
  malformedCancellation.data?.code,
  "INVALID_JSON",
);

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
const createdDiary = await request(
  "POST",
  `/api/reservations/${reservationId}/diaries`,
  {
    body: { content: "정상 알림장" },
    token: ownerToken,
  },
);
expect("가게 사장님 알림장 작성", createdDiary.status, 200);
const diaryId = createdDiary.data.diary_id;

const jpeg = Buffer.from(
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDfooor8eP1U//Z",
  "base64",
);
expect(
  "보호자 알림장 사진 업로드 차단",
  (await request("POST", `/api/diaries/${diaryId}/photos`, {
    rawBody: jpeg,
    token: guardianToken,
    contentType: "image/jpeg",
    idempotencyKey: crypto.randomUUID(),
  })).status,
  403,
);
expect(
  "JPEG가 아닌 Content-Type 차단",
  (await request("POST", `/api/diaries/${diaryId}/photos`, {
    rawBody: jpeg,
    token: ownerToken,
    contentType: "image/png",
    idempotencyKey: crypto.randomUUID(),
  })).status,
  400,
);
expect(
  "JPEG magic byte 누락 차단",
  (await request("POST", `/api/diaries/${diaryId}/photos`, {
    rawBody: Uint8Array.from([0x89, 0x50, 0x4e, 0x47]),
    token: ownerToken,
    contentType: "image/jpeg",
    idempotencyKey: crypto.randomUUID(),
  })).status,
  400,
);
expect(
  "디코딩할 수 없는 JPEG 모양 데이터 차단",
  (await request("POST", `/api/diaries/${diaryId}/photos`, {
    rawBody: Uint8Array.from([0xff, 0xd8, 0xff, 0xd9]),
    token: ownerToken,
    contentType: "image/jpeg",
    idempotencyKey: crypto.randomUUID(),
  })).status,
  400,
);
const oversizedJpeg = new Uint8Array(1.5 * 1024 * 1024 + 1);
oversizedJpeg.set([0xff, 0xd8, 0xff]);
expect(
  "1.5MB 초과 알림장 사진 차단",
  (await request("POST", `/api/diaries/${diaryId}/photos`, {
    rawBody: oversizedJpeg,
    token: ownerToken,
    contentType: "image/jpeg",
    idempotencyKey: crypto.randomUUID(),
  })).status,
  413,
);

const uploadedPhotos = [];
const uploadRequestIds = [];
for (let index = 0; index < 3; index += 1) {
  const idempotencyKey = crypto.randomUUID();
  const uploaded = await request("POST", `/api/diaries/${diaryId}/photos`, {
    rawBody: jpeg,
    token: ownerToken,
    contentType: "image/jpeg",
    idempotencyKey,
  });
  expect(`알림장 사진 ${index + 1}장 업로드`, uploaded.status, 201);
  expect(
    `알림장 사진 ${index + 1}장 URL 계약`,
    uploaded.data.url,
    `/api/diary-photos/${uploaded.data.photo_id}`,
  );
  uploadedPhotos.push(uploaded.data);
  uploadRequestIds.push(idempotencyKey);
}
const repeatedUpload = await request("POST", `/api/diaries/${diaryId}/photos`, {
  rawBody: jpeg,
  token: ownerToken,
  contentType: "image/jpeg",
  idempotencyKey: uploadRequestIds[0],
});
expect("알림장 사진 업로드 재시도 멱등 성공", repeatedUpload.status, 200);
expect("알림장 사진 업로드 재시도 ID 유지", repeatedUpload.data.photo_id, uploadedPhotos[0].photo_id);
expect(
  "알림장 사진 4번째 업로드 차단",
  (await request("POST", `/api/diaries/${diaryId}/photos`, {
    rawBody: jpeg,
    token: ownerToken,
    contentType: "image/jpeg",
    idempotencyKey: crypto.randomUUID(),
  })).status,
  409,
);

const diariesWithPhotos = await request(
  "GET",
  `/api/reservations/${reservationId}/diaries`,
  { token: guardianToken },
);
expect("보호자 알림장 사진 목록 조회", diariesWithPhotos.status, 200);
const listedDiary = diariesWithPhotos.data.find((item) => item.diary_id === diaryId);
expect("알림장 사진 목록 최대 3장", listedDiary.photos.length, 3);
expect(
  "알림장 사진 목록 URL 계약",
  listedDiary.photos[0].url,
  `/api/diary-photos/${uploadedPhotos[0].photo_id}`,
);
const updatedDiaryWithPhotos = await request("PATCH", `/api/diaries/${diaryId}`, {
  token: ownerToken,
  body: { content: "사진이 유지되는 수정 알림장" },
});
expect("알림장 수정 후 사진 유지", updatedDiaryWithPhotos.data.photos.length, 3);

const ownerPhoto = await request(
  "GET",
  `/api/diary-photos/${uploadedPhotos[0].photo_id}`,
  { token: ownerToken },
);
expect("가게 소유자 알림장 사진 조회", ownerPhoto.status, 200);
expect("알림장 사진 JPEG Content-Type", ownerPhoto.headers.get("content-type"), "image/jpeg");
expect("알림장 사진 private/no-store", ownerPhoto.headers.get("cache-control"), "private, no-store");
expect("알림장 사진 원본 바이트", Buffer.from(ownerPhoto.bytes).equals(Buffer.from(jpeg)), true);
expect(
  "예약 보호자 알림장 사진 조회",
  (await request("GET", `/api/diary-photos/${uploadedPhotos[0].photo_id}`, {
    token: guardianToken,
  })).status,
  200,
);
expect(
  "다른 사용자 알림장 사진 조회 차단",
  (await request("GET", `/api/diary-photos/${uploadedPhotos[0].photo_id}`, {
    token: otherOwnerToken,
  })).status,
  403,
);
expect(
  "보호자 알림장 사진 삭제 차단",
  (await request("DELETE", `/api/diary-photos/${uploadedPhotos[0].photo_id}`, {
    token: guardianToken,
  })).status,
  403,
);
expect(
  "가게 소유자 알림장 사진 삭제",
  (await request("DELETE", `/api/diary-photos/${uploadedPhotos[0].photo_id}`, {
    token: ownerToken,
  })).status,
  200,
);
expect(
  "삭제한 알림장 사진 조회 불가",
  (await request("GET", `/api/diary-photos/${uploadedPhotos[0].photo_id}`, {
    token: ownerToken,
  })).status,
  404,
);
expect(
  "삭제한 알림장 사진 재삭제 멱등 성공",
  (await request("DELETE", `/api/diary-photos/${uploadedPhotos[0].photo_id}`, {
    token: ownerToken,
  })).status,
  200,
);
expect(
  "알림장 삭제",
  (await request("DELETE", `/api/diaries/${diaryId}`, { token: ownerToken })).status,
  200,
);
for (const photo of uploadedPhotos.slice(1)) {
  expect(
    "알림장 삭제 후 사진 조회 불가",
    (await request("GET", `/api/diary-photos/${photo.photo_id}`, {
      token: ownerToken,
    })).status,
    404,
  );
}
const diariesAfterDelete = await request(
  "GET",
  `/api/reservations/${reservationId}/diaries`,
  { token: guardianToken },
);
expect(
  "알림장 삭제 후 D1 행 정리",
  diariesAfterDelete.data.some((item) => item.diary_id === diaryId),
  false,
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

// ── 회원 탈퇴: 진행 예약 차단 → 개인정보 삭제/익명화 → 모든 세션 폐기 ──
const deletingGuardianLogin = await request("POST", "/api/auth/dev", {
  body: {
    identity: `delete-guardian-${runId}`,
    nickname: "탈퇴 테스트 보호자",
    is_owner: false,
  },
});
expect("탈퇴 테스트 보호자 로그인", deletingGuardianLogin.status, 201);
const deletingGuardianId = deletingGuardianLogin.data.user_id;
const deletingGuardianToken = deletingGuardianLogin.data.session_token;
const deletingGuardianSecondLogin = await request("POST", "/api/auth/dev", {
  body: {
    identity: `delete-guardian-${runId}`,
    nickname: "탈퇴 테스트 보호자",
    is_owner: false,
  },
});
expect("탈퇴 테스트 다른 기기 세션 발급", deletingGuardianSecondLogin.status, 200);
const deletingGuardianSecondToken = deletingGuardianSecondLogin.data.session_token;

expect(
  "탈퇴 전 프로필 개인정보 저장",
  (await request("PUT", `/api/users/${deletingGuardianId}`, {
    token: deletingGuardianToken,
    body: { nickname: "삭제될 이름", phone: "010-1234-5678", address: "삭제될 주소" },
  })).status,
  200,
);
const deletingPet = await request("POST", `/api/users/${deletingGuardianId}/pets`, {
  token: deletingGuardianToken,
  body: { name: "삭제될 강아지", note: "삭제될 메모" },
});
expect("탈퇴 전 강아지 저장", deletingPet.status, 201);
expect(
  "타인의 회원 탈퇴 요청 차단",
  (await request("DELETE", `/api/users/${deletingGuardianId}/account`, {
    token: ownerToken,
  })).status,
  403,
);
expect(
  "탈퇴 전 찜 저장",
  (await request("POST", "/api/favorites", {
    token: deletingGuardianToken,
    body: { user_id: deletingGuardianId, ...store },
  })).status,
  201,
);

const futureDeletionReservation = await request("POST", "/api/reservations", {
  token: deletingGuardianToken,
  body: {
    user_id: deletingGuardianId,
    pet_id: deletingPet.data.pet_id,
    ...store,
    start_date: "2099-12-30 (수)",
    end_date: "2099-12-30 (수)",
    reservation_type: "종일권",
    request_message: "삭제 전 진행 예약",
  },
});
expect("탈퇴 차단용 진행 예약 생성", futureDeletionReservation.status, 201);
const blockedGuardianDeletion = await request(
  "DELETE",
  `/api/users/${deletingGuardianId}/account`,
  { token: deletingGuardianToken },
);
expect("진행 예약이 있는 보호자 탈퇴 차단", blockedGuardianDeletion.status, 409);
expect("보호자 탈퇴 차단 사유", blockedGuardianDeletion.data.code, "ACTIVE_RESERVATIONS");
expect("보호자 진행 예약 수 반환", blockedGuardianDeletion.data.active_reservations, 1);
expect(
  "탈퇴 차단 후 세션 유지",
  (await request("GET", `/api/users/${deletingGuardianId}/pets`, {
    token: deletingGuardianToken,
  })).status,
  200,
);
expect(
  "탈퇴 전 진행 예약 취소",
  (await request("PATCH", `/api/reservations/${futureDeletionReservation.data.reservation_id}/cancel`, {
    token: deletingGuardianToken,
  })).status,
  200,
);

// 완료 이용 후기와 예약은 익명 운영 기록으로 남고, 개인 데이터는 새 계정에 승계되지 않는다.
const pastDeletionReservation = await request("POST", "/api/reservations", {
  token: deletingGuardianToken,
  body: {
    user_id: deletingGuardianId,
    pet_id: deletingPet.data.pet_id,
    ...store,
    start_date: "2000-01-01 (토)",
    end_date: "2000-01-01 (토)",
    reservation_type: "종일권",
    request_message: "삭제될 요청 메모",
  },
});
expect("탈퇴 전 완료 대상 예약 생성", pastDeletionReservation.status, 201);
expect(
  "탈퇴 전 완료 대상 예약 확정",
  (await request("PATCH", `/api/reservations/${pastDeletionReservation.data.reservation_id}/confirm`, {
    token: ownerToken,
  })).status,
  200,
);
const deletingGuardianDiary = await request(
  "POST",
  `/api/reservations/${pastDeletionReservation.data.reservation_id}/diaries`,
  {
    body: { content: "탈퇴 시 사진까지 삭제될 알림장" },
    token: ownerToken,
  },
);
expect("탈퇴 전 알림장 생성", deletingGuardianDiary.status, 200);
const deletingGuardianPhoto = await request(
  "POST",
  `/api/diaries/${deletingGuardianDiary.data.diary_id}/photos`,
  {
    rawBody: jpeg,
    token: ownerToken,
    contentType: "image/jpeg",
    idempotencyKey: crypto.randomUUID(),
  },
);
expect("탈퇴 전 알림장 사진 업로드", deletingGuardianPhoto.status, 201);
expect(
  "탈퇴 전 검증 리뷰 저장",
  (await request("POST", "/api/pet-reviews", {
    token: deletingGuardianToken,
    body: {
      user_id: deletingGuardianId,
      store_key: store.store_key,
      store_name: store.store_name,
      rating: 5,
      content: "익명으로 보존할 후기",
    },
  })).status,
  201,
);
expect(
  "탈퇴 전 개인 채팅 저장",
  (await request("POST", `/api/chatrooms/${pastDeletionReservation.data.room_id}/messages`, {
    token: deletingGuardianToken,
    body: { content: "삭제될 개인 채팅" },
  })).status,
  201,
);

expect(
  "보호자 계정 탈퇴 완료",
  (await request("DELETE", `/api/users/${deletingGuardianId}/account`, {
    token: deletingGuardianToken,
  })).status,
  200,
);
expect(
  "탈퇴 요청 세션 즉시 폐기",
  (await request("GET", `/api/users/${deletingGuardianId}/pets`, {
    token: deletingGuardianToken,
  })).status,
  401,
);
expect(
  "탈퇴 계정 다른 기기 세션도 폐기",
  (await request("GET", `/api/users/${deletingGuardianId}/pets`, {
    token: deletingGuardianSecondToken,
  })).status,
  401,
);
expect(
  "탈퇴 후 알림장 사진 메타데이터·객체 접근 불가",
  (await request("GET", `/api/diary-photos/${deletingGuardianPhoto.data.photo_id}`, {
    token: ownerToken,
  })).status,
  404,
);
const publicReviewsAfterDeletion = await request(
  "GET",
  `/api/pet-reviews?storeKey=${encodeURIComponent(store.store_key)}`,
);
expect("탈퇴 후 리뷰 공개 조회", publicReviewsAfterDeletion.status, 200);
expect(
  "탈퇴 후 리뷰 작성자·본문 익명화",
  publicReviewsAfterDeletion.data.reviews.some(
    (review) => review.content === "" && review.user_name === "익명",
  ),
  true,
);

const recreatedGuardian = await request("POST", "/api/auth/dev", {
  body: {
    identity: `delete-guardian-${runId}`,
    nickname: "재가입 보호자",
    is_owner: false,
  },
});
expect("탈퇴 후 재가입", recreatedGuardian.status, 201);
expect("재가입은 새 사용자 번호 발급", recreatedGuardian.data.user_id !== deletingGuardianId, true);
expect(
  "재가입 계정에 강아지 데이터 없음",
  (await request("GET", `/api/users/${recreatedGuardian.data.user_id}/pets`, {
    token: recreatedGuardian.data.session_token,
  })).data.length,
  0,
);
expect(
  "재가입 계정에 찜 데이터 없음",
  (await request("GET", `/api/users/${recreatedGuardian.data.user_id}/favorites`, {
    token: recreatedGuardian.data.session_token,
  })).data.length,
  0,
);
expect(
  "재가입 계정에 예약 데이터 없음",
  (await request("GET", `/api/users/${recreatedGuardian.data.user_id}/reservations`, {
    token: recreatedGuardian.data.session_token,
  })).data.length,
  0,
);

// 사장님은 자신이 소유한 가게에 진행 예약이 있으면 탈퇴할 수 없고, 취소 후에는 연결이 해제된다.
const deletingOwnerLogin = await request("POST", "/api/auth/dev", {
  body: {
    identity: `delete-owner-${runId}`,
    nickname: "탈퇴 테스트 사장님",
    is_owner: true,
  },
});
expect("탈퇴 테스트 사장님 로그인", deletingOwnerLogin.status, 201);
const deletingOwnerId = deletingOwnerLogin.data.user_id;
const deletingOwnerToken = deletingOwnerLogin.data.session_token;
const deletingOwnerStore = {
  store_key: `delete-owner-store-${runId}`,
  store_name: "탈퇴 안전 규칙 가게",
  store_address: "서울 테스트구",
  store_type: "유치원",
};
expect(
  "탈퇴 테스트 사장님 가게 등록",
  (await request("POST", "/api/admin/stores/import", {
    body: deletingOwnerStore,
    internal: internalKey,
  })).status,
  201,
);
const deletingOwnerApplication = await request("POST", "/api/stores/claim", {
  body: { user_id: deletingOwnerId, ...deletingOwnerStore },
  token: deletingOwnerToken,
});
expect("탈퇴 테스트 사장님 등록 요청", deletingOwnerApplication.status, 201);
expect(
  "탈퇴 테스트 사장님 등록 승인",
  (await request("PATCH", `/api/owner-applications/${deletingOwnerApplication.data.application_id}/approve`, {
    token: adminToken,
  })).status,
  200,
);
const recreatedPet = await request("POST", `/api/users/${recreatedGuardian.data.user_id}/pets`, {
  token: recreatedGuardian.data.session_token,
  body: { name: "사장님 탈퇴 차단 강아지" },
});
expect("사장님 탈퇴 차단용 강아지 생성", recreatedPet.status, 201);
const ownerBlockingReservation = await request("POST", "/api/reservations", {
  token: recreatedGuardian.data.session_token,
  body: {
    user_id: recreatedGuardian.data.user_id,
    pet_id: recreatedPet.data.pet_id,
    ...deletingOwnerStore,
    start_date: "2099-12-31 (목)",
    end_date: "2099-12-31 (목)",
    reservation_type: "종일권",
  },
});
expect("사장님 탈퇴 차단용 예약 생성", ownerBlockingReservation.status, 201);
const blockedOwnerDeletion = await request("DELETE", `/api/users/${deletingOwnerId}/account`, {
  token: deletingOwnerToken,
});
expect("가게 진행 예약이 있는 사장님 탈퇴 차단", blockedOwnerDeletion.status, 409);
expect("가게 진행 예약 수 반환", blockedOwnerDeletion.data.active_owned_reservations, 1);
expect(
  "사장님 탈퇴 전 고객 예약 취소",
  (await request("PATCH", `/api/reservations/${ownerBlockingReservation.data.reservation_id}/cancel`, {
    token: recreatedGuardian.data.session_token,
  })).status,
  200,
);
expect(
  "사장님 계정 탈퇴 완료",
  (await request("DELETE", `/api/users/${deletingOwnerId}/account`, {
    token: deletingOwnerToken,
  })).status,
  200,
);
expect(
  "탈퇴 사장님 토큰 폐기",
  (await request("GET", `/api/owners/${deletingOwnerId}/stores`, {
    token: deletingOwnerToken,
  })).status,
  401,
);
const reclaimedAfterOwnerDeletion = await request("POST", "/api/stores/claim", {
  body: { user_id: otherOwnerId, ...deletingOwnerStore },
  token: otherOwnerToken,
});
expect("사장님 탈퇴 후 가게 연결 해제", reclaimedAfterOwnerDeletion.status, 201);
expect("해제 가게는 새 승인 대기", reclaimedAfterOwnerDeletion.data.status, "PENDING");
const releasedStoreDetail = await request(
  "GET",
  `/api/stores/detail?storeKey=${encodeURIComponent(deletingOwnerStore.store_key)}`,
);
expect("사장님 탈퇴 후 파트너 비활성", releasedStoreDetail.data.is_partner, false);
expect("사장님 탈퇴 후 예약 비활성", releasedStoreDetail.data.can_book, false);

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
