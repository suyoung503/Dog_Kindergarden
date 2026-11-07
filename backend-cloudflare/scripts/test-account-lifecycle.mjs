#!/usr/bin/env node
// 실제 Hono Worker.fetch + 격리된 Miniflare D1/R2/DO를 사용하며 운영 자원은 사용하지 않는다.
// Node에서 cloudflare:workers 기반 클래스만 대체하고 실제 DO는 원본 workerd 번들로 실행한다.
// 경쟁 순서는 실제 SELECT를 끝낸 뒤 결과 전달만 지연한다. SQL·결과·권한은 바꾸지 않는다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { test } from 'node:test';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const backend = fileURLToPath(new URL('..', import.meta.url));
const temporary = await mkdtemp(`${tmpdir()}/account-lifecycle-`);
let mf;
try {
  const entry = { entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false, format: 'esm' };
  const workerBundle = await build({ ...entry, platform: 'neutral', external: ['cloudflare:*'] });
  const nodeBundle = await build({ ...entry, platform: 'node', plugins: [{ name: 'node-do-base', setup(b) {
    b.onResolve({ filter: /^cloudflare:workers$/ }, () => ({ path: 'workers', namespace: 'node-do-base' }));
    b.onLoad({ filter: /.*/, namespace: 'node-do-base' }, () => ({ contents: 'export class DurableObject {}' }));
  } }] });
  const nodeFile = `${temporary}/worker.mjs`;
  await writeFile(nodeFile, nodeBundle.outputFiles[0].text);
  const { default: worker } = await import(pathToFileURL(nodeFile).href);
  const options = { name: 'account-lifecycle-test', modules: true, script: workerBundle.outputFiles[0].text,
    compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
    durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
  mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
  const db = await mf.getD1Database('DB'), bucket = await mf.getR2Bucket('DIARY_PHOTOS');
  const env = { DB: db, DIARY_PHOTOS: bucket, USER_REALTIME: await mf.getDurableObjectNamespace('USER_REALTIME') };
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));

  const rows = async (sql, ...values) => (await db.prepare(sql).bind(...values).all()).results;
  const token = (id, device = 1) => `account-lifecycle-${id}-${device}`;
  const api = async (path, id, body, { database = db, photos = bucket, method = 'POST', device = 1 } = {}) => {
    const response = await worker.fetch(new Request(`http://localhost/api${path}`, {
      method, headers: { Authorization: `Bearer ${token(id, device)}`, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), { ...env, DB: database, DIARY_PHOTOS: photos }, { waitUntil() {} });
    const raw = await response.text();
    let data; try { data = JSON.parse(raw); } catch { data = raw; }
    return { status: response.status, data };
  };
  const removeAccount = (id, options) => api(`/users/${id}/account`, id, undefined, { ...options, method: 'DELETE' });
  const reserve = (fixture, options) => api('/reservations', fixture.customer, {
    pet_id: fixture.customer, store_id: fixture.store, start_date: '2099-01-01', end_date: '2099-01-02',
    request_message: '새 예약의 개인정보',
  }, options);
  const photoKeys = [];
  let nextId = 9300;
  async function fixture() {
    nextId += 10;
    const store = nextId, customer = nextId + 1, owner = nextId + 2;
    for (const id of [customer, owner]) {
      await db.prepare(`INSERT INTO users(user_id,kakao_id,nickname,email,phone,address,is_owner,is_admin)
        VALUES(?,?,?,?,?,?,?,0)`).bind(id, `account-kakao-${id}`, `사용자${id}`, `user${id}@example.com`,
        '01012345678', `서울시 ${id}번지`, id === owner ? 1 : 0).run();
      for (const device of [1, 2]) await db.prepare(`INSERT INTO auth_sessions(token_hash,user_id,expires_at)
        VALUES(?,?,datetime('now','+1 day'))`).bind(createHash('sha256').update(token(id, device)).digest('hex'), id).run();
      await db.prepare(`INSERT INTO pets(pet_id,user_id,name,breed,note,image_url) VALUES(?,?,?,?,?,?)`)
        .bind(id, id, `강아지${id}`, '말티푸', '보호자 개인 메모', `/api/pets/${id}/photo`).run();
    }
    await db.prepare(`INSERT INTO stores(store_id,store_key,name,owner_id,partner_status)
      VALUES(?,?,?,?,'ACTIVE')`).bind(store, `account-store-${store}`, `가게${store}`, owner).run();
    for (const id of [customer, owner]) {
      await db.prepare(`INSERT INTO reservations(reservation_id,user_id,pet_id,store_id,start_date,end_date,reservation_type,status,request_message,booking_snapshot)
        VALUES(?,?,?,?,'2000-01-01','2000-01-02','NORMAL','CANCELED',?,?)`)
        .bind(id, id, id, store, '과거 예약의 개인정보', JSON.stringify({ user_name: `사용자${id}`, user_phone: '01012345678', pet_name: `강아지${id}` })).run();
      await db.prepare(`INSERT INTO chat_rooms(room_id,user_id,store_id) VALUES(?,?,?)`).bind(id, id, store).run();
      await db.prepare(`INSERT INTO chat_messages(message_id,room_id,sender_id,sender_name,message_type,content)
        VALUES(?,?,?,?,'TEXT',?)`).bind(id, id, id, `사용자${id}`, '보호자의 개인 채팅').run();
      await db.prepare(`INSERT INTO chat_room_reads(room_id,user_id,last_read_message_id) VALUES(?,?,?)`).bind(id, id, id).run();
      await db.prepare(`INSERT INTO diaries(diary_id,reservation_id,store_id,content,media_type)
        VALUES(?,?,?,?,'IMAGE')`).bind(id, id, store, '과거 알림장의 개인정보').run();
      const diaryKey = `account-lifecycle/${id}/diary.jpg`, petKey = `account-lifecycle/${id}/pet.jpg`;
      await db.prepare(`INSERT INTO diary_photos(photo_id,diary_id,r2_key) VALUES(?,?,?)`).bind(id, id, diaryKey).run();
      await db.prepare(`INSERT INTO pet_photos(pet_id,r2_key) VALUES(?,?)`).bind(id, petKey).run();
      await db.prepare(`INSERT INTO favorites(user_id,store_id) VALUES(?,?)`).bind(id, store).run();
      await db.prepare(`INSERT INTO pet_reviews(id,store_key,user_id,user_name,rating,content,reservation_id)
        VALUES(?,?,?,?,5,?,?)`).bind(id, `account-store-${store}`, id, `사용자${id}`, '후기의 개인정보', id).run();
      for (const key of [diaryKey, petKey]) { await bucket.put(key, `private fixture ${key}`); photoKeys.push(key); }
    }
    return { customer, owner, store };
  }

  const preservedTables = ['users', 'pets', 'reservations', 'stores', 'chat_rooms', 'chat_messages', 'chat_room_reads',
    'diaries', 'diary_photos', 'pet_photos', 'favorites', 'pet_reviews', 'auth_sessions', 'diary_photo_deletion_queue'];
  async function snapshot() {
    const tables = {};
    for (const table of preservedTables) tables[table] = await rows(`SELECT * FROM ${table} ORDER BY rowid`);
    const photos = {};
    for (const key of photoKeys) { const object = await bucket.get(key); photos[key] = object ? await object.text() : null; }
    return { tables, photos };
  }
  async function assertDeleted(id) {
    const [user] = await rows('SELECT * FROM users WHERE user_id=?', id);
    assert.ok(user.deleted_at);
    assert.match(user.kakao_id, new RegExp(`^deleted:${id}:`));
    assert.equal(user.nickname, '탈퇴한 사용자');
    for (const field of ['email', 'phone', 'address']) assert.equal(user[field], null, `${field} 익명화`);
    assert.equal(user.is_owner, 0); assert.equal(user.is_admin, 0);
    for (const table of ['pets', 'favorites', 'auth_sessions', 'chat_rooms'])
      assert.equal((await rows(`SELECT * FROM ${table} WHERE user_id=?`, id)).length, 0, `${table} 삭제`);
    assert.equal((await rows('SELECT * FROM diaries WHERE reservation_id=?', id)).length, 0);
    assert.equal((await rows('SELECT * FROM diary_photos WHERE diary_id=?', id)).length, 0);
    assert.equal((await rows('SELECT * FROM pet_photos WHERE pet_id=?', id)).length, 0);
    assert.equal((await rows('SELECT * FROM chat_messages WHERE room_id=?', id)).length, 0);
    assert.equal((await rows('SELECT * FROM chat_room_reads WHERE room_id=? OR user_id=?', id, id)).length, 0);
    const [history] = await rows('SELECT status,request_message,booking_snapshot FROM reservations WHERE reservation_id=?', id);
    assert.deepEqual(history, { status: 'CANCELED', request_message: null, booking_snapshot: null });
    const [review] = await rows('SELECT user_id,user_name,content FROM pet_reviews WHERE id=?', id);
    assert.deepEqual(review, { user_id: null, user_name: '익명', content: '' });
    for (const kind of ['diary', 'pet']) {
      const key = `account-lifecycle/${id}/${kind}.jpg`;
      assert.equal(await bucket.get(key), null, '실제 R2 개인정보 사진 삭제');
      assert.equal((await rows('SELECT * FROM diary_photo_deletion_queue WHERE r2_key=?', key)).length, 0);
    }
    for (const device of [1, 2]) assert.equal((await api('/auth/me', id, undefined, { method: 'GET', device })).status, 401);
  }

  async function within(promise, message) {
    let timer;
    try { return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`SELECT gate timeout: ${message}`)), 8000);
    })]); } finally { clearTimeout(timer); }
  }
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
            await within(interceptor.beforeDeliver(result), sql.trim().split('\n')[0]);
            return result;
          };
          return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
        } });
        return wrap(statement);
      };
    } });
  }
  const customerCount = /SELECT COUNT\(\*\) AS count\s+FROM reservations\s+WHERE user_id/;
  const ownerCount = /SELECT COUNT\(\*\) AS count\s+FROM reservations r\s+JOIN stores/;
  const petRead = /SELECT 1 AS found FROM pets WHERE pet_id = \? AND user_id = \?/;
  const storeRead = /SELECT s.store_id, s.owner_id, s.partner_status,/;
  const authRead = /SELECT s.user_id, u.is_owner, u.is_admin\s+FROM auth_sessions s/;
  function onceAfter(pattern, action) {
    let arrived = 0;
    return { database: beforeDeliverSelect([{ pattern, beforeDeliver: async result => {
      if (arrived > 0) return;
      arrived += 1;
      await action(result);
    } }]), arrivals: () => arrived };
  }

  await test('계정 탈퇴와 진행 중 쓰기의 실제 API 수명주기', { timeout: 120000 }, async t => {
    for (const role of ['customer', 'owner']) await t.test(`${role}: count0 뒤 완료된 예약이 탈퇴와 모든 개인정보 삭제를 막는다`, { timeout: 20000 }, async t => {
      const f = await fixture();
      let baseline, counts = 0, customerRead = false, ownerRead = false;
      const database = beforeDeliverSelect([
        { pattern: customerCount, beforeDeliver: async result => {
          if (customerRead) return;
          customerRead = true; assert.equal(result.count, 0); counts += 1;
        } },
        { pattern: ownerCount, beforeDeliver: async result => {
          if (ownerRead) return;
          ownerRead = true; assert.equal(result.count, 0); counts += 1;
          assert.equal((await reserve(f)).status, 201, '실제 신규 예약을 먼저 완료한다');
          baseline = await snapshot();
        } },
      ]);
      const deletion = await removeAccount(f[role], { database });
      t.diagnostic(`counts=${counts} delete=${deletion.status}`);
      assert.equal(counts, 2, '두 실제 COUNT=0 전달 사이 이후의 경쟁이다');
      assert.equal(deletion.status, 409, '예약이 먼저 저장되면 탈퇴는 거절되어야 한다');
      assert.equal(deletion.data.code, 'ACTIVE_RESERVATIONS');
      assert.deepEqual(await snapshot(), baseline, '프로필·펫·예약 snapshot·채팅·사진·모든 세션을 보존한다');
      assert.equal((await api('/auth/me', f[role], undefined, { method: 'GET' })).status, 200);
    });

    for (const role of ['customer', 'owner']) await t.test(`${role}: 선탈퇴 뒤 지연된 예약은 예약과 유령 채팅방을 만들지 않는다`, { timeout: 20000 }, async t => {
      const f = await fixture();
      // owner도 늦은 요청이 새 방을 만들 수 있도록 고객의 최초 채팅방 상태로 시작한다.
      if (role === 'owner') await db.batch([
        db.prepare('DELETE FROM chat_room_reads WHERE room_id=?').bind(f.customer),
        db.prepare('DELETE FROM chat_messages WHERE room_id=?').bind(f.customer),
        db.prepare('DELETE FROM chat_rooms WHERE room_id=?').bind(f.customer),
      ]);
      const gate = onceAfter(role === 'customer' ? petRead : storeRead, async result => {
        if (role === 'customer') assert.equal(result.found, 1); else assert.equal(result.can_book, 1);
        assert.equal((await removeAccount(f[role])).status, 200);
      });
      const reservation = await reserve(f, { database: gate.database });
      const active = await rows("SELECT * FROM reservations WHERE store_id=? AND status IN ('REQUEST','CONFIRMED')", f.store);
      const rooms = await rows('SELECT * FROM chat_rooms WHERE user_id=? AND store_id=?', f.customer, f.store);
      t.diagnostic(`gate=${gate.arrivals()} booking=${reservation.status} active=${active.length} rooms=${rooms.length}`);
      assert.equal(gate.arrivals(), 1);
      assert.equal(reservation.status, 403);
      assert.equal(active.length, 0);
      assert.equal(rooms.length, 0, '선탈퇴 뒤 실패한 예약이 빈 채팅방을 생성하면 안 된다');
      await assertDeleted(f[role]);
    });

    for (const kind of ['profile', 'pet']) await t.test(`인증 뒤 선탈퇴하면 지연된 ${kind} 쓰기로 개인정보를 복원하지 않는다`, { timeout: 20000 }, async t => {
      const f = await fixture();
      const gate = onceAfter(authRead, async result => {
        assert.equal(result.user_id, f.customer);
        assert.equal((await removeAccount(f.customer)).status, 200);
      });
      const response = kind === 'profile'
        ? await api(`/users/${f.customer}`, f.customer, { nickname: '복원 금지', email: 'after-delete@example.com', phone: '01099998888', address: '복원 금지 주소' }, { database: gate.database, method: 'PUT' })
        : await api(`/users/${f.customer}/pets`, f.customer, { name: '복원 금지 반려견', note: '복원 금지 개인정보' }, { database: gate.database });
      t.diagnostic(`gate=${gate.arrivals()} write=${response.status}`);
      assert.equal(gate.arrivals(), 1);
      assert.ok([403, 404].includes(response.status), '인증을 이미 읽었더라도 탈퇴 이후 쓰기를 거절한다');
      await assertDeleted(f.customer);
    });

    await t.test('채팅방 조회까지 성공해도 쓰기 전 사장님 탈퇴가 끝나면 예약·자동 안내를 만들지 않는다', { timeout: 20000 }, async t => {
      const f = await fixture();
      const gate = onceAfter(/SELECT room_id FROM chat_rooms WHERE user_id = \? AND store_id = \?/, async result => {
        assert.equal(result.room_id, f.customer);
        assert.equal((await removeAccount(f.owner)).status, 200);
      });
      const response = await reserve(f, { database: gate.database });
      const active = await rows("SELECT * FROM reservations WHERE store_id=? AND status IN ('REQUEST','CONFIRMED')", f.store);
      const notices = await rows("SELECT * FROM chat_messages WHERE room_id=? AND event_type='reservation_submitted'", f.customer);
      t.diagnostic(`roomGate=${gate.arrivals()} booking=${response.status} active=${active.length} notices=${notices.length}`);
      assert.equal(gate.arrivals(), 1);
      assert.equal(response.status, 403);
      assert.equal(active.length, 0);
      assert.equal(notices.length, 0);
      await assertDeleted(f.owner);
    });

    await t.test('정상 활성 예약은 보호자·사장님 탈퇴를 409로 막고 기존 데이터를 보존한다', { timeout: 20000 }, async () => {
      const f = await fixture();
      assert.equal((await reserve(f)).status, 201);
      const baseline = await snapshot();
      for (const id of [f.customer, f.owner]) {
        const deletion = await removeAccount(id);
        assert.equal(deletion.status, 409);
        assert.equal(deletion.data.code, 'ACTIVE_RESERVATIONS');
      }
      assert.deepEqual(await snapshot(), baseline);
    });

    for (const role of ['customer', 'owner']) await t.test(`${role}: 정상 탈퇴는 이력만 익명화하고 사진·모든 세션을 삭제한다`, { timeout: 20000 }, async () => {
      const f = await fixture();
      const deletion = await removeAccount(f[role]);
      assert.equal(deletion.status, 200);
      assert.equal(deletion.data.ok, true);
      await assertDeleted(f[role]);
      if (role === 'owner') assert.deepEqual((await rows('SELECT owner_id,partner_status FROM stores WHERE store_id=?', f.store))[0],
        { owner_id: null, partner_status: 'TERMINATED' });
      assert.equal((await api('/auth/me', f[role === 'customer' ? 'owner' : 'customer'], undefined, { method: 'GET' })).status, 200,
        '다른 계정의 세션은 보존한다');
    });

    await t.test('R2 삭제 실패에도 탈퇴·사진 접근 차단을 유지하고 후속 정리가 파일과 대기 기록을 지운다', { timeout: 20000 }, async () => {
      const f = await fixture();
      const photos = new Proxy(bucket, { get(target, key) {
        if (key === 'delete') return async () => { throw Error('fixture R2 unavailable'); };
        return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
      } });
      assert.equal((await removeAccount(f.customer, { photos })).status, 200);
      assert.equal((await api('/auth/me', f.customer, undefined, { method: 'GET' })).status, 401);
      for (const path of [`/pets/${f.customer}/photo`, `/diary-photos/${f.customer}`])
        assert.equal((await api(path, f.owner, undefined, { method: 'GET' })).status, 404, '살아 있는 다른 계정으로도 삭제된 조회 연결은 열 수 없다');
      for (const kind of ['diary', 'pet']) {
        const key = `account-lifecycle/${f.customer}/${kind}.jpg`;
        assert.ok(await bucket.get(key), '저장소 장애 중 실제 파일은 아직 남아 있다');
        assert.equal((await rows('SELECT * FROM diary_photo_deletion_queue WHERE r2_key=?', key)).length, 1);
      }
      await worker.scheduled({ cron: '*/15 * * * *' }, env, { waitUntil() {} });
      await assertDeleted(f.customer);
    });

    await t.test('cleanup 중 실제 D1 오류가 나면 tombstone부터 사진 대기열까지 batch 전체를 rollback한다', { timeout: 20000 }, async () => {
      const f = await fixture(), trigger = `fail_account_delete_${f.customer}`;
      await db.prepare(`CREATE TRIGGER ${trigger} BEFORE DELETE ON pets WHEN OLD.user_id=${f.customer}
        BEGIN SELECT RAISE(ABORT,'fixture account cleanup failure'); END`).run();
      try {
        const baseline = await snapshot();
        assert.equal((await removeAccount(f.customer)).status, 500);
        assert.deepEqual(await snapshot(), baseline, '실패 전 개인정보 삭제·tombstone·대기열·R2는 모두 원상태다');
        assert.equal((await api('/auth/me', f.customer, undefined, { method: 'GET' })).status, 200);
      } finally { await db.prepare(`DROP TRIGGER ${trigger}`).run(); }
    });

    await t.test('동시 탈퇴 둘은 한 요청만 성공하고 실제 사진 객체를 한 번씩 정리한다', { timeout: 20000 }, async t => {
      const f = await fixture();
      let arrived = 0, release;
      const bothCountsRead = new Promise(resolve => { release = resolve; });
      const database = beforeDeliverSelect([{ pattern: ownerCount, beforeDeliver: async result => {
        if (arrived >= 2) return;
        assert.equal(result.count, 0);
        arrived += 1;
        if (arrived === 2) release();
        await bothCountsRead;
      } }]);
      const deletedKeys = [];
      const photos = new Proxy(bucket, { get(target, key) {
        if (key === 'delete') return async keys => {
          deletedKeys.push(...(Array.isArray(keys) ? keys : [keys]));
          return target.delete(keys);
        };
        return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
      } });
      const responses = await Promise.all([removeAccount(f.customer, { database, photos }), removeAccount(f.customer, { database, photos })]);
      t.diagnostic(`counts=${arrived} statuses=${responses.map(r => r.status)}`);
      assert.equal(arrived, 2);
      assert.deepEqual(responses.map(r => r.status).sort(), [200, 404]);
      for (const kind of ['diary', 'pet']) {
        const key = `account-lifecycle/${f.customer}/${kind}.jpg`;
        assert.equal(deletedKeys.filter(deleted => deleted === key).length, 1, '성공한 탈퇴만 cleanup을 실행한다');
        assert.equal(await bucket.get(key), null);
      }
      await assertDeleted(f.customer);
    });
  });
} finally {
  try { if (mf) await mf.dispose(); } finally { await rm(temporary, { recursive: true, force: true }); }
}
