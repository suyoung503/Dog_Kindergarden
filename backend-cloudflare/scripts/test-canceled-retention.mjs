#!/usr/bin/env node
// 격리된 Miniflare/D1/R2만 사용한다. 운영 데이터에 접근하지 않는다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'canceled-retention-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'retention local test', INTERNAL_API_KEY: 'local-retention-key' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort()) {
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  }
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname) VALUES(901,'retention-fixture','보호자');
    INSERT INTO stores(store_id,name,store_key) VALUES(901,'정리 테스트','retention-store');
    INSERT INTO pets(pet_id,user_id,name) VALUES(901,901,'상민이');`);
  const cases = [
    [901, 'CANCELED', "datetime('now','-8 days')", "datetime('now','-30 days')", 'USER', false],
    [902, 'CANCELED', "datetime('now','-6 days')", "datetime('now','-30 days')", 'OWNER', true],
    [903, 'CANCELED', "datetime('now','-7 days')", "datetime('now','-30 days')", 'OWNER', false],
    [904, 'REQUEST', 'NULL', "datetime('now','-30 days')", 'NULL', true],
    [905, 'CONFIRMED', 'NULL', "datetime('now','-30 days')", 'NULL', true],
    // 과거 취소 시각 미기록 데이터에 신청일을 취소일로 추정하면 안 된다.
    [906, 'CANCELED', 'NULL', "datetime('now','-30 days')", 'USER', true],
    [907, 'CONFIRMED', 'NULL', "datetime('now','-6 years')", 'NULL', false],
  ];
  for (const [id, status, canceledAt, createdAt, by] of cases) {
    await db.exec(`INSERT INTO reservations(reservation_id,user_id,pet_id,store_id,start_date,end_date,reservation_type,status,created_at,canceled_at,canceled_by)
      VALUES(${id},901,901,901,'2099-01-01','2099-01-01','NORMAL','${status}',${createdAt},${canceledAt},${by === 'NULL' ? 'NULL' : `'${by}'`});`.replace(/\n/g, ' '));
  }
  await db.exec("UPDATE reservations SET end_date = date('now','-6 years') WHERE reservation_id=907;");
  await db.exec(`INSERT INTO diaries(diary_id,reservation_id,store_id,content) VALUES(901,901,901,'삭제 대상 사진');
    INSERT INTO diary_photos(photo_id,diary_id,r2_key,sort_order) VALUES(901,901,'retention-fixture/photo.jpg',0);
    INSERT INTO pet_reviews(id,store_key,rating,reservation_id) VALUES(901,'retention-store',5,901);`);
  const bucket = await mf.getR2Bucket('DIARY_PHOTOS');
  await bucket.put('retention-fixture/photo.jpg', 'local fixture');
  const token = 'retention-fixture-session';
  await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,901,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(token).digest('hex')).run();
  const list = await mf.dispatchFetch('http://localhost/api/users/901/reservations', {
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.equal(list.status, 200);
  const listed = (await list.json()).map(row => row.reservation_id);
  for (const id of [901, 903]) assert.ok(!listed.includes(id), `정리 전에도 만료 취소 예약 ${id} 목록 제외`);
  for (const id of [902, 904, 905, 906]) assert.ok(listed.includes(id), `유효 예약 ${id} 목록 보존`);
  const run = () => mf.dispatchFetch('http://localhost/api/internal/data-retention', {
    method: 'POST', headers: { 'X-Internal-Key': 'local-retention-key' },
  });
  const response = await run();
  assert.equal(response.status, 200);
  for (const [id, , , , , retained] of cases) {
    const row = await db.prepare('SELECT reservation_id FROM reservations WHERE reservation_id = ?').bind(id).first();
    assert.equal(!!row, retained, `reservation ${id}: 취소 시각 기준 7일 경계`);
  }
  assert.equal(await db.prepare('SELECT diary_id FROM diaries WHERE diary_id=901').first(), null);
  assert.equal(await db.prepare('SELECT photo_id FROM diary_photos WHERE photo_id=901').first(), null);
  assert.equal(await bucket.get('retention-fixture/photo.jpg'), null, '연결된 R2 사진도 삭제');
  assert.equal((await db.prepare('SELECT reservation_id FROM pet_reviews WHERE id=901').first()).reservation_id, null, '리뷰는 보존하고 예약 연결만 제거');
  assert.equal((await run()).status, 200, '반복 정리는 멱등');
  console.log('PASS canceled retention: 취소자 무관·취소 후 7일 경계·신청일 미사용·REQUEST/CONFIRMED 보존·D1/R2 삭제·멱등');
} finally {
  await mf.dispose();
}
