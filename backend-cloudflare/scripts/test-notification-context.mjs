#!/usr/bin/env node
// 격리된 Miniflare/D1만 사용한다. 예약 이벤트를 일반 채팅으로 합치는 회귀를 검증한다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';
const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'notification-context-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'notification context local test' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort()) {
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  }
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner) VALUES(601,'context-customer','보호자',0),(602,'context-owner','사장님',1);
    INSERT INTO stores(store_id,name,store_key,owner_id,partner_status) VALUES(601,'예약 테스트','context-store',602,'ACTIVE');
    INSERT INTO pets(pet_id,user_id,name) VALUES(601,601,'초코');
    INSERT INTO chat_rooms(room_id,user_id,store_id) VALUES(601,601,601);`.replace(/\n/g, ' '));
  for (const id of [601,602]) await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(`context-token-${id}`).digest('hex'), id).run();
  const api = (path, id, method = 'GET', body) => mf.dispatchFetch(`http://localhost/api${path}`, {
    method, headers: { Authorization: `Bearer context-token-${id}`, ...(body ? {'Content-Type':'application/json'} : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const feed = async (id, cursor) => {
    const response = await api(`/users/${id}/notifications${cursor ? `?cursor=${encodeURIComponent(JSON.stringify(cursor))}` : ''}`, id);
    assert.equal(response.status, 200); return response.json();
  };
  const reserve = async () => {
    const response = await api('/reservations',601,'POST',{pet_id:601,store_id:601,store_name:'예약 테스트',start_date:'2099-01-01',end_date:'2099-01-01'});
    assert.equal(response.status,201); return response.json();
  };
  const first = await reserve(), second = await reserve();
  const baseline = await feed(601);
  assert.equal((await api(`/reservations/${first.reservation_id}/cancel`,602,'PATCH',{by_owner:true})).status,200);
  assert.equal((await api(`/reservations/${second.reservation_id}/confirm`,602,'PATCH')).status,200);
  for (const content of ['일반 대화1','일반 대화2']) assert.equal((await api('/chatrooms/601/messages',602,'POST',{content})).status,201);
  const result = await feed(601,baseline.cursor);
  const canceled = result.notifications.filter(n => n.type === 'reservation_canceled');
  assert.equal(canceled.length,1,'가게 취소는 별도 예약 알림이어야 한다');
  assert.equal(canceled[0].reservation_id,first.reservation_id);
  assert.equal(canceled[0].as_owner,false);
  assert.match(canceled[0].event_id,/^chat:\d+$/,'기존 메시지 이벤트 ID 유지');
  assert.match(canceled[0].body,/가게 사정/);
  const confirmed = result.notifications.filter(n => n.type === 'reservation_confirmed');
  assert.equal(confirmed.length,1,'같은 방의 확정 이벤트도 합치지 않는다');
  assert.equal(confirmed[0].reservation_id,second.reservation_id);
  const chats = result.notifications.filter(n => n.type === 'chat');
  assert.equal(chats.length,1,'일반 채팅만 방별 묶음 유지');
  assert.equal(chats[0].body,'새 채팅이 도착했어요. 일반 대화2 외 1건');
  assert.deepEqual((await feed(601,result.cursor)).notifications,[],'다음 cursor에는 재전달하지 않는다');
  const messages = await db.prepare("SELECT content FROM chat_messages WHERE sender_id = 0 AND room_id = 601 ORDER BY message_id").all();
  assert.ok(messages.results.some(m => m.content.includes('가게 사정')),'채팅방 안내 메시지는 보존');
  const ownerBaseline = await feed(602);
  const third = await reserve();
  const requests = await feed(602,ownerBaseline.cursor);
  assert.equal(requests.notifications.find(n => n.reservation_id === third.reservation_id)?.as_owner,true,'사장님 예약 요청 라우팅 문맥');
  await db.prepare("UPDATE reservations SET canceled_at = datetime('now','+1 second'), canceled_by = 'USER',status='CANCELED' WHERE reservation_id = ?").bind(third.reservation_id).run();
  const ownerCanceled = await feed(602,requests.cursor);
  assert.equal(ownerCanceled.notifications.find(n => n.type === 'reservation_canceled')?.as_owner,true,'고객 취소는 사장님 문맥');
  // MAX(message_id) 직후 도착하는 메시지도 다음 조회로 이월해야 한다.
  // route는 실제 Worker, SQL은 실제 D1을 사용하고 snapshot 사이의 쓰기 시점만 제어한다.
  const nodeBundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
    format: 'esm', platform: 'node', plugins: [{ name: 'unused-durable-object-base', setup(builder) {
      builder.onResolve({ filter: /^cloudflare:workers$/ }, () => ({ path: 'workers', namespace: 'local-stub' }));
      builder.onLoad({ filter: /.*/, namespace: 'local-stub' }, () => ({ contents: 'export class DurableObject {}' }));
    } }] });
  const { default: worker } = await import(`data:text/javascript;base64,${Buffer.from(nodeBundle.outputFiles[0].text).toString('base64')}`);
  let inserted = false;
  const snapshotDB = new Proxy(db, { get(target, key) {
    if (key !== 'prepare') return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
    return sql => {
      const statement = target.prepare(sql);
      if (!sql.includes('MAX(message_id)') || !sql.includes('FROM chat_messages')) return statement;
      return new Proxy(statement, { get(stmt, method) {
        if (method !== 'first') return typeof stmt[method] === 'function' ? stmt[method].bind(stmt) : stmt[method];
        return async (...args) => {
          const snapshot = await stmt.first(...args);
          if (!inserted) {
            inserted = true;
            await db.exec("INSERT INTO chat_messages(room_id,sender_id,content) VALUES(601,602,'snapshot 이후 일반 대화'); INSERT INTO chat_messages(room_id,sender_id,message_type,content,event_type,reservation_id) VALUES(601,0,'AUTO','snapshot 이후 예약 취소','reservation_canceled',999);");
          }
          return snapshot;
        };
      } });
    };
  } });
  const beforeRace = await feed(601);
  const snapshotResponse = await worker.fetch(new Request(`http://localhost/api/users/601/notifications?cursor=${encodeURIComponent(JSON.stringify(beforeRace.cursor))}`,
    { headers: { Authorization: 'Bearer context-token-601' } }), { DB: snapshotDB }, { waitUntil() {} });
  assert.equal(snapshotResponse.status,200);
  const snapshotFeed = await snapshotResponse.json();
  assert.equal(snapshotFeed.notifications.length,0,'snapshot 이후 일반·시스템 메시지는 현재 응답에 포함하지 않는다');
  const deferredFeed = await feed(601,snapshotFeed.cursor);
  assert.equal(deferredFeed.notifications.length,2,'snapshot 이후 메시지는 다음 조회에서 각각 복구한다');
  assert.ok(deferredFeed.notifications.some(n => n.type === 'reservation_canceled' && n.reservation_id === 999));
  assert.deepEqual((await feed(601,deferredFeed.cursor)).notifications,[]);
  console.log('PASS notification context: 취소·확정 개별 이벤트, 일반 채팅 묶음, cursor 재전달 없음, 채팅 안내 보존, 사장님 문맥');
} finally { await mf.dispose(); }
