#!/usr/bin/env node
// 임시 Miniflare/D1만 사용한다. 운영 Worker·D1에 접근하지 않는다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';
import WebSocket, { Receiver } from 'ws';

const backend = fileURLToPath(new URL('..', import.meta.url));
const result = await build({
  entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'],
});
const hasRealtime = result.outputFiles[0].text.includes('class UserRealtime')
  || result.outputFiles[0].text.includes('UserRealtime = class');
const options = { name: 'realtime-test',
  modules: true, script: result.outputFiles[0].text,
  compatibilityDate: '2026-05-20',
  d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'realtime local test' },
  durableObjects: hasRealtime ? { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } : {},
};
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
const connections = [];
function within(promise, label, ms = 4000) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`${label}: 소켓 종료 대기 시간 초과`)), ms); })]).finally(() => clearTimeout(timer));
}
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort()) {
    const sql = (await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' ');
    await db.exec(sql);
  }
  const tokenA = 'realtime-local-user-a';
  const tokenA2 = 'realtime-local-user-a-other-device';
  const tokenB = 'realtime-local-user-b';
  const tokenC = 'realtime-local-unrelated-user';
  const hash = value => createHash('sha256').update(value).digest('hex');
  await db.exec("INSERT INTO users(user_id, kakao_id, nickname, is_owner) VALUES (101,'rt-a','보호자',0),(102,'rt-b','사장님',1),(103,'rt-c','관계없음',0);");
  for (const [token, userId] of [[tokenA,101],[tokenA2,101],[tokenB,102],[tokenC,103]]) {
    await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))").bind(hash(token),userId).run();
  }
  await db.exec("INSERT INTO stores(store_id,name,owner_id,partner_status,store_key) VALUES(101,'실시간 테스트',102,'ACTIVE','rt-store'); INSERT INTO pets(pet_id,user_id,name) VALUES(101,101,'초코'); INSERT INTO chat_rooms(room_id,user_id,store_id) VALUES(101,101,101);");
  const api = (path, token, method = 'GET', body) => mf.dispatchFetch(`http://localhost/api${path}`, {
    method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  assert.equal((await api('/realtime', tokenA)).status, 426, '인증된 비-WebSocket 요청은 upgrade를 요구해야 한다');
  assert.equal((await api('/realtime')).status, 401, '익명 WebSocket endpoint 거부');
  assert.equal((await api(`/realtime?token=${tokenA}`)).status, 401, 'query secret 인증 금지');
  async function connect(token) {
    const url = new URL('/api/realtime', await mf.ready);
    url.protocol = 'ws:';
    const ws = new WebSocket(url, { headers: { Authorization: `Bearer ${token}` }, perMessageDeflate: false });
    // Miniflare의 hibernation 소켓은 Close 교환 뒤 TCP FIN을 지연한다.
    // private _receiver 대신 공개 export와 HTTP upgrade socket으로 서버 Close 프레임을 확인한다.
    const receiver = new Receiver();
    const closeFrame = new Promise((resolve, reject) => {
      receiver.once('conclude', (code, reason) => resolve({ code, reason: reason.toString() }));
      receiver.once('error', reject);
    });
    ws.on('upgrade', response => {
      assert.equal(response.statusCode, 101, '유효 Bearer 세션만 upgrade');
      ws.once('open', () => response.socket.on('data', chunk => receiver.write(chunk)));
    });
    const messages = [];
    const closed = new Promise(resolve => ws.addEventListener('close', resolve, { once: true }));
    ws.addEventListener('message', e => messages.push(JSON.parse(e.data)));
    const connection = { ws, messages, closed, closeFrame };
    connections.push(connection);
    await until(() => messages.some(m => m.type === 'ready'));
    return connection;
  }
  async function until(predicate, ms = 3000) {
    const end = Date.now() + ms;
    while (!predicate()) { if (Date.now() > end) assert.fail('실시간 이벤트 대기 시간 초과'); await new Promise(r => setTimeout(r, 10)); }
  }
  const a = await connect(tokenA), a2 = await connect(tokenA2), b = await connect(tokenB), c = await connect(tokenC);
  const changes = connection => connection.messages.filter(m => m.type === 'change');
  const baseline = await (await api('/users/101/notifications', tokenA)).json();
  assert.ok(baseline.cursor);
  const send = await api('/chatrooms/101/messages', tokenB, 'POST', { content: '첫 실시간 메시지' });
  assert.equal(send.status, 201);
  await until(() => changes(a).length === 1 && changes(a2).length === 1 && changes(b).length === 1);
  assert.equal(changes(c).length, 0, '관계없는 사용자에게 변경 이벤트가 새지 않아야 한다');
  assert.equal(changes(a)[0].event_id, changes(b)[0].event_id, '한 변경은 수신자 전체에 동일 ID');
  assert.equal(changes(a)[0].scope, 'chat');
  assert.equal(changes(a)[0].room_id, 101);
  assert.equal(changes(a)[0].content, undefined, 'WebSocket은 내용 대신 invalidation만 전달');
  const cursorPath = `/users/101/notifications?cursor=${encodeURIComponent(JSON.stringify(baseline.cursor))}`;
  const feed = await (await api(cursorPath, tokenA)).json();
  assert.ok(feed.notifications.some(n => n.body.includes('첫 실시간 메시지')), '알림은 영속 피드에서 복구');
  const denied = await api('/chatrooms/101/messages', tokenC, 'POST', { content: '금지' });
  assert.equal(denied.status, 403);
  assert.equal(changes(c).length, 0);
  assert.equal(changes(a).length, 1, '실패한 쓰기는 변경을 발행하지 않아야 한다');
  a.ws.close(1000, 'disconnect');
  await within(a.closed, 'client disconnect');
  const missed = await api('/chatrooms/101/messages', tokenB, 'POST', { content: '오프라인 누락 메시지' });
  assert.equal(missed.status, 201);
  const reconnected = await connect(tokenA);
  const catchup = await (await api(`/users/101/notifications?cursor=${encodeURIComponent(JSON.stringify(feed.cursor))}`, tokenA)).json();
  assert.ok(catchup.notifications.some(n => n.body.includes('오프라인 누락 메시지')), '재연결 때 로컬 커서 이후 catchup');
  assert.equal(changes(reconnected).length, 0, '재연결은 과거 이벤트를 WebSocket으로 재발행하지 않는다');
  assert.equal((await api('/auth/logout', tokenA, 'POST')).status, 200);
  const revoked = await within(reconnected.closeFrame, 'logout revocation');
  assert.equal(revoked.code, 4401, '로그아웃한 세션의 기존 소켓도 즉시 폐기');
  assert.ok([WebSocket.CLOSING, WebSocket.CLOSED].includes(reconnected.ws.readyState));
  const revokedBefore = changes(reconnected).length;
  assert.equal((await api('/realtime', tokenA)).status, 401);
  const a2Before = changes(a2).length;
  await api('/chatrooms/101/messages', tokenB, 'POST', { content: '다른 기기는 유지' });
  await until(() => changes(a2).length > a2Before);
  assert.equal(changes(reconnected).length, revokedBefore, '폐기된 세션에 이후 변경을 전송하지 않는다');
  const reservations = await api('/reservations', tokenA2, 'POST', { pet_id:101, store_id:101, store_name:'실시간 테스트', start_date:'2099-01-01', end_date:'2099-01-01' });
  assert.equal(reservations.status, 201);
  const reservation = await reservations.json();
  await until(() => changes(b).some(m => m.scope === 'reservation' && m.reservation_id === reservation.reservation_id));
  assert.equal((await api(`/reservations/${reservation.reservation_id}/confirm`, tokenB, 'PATCH')).status, 200);
  const diary = await api(`/reservations/${reservation.reservation_id}/diaries`, tokenB, 'POST', { content:'잘 놀았어요' });
  assert.equal(diary.status, 200);
  const diaryData = await diary.json();
  await until(() => changes(a2).some(m => m.scope === 'diary' && m.reservation_id === reservation.reservation_id));
  const diaryCount = changes(a2).filter(m => m.scope === 'diary').length;
  assert.equal((await api(`/diaries/${diaryData.diary_id}`, tokenB, 'DELETE')).status, 200);
  await until(() => changes(a2).filter(m => m.scope === 'diary').length > diaryCount);
  await db.prepare("UPDATE auth_sessions SET expires_at = datetime('now','-1 second') WHERE token_hash = ?").bind(hash(tokenA2)).run();
  const expiredBefore = changes(a2).length;
  // 브로드캐스트 직전에도 세션 유효성을 확인해야 만료 세션에 이벤트가 새지 않는다.
  await api('/chatrooms/101/messages', tokenB, 'POST', { content:'만료 후 이벤트' });
  assert.equal((await within(a2.closeFrame, 'publish expiry')).code, 4401);
  assert.equal(changes(a2).length, expiredBefore, '만료 세션에 변경 이벤트를 전송하지 않는다');
  assert.equal((await api('/realtime', tokenA2)).status, 401);
  assert.equal(changes(c).length, 0);
  await db.prepare("UPDATE auth_sessions SET expires_at = datetime('now','-1 second') WHERE token_hash = ?").bind(hash(tokenC)).run();
  assert.equal((await within(c.closeFrame, 'idle expiry alarm', 35_000)).code, 4401, '유휴 소켓도 alarm에서 만료 세션을 폐기');
  console.log('PASS realtime: Bearer 인증, 사용자 격리, 실패 쓰기 차단, 영속 피드 catchup, 예약/채팅/알림장 invalidation, 로그아웃·만료 소켓 폐기');
} finally {
  for (const { ws } of connections) { try { ws.terminate(); } catch {} }
  await mf.dispose();
}
