#!/usr/bin/env node
// 실제 Hono Worker.fetch와 격리된 Miniflare D1/R2/DO를 사용한다. 운영 자원은 사용하지 않는다.
// Node 번들에서 cloudflare:workers의 DurableObject 기반 클래스만 대체한다.
// 실제 DO는 원본 workerd 번들에서 실행한다. 라우트·인증·SQL·D1 batch는 대체하지 않는다.
// D1 proxy는 SELECT를 실제 실행한 후 첫 10개 결과 전달만 모아 지연한다.
// DB 응답 지연으로 가능한 read-before-insert 순서를 결정적으로 만들며 결과값은 바꾸지 않는다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { test } from 'node:test';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const backend = fileURLToPath(new URL('..', import.meta.url));
const temporary = await mkdtemp(`${tmpdir()}/store-identity-concurrency-`);
const entry = { entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false, format: 'esm' };
const workerBundle = await build({ ...entry, platform: 'neutral', external: ['cloudflare:*'] });
const nodeBundle = await build({ ...entry, platform: 'node', plugins: [{ name: 'node-do-base', setup(b) {
  b.onResolve({ filter: /^cloudflare:workers$/ }, () => ({ path: 'workers', namespace: 'node-do-base' }));
  b.onLoad({ filter: /.*/, namespace: 'node-do-base' }, () => ({ contents: 'export class DurableObject {}' }));
} }] });
const nodeFile = `${temporary}/worker.mjs`;
await writeFile(nodeFile, nodeBundle.outputFiles[0].text);
const { default: worker } = await import(pathToFileURL(nodeFile).href);
const options = { name: 'store-identity-concurrency-test', modules: true, script: workerBundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);

try {
  const db = await mf.getD1Database('DB');
  const env = { DB: db, DIARY_PHOTOS: await mf.getR2Bucket('DIARY_PHOTOS'),
    USER_REALTIME: await mf.getDurableObjectNamespace('USER_REALTIME') };
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner,is_admin) VALUES
    (8101,'identity-customer','손님',0,0),(8102,'identity-owner','사장님',1,0),
    (8103,'identity-other-owner','다른 사장님',1,0),(8104,'identity-admin','관리자',0,1);
    INSERT INTO stores(store_id,store_key,name,owner_id,partner_status) VALUES
    (8101,'identity-chat','채팅 가게',8102,'ACTIVE'),(8102,'identity-book','예약 가게',8102,'ACTIVE'),
    (8103,'identity-pending','신청 가게',NULL,'NONE');
    INSERT INTO pets(pet_id,user_id,name) VALUES(8101,8101,'강아지');`.replace(/\n/g, ' '));
  for (const id of [8101, 8102, 8103, 8104]) await db.prepare(
    "INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))",
  ).bind(createHash('sha256').update(`identity-token-${id}`).digest('hex'), id).run();

  function beforeDeliverSelect(interceptors) {
    return new Proxy(db, { get(target, key) {
      if (key !== 'prepare') return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
      return sql => {
        const statement = target.prepare(sql), interceptor = interceptors.find(item => item.pattern.test(sql));
        if (!interceptor) return statement;
        const wrap = prepared => new Proxy(prepared, { get(target, key) {
          if (key === 'bind') return (...values) => wrap(target.bind(...values));
          if (key === 'first') return async (...args) => {
            const result = await target.first(...args);
            await interceptor.beforeDeliver(result);
            return result;
          };
          return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
        } });
        return wrap(statement);
      };
    } });
  }
  function delaySelects(patterns) {
    return beforeDeliverSelect(patterns.map(pattern => {
      let arrived = 0, release;
      const gate = new Promise(resolve => { release = resolve; });
      return { pattern, beforeDeliver: async () => {
        arrived += 1;
        if (arrived === 10) release();
        await gate;
      } };
    }));
  }
  const api = async (path, userId, body, database, method = 'POST') => {
    const response = await worker.fetch(new Request(`http://localhost/api${path}`, {
      method, headers: { Authorization: `Bearer identity-token-${userId}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }), { ...env, DB: database }, { waitUntil() {} });
    const raw = await response.text();
    let data; try { data = JSON.parse(raw); } catch { data = raw; }
    return { status: response.status, data };
  };
  const ten = action => Promise.all(Array.from({ length: 10 }, (_, i) => action(i)));
  const storeSelect = /SELECT store_id FROM stores WHERE store_key = \?/;
  const pendingSelect = /SELECT application_id, status\s+FROM store_owner_applications/;
  const roomSelect = /SELECT room_id FROM chat_rooms WHERE user_id = \? AND store_id = \?/;

  await test('실제 HTTP 경로의 가게·신청·채팅방 identity 동시성', async t => {
    await t.test('신규 같은 가게 claim 10건은 가게 하나와 신청 하나를 공유한다', async t => {
      const database = delaySelects([storeSelect, pendingSelect]);
      const responses = await ten(() => api('/stores/claim', 8102,
        { store_key: 'identity-new', store_name: '새 가게' }, database));
      const stores = (await db.prepare("SELECT store_id FROM stores WHERE store_key='identity-new'").all()).results;
      const pending = (await db.prepare(`SELECT a.application_id FROM store_owner_applications a
        JOIN stores s ON s.store_id=a.store_id WHERE s.store_key='identity-new' AND a.status='PENDING'`).all()).results;
      t.diagnostic(`statuses=${responses.map(r => r.status)} stores=${stores.length} pending=${pending.length}`);
      assert.equal(stores.length, 1, '동일 store_key가 서로 다른 stores 행으로 분기되면 안 된다');
      assert.equal(pending.length, 1, '동일 가게 신청은 하나만 생성한다');
      assert.ok(responses.every(r => [200, 201].includes(r.status)), '동시 재요청도 기존 신청을 반환한다');
      assert.ok(responses.every(r => r.data.store_id === stores[0].store_id && r.data.application_id === pending[0].application_id));
    });

    await t.test('기존 가게 최초 claim 10건도 UNIQUE 오류 대신 같은 신청을 반환한다', async t => {
      const database = delaySelects([pendingSelect]);
      const responses = await ten(() => api('/stores/claim', 8102,
        { store_key: 'identity-pending', store_name: '신청 가게' }, database));
      const pending = (await db.prepare("SELECT application_id FROM store_owner_applications WHERE store_id=8103 AND status='PENDING'").all()).results;
      t.diagnostic(`statuses=${responses.map(r => r.status)} pending=${pending.length}`);
      assert.equal(pending.length, 1);
      assert.ok(responses.every(r => [200, 201].includes(r.status)), 'UNIQUE 경합은 정상적인 기존 신청 조회로 복구한다');
      assert.ok(responses.every(r => r.data.application_id === pending[0].application_id && r.data.store_id === 8103));
    });

    await t.test('본인 신청 조회가 늦어도 같은 사용자의 먼저 완료된 신청을 다른 신청으로 거절하지 않는다', async t => {
      await db.exec("INSERT INTO stores(store_id,store_key,name) VALUES(8510,'identity-own-pending-race','동일 신청 경합 가게')");
      let winner;
      const body = { store_key: 'identity-own-pending-race' };
      const database = beforeDeliverSelect([{ pattern: pendingSelect, beforeDeliver: async result => {
        if (winner) return;
        assert.equal(result, null);
        // 첫 요청의 실제 null 전달만 보류하고 같은 사용자 두 번째 claim을 실제 API로 완료한다.
        winner = await api('/stores/claim', 8102, body, db);
        assert.equal(winner.status, 201);
      } }]);
      const delayed = await api('/stores/claim', 8102, body, database);
      const pending = (await db.prepare("SELECT application_id FROM store_owner_applications WHERE store_id=8510 AND status='PENDING'").all()).results;
      t.diagnostic(`winner=${winner.status} delayed=${delayed.status} pending=${pending.length}`);
      assert.equal(pending.length, 1);
      assert.ok([200, 201].includes(delayed.status), '같은 사용자 경쟁 승자의 신청을 다른 사장님 신청으로 오인하지 않는다');
      assert.equal(delayed.data.application_id, winner.data.application_id);
      assert.equal(delayed.data.application_id, pending[0].application_id);
    });

    await t.test('소유권 조회 응답이 늦어도 먼저 승인된 가게에 다른 사장님 신청을 만들지 않는다', async t => {
      await db.exec(`INSERT INTO stores(store_id,store_key,name,partner_status)
        VALUES(8500,'identity-approval-race','승인 경합 가게','PENDING');
        INSERT INTO store_owner_applications(application_id,user_id,store_id) VALUES(8500,8102,8500);`.replace(/\n/g, ' '));
      let approved = false;
      const database = beforeDeliverSelect([{ pattern: /SELECT owner_id FROM stores WHERE store_id = \?/, beforeDeliver: async () => {
        if (approved) return;
        // null을 조작하지 않는다. 실제 SELECT 결과 전달만 보류하고 실제 승인 API를 끝낸다.
        const approval = await api('/owner-applications/8500/approve', 8104, undefined, db, 'PATCH');
        assert.equal(approval.status, 200);
        approved = true;
      } }]);
      const response = await api('/stores/claim', 8103, { store_key: 'identity-approval-race' }, database);
      const store = await db.prepare('SELECT owner_id,partner_status FROM stores WHERE store_id=8500').first();
      const pending = (await db.prepare("SELECT application_id FROM store_owner_applications WHERE store_id=8500 AND status='PENDING'").all()).results;
      t.diagnostic(`claim=${response.status} owner=${store.owner_id} partner=${store.partner_status} pending=${pending.length}`);
      assert.deepEqual(store, { owner_id: 8102, partner_status: 'ACTIVE' });
      assert.equal(pending.length, 0, '실제 승인 완료 후에는 지연된 다른 소유자 claim을 INSERT하지 않는다');
      assert.equal(response.status, 409);
    });

    await t.test('첫 채팅방 생성 10건은 모두 같은 방을 반환하고 기존 메시지를 보존한다', async t => {
      const before = await db.prepare('SELECT message_id,content FROM chat_messages WHERE room_id=1 ORDER BY message_id').all();
      const database = delaySelects([roomSelect]);
      const responses = await ten(() => api('/chatrooms', 8101, { store_id: 8101 }, database));
      const rooms = (await db.prepare('SELECT room_id FROM chat_rooms WHERE user_id=8101 AND store_id=8101').all()).results;
      t.diagnostic(`statuses=${responses.map(r => r.status)} rooms=${rooms.length}`);
      assert.deepEqual((await db.prepare('SELECT message_id,content FROM chat_messages WHERE room_id=1 ORDER BY message_id').all()).results, before.results);
      assert.equal(rooms.length, 1);
      assert.ok(responses.every(r => r.status === 201), '경쟁 생성 요청도 UNIQUE 500 없이 성공한다');
      assert.ok(responses.every(r => r.data.room_id === rooms[0].room_id));
    });

    await t.test('서로 다른 첫 예약 10건은 채팅방 경합 때문에 저장에 실패하지 않는다', async t => {
      const database = delaySelects([roomSelect]);
      // 각각 다른 요청이며 예약 자체의 재시도 멱등성을 새로 요구하지 않는다.
      const responses = await ten(i => api('/reservations', 8101, { pet_id: 8101, store_id: 8102,
        start_date: '2099-01-01', end_date: '2099-01-02', request_message: `distinct-request-${i}` }, database));
      const bookings = (await db.prepare('SELECT reservation_id,request_message FROM reservations WHERE store_id=8102').all()).results;
      const messages = (await db.prepare(`SELECT m.reservation_id FROM chat_messages m JOIN reservations r ON r.reservation_id=m.reservation_id
        WHERE r.store_id=8102 AND m.event_type='reservation_submitted'`).all()).results;
      t.diagnostic(`statuses=${responses.map(r => r.status)} bookings=${bookings.length} messages=${messages.length}`);
      assert.equal(bookings.length, 10, '방 생성 UNIQUE 충돌로 유효한 예약 요청을 잃지 않는다');
      assert.equal(new Set(bookings.map(r => r.request_message)).size, 10);
      assert.equal(messages.length, 10);
      assert.ok(responses.every(r => r.status === 201));
      assert.equal(new Set(responses.map(r => r.data.room_id)).size, 1);
    });
  });
} finally {
  await mf.dispose();
  await rm(temporary, { recursive: true, force: true });
}
