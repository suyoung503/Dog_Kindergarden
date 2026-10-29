type PublicStore = { name: string; address: string | null; phone: string | null };
type StoreShareDatabase = {
  prepare(sql: string): { bind(key: string): { first<T>(): Promise<T | null> } };
};

const headers = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store",
  "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

function escapeHTML(value: string): string {
  const entities: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
  return value.replace(/[&<>"']/g, char => entities[char]);
}

function page(content: string, status: number): Response {
  return new Response(`<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>맡겨멍 · 가게 정보</title><style>body{font-family:system-ui,sans-serif;background:#faf3e7;color:#513624;margin:0;padding:32px 20px;line-height:1.6}main{max-width:480px;margin:40px auto;background:white;padding:28px;border-radius:20px}h1{font-size:24px;overflow-wrap:anywhere}p{overflow-wrap:anywhere}a{display:block;text-align:center;background:#ed8b40;color:#28190e;text-decoration:none;padding:14px;border-radius:12px;font-weight:700}small{color:#725e51}</style></head><body><main><small>맡겨멍 · 가게 정보</small>${content}</main></body></html>`, { status, headers });
}

export async function storeShareResponse(request: Request, db: StoreShareDatabase): Promise<Response> {
  const url = new URL(request.url);
  const entries = [...url.searchParams.entries()];
  const key = entries[0]?.[1] ?? "";
  if (url.pathname !== "/store" || entries.length !== 1 || entries[0][0] !== "key"
    || !key || key.trim() !== key || new TextEncoder().encode(key).length > 512
    || /[\u0000-\u001f\u007f-\u009f]/u.test(key)) {
    return page("<h1>올바르지 않은 가게 링크예요</h1><p>공유한 분에게 링크를 다시 요청해주세요.</p>", 400);
  }
  try {
    // 공개 지도에 나오는 가게의 최소 필드만 조회한다. 사장님/계정/예약 정보는 조회하지 않는다.
    const store = await db.prepare(
      "SELECT name, address, phone FROM stores WHERE store_key = ? AND is_curated = 1 AND store_type IN ('호텔', '유치원') LIMIT 1",
    ).bind(key).first<PublicStore>();
    if (!store) return page("<h1>가게를 찾을 수 없어요</h1><p>삭제되었거나 더 이상 공개되지 않는 가게일 수 있어요.</p>", 404);
    // 외부/DB URL을 링크로 사용하지 않는다. 앱 링크의 scheme/host/path는 고정되어 있다.
    const appURL = `matgyeomung://store?key=${encodeURIComponent(key)}`;
    return page(`<h1>${escapeHTML(store.name)}</h1><p>${escapeHTML(store.address || "주소 정보가 없어요")}</p><p>${escapeHTML(store.phone || "전화번호 정보가 없어요")}</p><a href="${escapeHTML(appURL)}">맡겨멍 앱에서 가게 열기</a><p><small>앱이 설치되어 있지 않다면 이 페이지에서 가게 기본 정보를 확인해주세요. 앱이 설치되어 있다면 위 버튼으로 해당 가게를 열 수 있어요. 로그인 후 가게 상세로 이동해요.</small></p>`, 200);
  } catch {
    return page("<h1>가게 정보를 불러오지 못했어요</h1><p>잠시 후 이 페이지를 새로고침해주세요.</p>", 503);
  }
}
