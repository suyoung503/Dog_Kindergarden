#!/usr/bin/env node
// 실제 Hono Worker.fetch와 격리된 Miniflare D1/R2/DO를 사용한다. 운영 자원은 사용하지 않는다.
// Node 번들에서 cloudflare:workers의 DurableObject 기반 클래스만 대체한다.
// 실제 DO는 원본 workerd 번들에서 실행한다. 라우트·인증·SQL·D1 결과값은 대체하지 않는다.
// D1 proxy는 실제 자격 SELECT를 실행한 뒤 결과 전달만 지연하여 경합 순서를 고정한다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { test } from 'node:test';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const backend = fileURLToPath(new URL('..', import.meta.url));
const temporary = await mkdtemp(`${tmpdir()}/review-integrity-`);
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
  const options = { name: 'review-integrity-test', modules: true, script: workerBundle.outputFiles[0].text,
    compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
    durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
  mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
  const db = await mf.getD1Database('DB');
  const env = { DB: db, DIARY_PHOTOS: await mf.getR2Bucket('DIARY_PHOTOS'),
    USER_REALTIME: await mf.getDurableObjectNamespace('USER_REALTIME') };
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner,is_admin) VALUES
    (8901,'review-customer','리뷰 보호자',0,0),(8902,'review-owner','리뷰 점주',1,0),
    (8903,'review-other-customer','다른 보호자',0,0);
    INSERT INTO pets(pet_id,user_id,name) VALUES(8901,8901,'초코');`.replace(/\n/g, ' '));
  for (const id of [8901, 8902, 8903]) await db.prepare(
    "INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))",
  ).bind(createHash('sha256').update(`review-token-${id}`).digest('hex'), id).run();

  async function within(promise, description) {
    let timer;
    try {
      return await Promise.race([promise, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${description}: 30초 대기 시간 초과`)), 30_000);
      })]);
    } finally { clearTimeout(timer); }
  }
  const availableSelect = /SELECT r\.reservation_id\s+FROM reservations r\s+JOIN stores s ON s\.store_id = r\.store_id\s+LEFT JOIN pet_reviews pr ON pr\.reservation_id = r\.reservation_id/;
  function beforeDeliverSelect(beforeDeliver) {
    return new Proxy(db, { get(target, key) {
      if (key !== 'prepare') return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
      return sql => {
        const statement = target.prepare(sql);
        if (!availableSelect.test(sql)) return statement;
        const wrap = prepared => new Proxy(prepared, { get(target, key) {
          if (key === 'bind') return (...values) => wrap(target.bind(...values));
          if (key === 'first') return async (...args) => {
            const result = await target.first(...args);
            await beforeDeliver(result);
            return result;
          };
          return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
        } });
        return wrap(statement);
      };
    } });
  }
  const api = async (path, userId, body, database = db, method = 'POST') => {
    const response = await worker.fetch(new Request(`http://localhost/api${path}`, {
      method, headers: { ...(userId ? { Authorization: `Bearer review-token-${userId}` } : {}), 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    }), { ...env, DB: database }, { waitUntil() {} });
    const raw = await response.text();
    let data; try { data = JSON.parse(raw); } catch { data = raw; }
    return { status: response.status, data };
  };
  async function fixture(id, status = 'CONFIRMED', endDate = '2000-01-02') {
    const storeKey = `review-integrity-${id}`;
    await db.prepare(`INSERT INTO stores(store_id,store_key,name,owner_id,partner_status)
      VALUES(?,?,'리뷰 경합 가게',8902,'ACTIVE')`).bind(id, storeKey).run();
    await db.prepare(`INSERT INTO reservations(reservation_id,user_id,pet_id,store_id,start_date,end_date,reservation_type,status)
      VALUES(?,8901,8901,?,'2000-01-01',?,'돌봄',?)`).bind(id, id, endDate, status).run();
    return { reservationId: id, storeId: id, storeKey, body: {
      user_id: 8901, store_key: storeKey, store_name: '리뷰 경합 가게', user_name: '위조 표시명',
      rating: 4.5, revisit: true, cctv: true, pickup: true, large_dog: true, separation_care: true, content: '이용 후기',
    } };
  }
  const countReviews = id => db.prepare('SELECT COUNT(*) AS count FROM pet_reviews WHERE reservation_id=?')
    .bind(id).first().then(row => row.count);

  await test('인증 리뷰의 자격·중복·저장 시점 무결성', { timeout: 60_000 }, async t => {
    await t.test('다른 사용자는 완료 예약 소유자를 사칭해 리뷰를 작성할 수 없다', async () => {
      const f = await fixture(8951);
      assert.equal((await api('/pet-reviews', 8903, f.body)).status, 403);
      assert.equal(await countReviews(f.reservationId), 0);
    });

    for (const [id, status, endDate] of [[8952, 'REQUEST', '2000-01-02'], [8953, 'CONFIRMED', '2099-01-02']]) {
      await t.test(`${status}/${endDate} 미완료 예약은 인증 리뷰를 작성할 수 없다`, async () => {
        const f = await fixture(id, status, endDate);
        const response = await api('/pet-reviews', 8901, f.body);
        assert.equal(response.status, 403);
        assert.equal(response.data.reason, 'no_completed_reservation');
        assert.equal(await countReviews(f.reservationId), 0);
      });
    }

    await t.test('완료 리뷰는 계정 표시명으로 저장되고 공개 목록과 태그 집계에 포함된다', async () => {
      const f = await fixture(8954);
      const created = await api('/pet-reviews', 8901, f.body);
      assert.equal(created.status, 201);
      assert.equal(created.data.verified, true);
      assert.ok(Number.isInteger(created.data.id) && created.data.id > 0);
      const saved = await db.prepare('SELECT user_id,reservation_id,user_name FROM pet_reviews WHERE id=?').bind(created.data.id).first();
      assert.deepEqual(saved, { user_id: 8901, reservation_id: f.reservationId, user_name: '리뷰 보호자' });
      const listing = await api(`/pet-reviews?storeKey=${encodeURIComponent(f.storeKey)}`, undefined, undefined, db, 'GET');
      assert.equal(listing.status, 200);
      assert.equal(listing.data.reviews.length, 1);
      assert.equal(listing.data.reviews[0].id, created.data.id);
      assert.equal(listing.data.reviews[0].user_name, '리뷰 보호자');
      assert.equal(listing.data.reviews[0].verified, 1);
      assert.equal(listing.data.reviews[0].content, '이용 후기');
      assert.deepEqual(listing.data.summary, { count: 1, avg_rating: 4.5, cctv: 1, pickup: 1, large_dog: 1, separation_care: 1 });
      const tags = await api('/pet-reviews/tags', undefined, undefined, db, 'GET');
      assert.equal(tags.status, 200);
      assert.deepEqual(tags.data.find(row => row.store_key === f.storeKey), {
        store_key: f.storeKey, count: 1, avg_rating: 4.5, cctv: 1, pickup: 1, large_dog: 1, separation_care: 1,
      });
      const duplicate = await api('/pet-reviews', 8901, f.body);
      assert.equal(duplicate.status, 409);
      assert.equal(duplicate.data.reason, 'already_reviewed');
      assert.equal(await countReviews(f.reservationId), 1);
    });

    await t.test('하나의 완료 예약에 동시 리뷰 10건은 한 건만 저장하고 나머지는 409로 거절한다', async t => {
      const f = await fixture(8955);
      let arrived = 0, release;
      const gate = new Promise(resolve => { release = resolve; });
      const database = beforeDeliverSelect(async result => {
        if (arrived === 10) return;
        assert.deepEqual(result, { reservation_id: f.reservationId });
        arrived += 1;
        if (arrived === 10) release();
        await gate;
      });
      let responses;
      try {
        responses = await within(Promise.all(Array.from({ length: 10 }, (_, i) =>
          api('/pet-reviews', 8901, { ...f.body, content: `동시 후기-${i}` }, database))), '리뷰 자격 SELECT 10건 gate');
      } finally { release(); }
      const statuses = responses.map(response => response.status).sort((a, b) => a - b);
      const count = await countReviews(f.reservationId);
      t.diagnostic(`statuses=${statuses} reviews=${count} delayedSelects=${arrived}`);
      assert.equal(arrived, 10, '자격 SELECT selector가 바뀌면 경합을 검증하지 않은 채 통과하면 안 된다');
      assert.equal(count, 1);
      assert.deepEqual(statuses, [201, 409, 409, 409, 409, 409, 409, 409, 409, 409]);
      assert.ok(responses.filter(response => response.status === 409).every(response => response.data.reason === 'already_reviewed'));
    });

    await t.test('자격 조회 후 실제 취소 API가 완료되면 리뷰를 저장하지 않는다', async t => {
      const f = await fixture(8956);
      let delayed = 0;
      const database = beforeDeliverSelect(async result => {
        if (delayed) return;
        assert.deepEqual(result, { reservation_id: f.reservationId });
        delayed += 1;
        assert.equal((await api(`/reservations/${f.reservationId}/cancel`, 8901, undefined, db, 'PATCH')).status, 200);
        assert.deepEqual(await db.prepare('SELECT status,canceled_by FROM reservations WHERE reservation_id=?').bind(f.reservationId).first(),
          { status: 'CANCELED', canceled_by: 'USER' });
      });
      const response = await within(api('/pet-reviews', 8901, f.body, database), '자격 SELECT 뒤 실제 취소 gate');
      const count = await countReviews(f.reservationId);
      t.diagnostic(`review=${response.status} reviews=${count} delayedSelects=${delayed}`);
      assert.equal(delayed, 1, '실제 eligible SELECT 결과 전달을 보류한 뒤 취소해야 한다');
      assert.equal(response.status, 403);
      assert.equal(response.data.reason, 'no_completed_reservation');
      assert.equal(count, 0);
    });

    await t.test('자격 조회 후 실제 가게 등록 해제가 완료되면 리뷰를 저장하지 않는다', async t => {
      const f = await fixture(8957);
      let delayed = 0;
      const database = beforeDeliverSelect(async result => {
        if (delayed) return;
        assert.deepEqual(result, { reservation_id: f.reservationId });
        delayed += 1;
        assert.equal((await api(`/owners/8902/stores/${f.storeId}`, 8902, undefined, db, 'DELETE')).status, 200);
        assert.deepEqual(await db.prepare('SELECT owner_id,partner_status FROM stores WHERE store_id=?').bind(f.storeId).first(),
          { owner_id: null, partner_status: 'TERMINATED' });
      });
      const response = await within(api('/pet-reviews', 8901, f.body, database), '자격 SELECT 뒤 실제 가게 해제 gate');
      const count = await countReviews(f.reservationId);
      t.diagnostic(`review=${response.status} reviews=${count} delayedSelects=${delayed}`);
      assert.equal(delayed, 1, '실제 eligible SELECT 결과 전달을 보류한 뒤 가게를 해제해야 한다');
      assert.equal(response.status, 403);
      assert.equal(response.data.reason, 'partner_required');
      assert.equal(count, 0);
    });
  });
} finally {
  try { await mf?.dispose(); }
  finally { await rm(temporary, { recursive: true, force: true }); }
}
