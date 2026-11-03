#!/usr/bin/env node
// 실제 정리 SQL·Worker와 격리된 D1/R2를 검사한다. 운영 자원은 사용하지 않는다.
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const backend = fileURLToPath(new URL('..', import.meta.url));
const source = await readFile(`${backend}/src/index.ts`, 'utf8');
const query = source.match(/`(SELECT r2_key FROM diary_photo_deletion_queue\s[^`]+)`/)?.[1];
assert.ok(query, '측정할 실제 Worker 삭제 대기 조회 SQL을 찾는다');
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'photo-cleanup-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { INTERNAL_API_KEY: 'local-photo-cleanup-key' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
try {
  const db = await mf.getD1Database('DB'), bucket = await mf.getR2Bucket('DIARY_PHOTOS');
  const migrations = (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort();
  const indexMigration = '0033_photo_deletion_queue_index.sql';
  const apply = async (file) => {
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  };
  for (const file of migrations.filter(file => file < indexMigration)) await apply(file);
  await db.exec(`WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<5000)
    INSERT INTO diary_photo_deletion_queue(r2_key,queued_at,available_at)
    SELECT 'future/'||x, '1990-01-01 00:00:00', '2999-01-01 00:00:00' FROM n;
    INSERT INTO diary_photo_deletion_queue(r2_key,queued_at,available_at) VALUES
    ('due/old.jpg','2000-01-01 00:00:00','2000-01-02 00:00:00'),
    ('due/legacy.jpg','2001-01-01 00:00:00',NULL),
    ('due/offset.jpg','2002-01-01 00:00:00','2002-01-01T09:00:00+09:00'),
    ('invalid/date.jpg','2003-01-01 00:00:00','invalid-date');`.replace(/\n/g, ' '));
  const before = await db.prepare(query).all();
  for (const file of migrations.filter(file => file >= indexMigration)) await apply(file);
  assert.equal((await db.prepare('SELECT COUNT(*) AS count FROM diary_photo_deletion_queue').first()).count, 5004,
    '기존 대기 데이터가 있는 DB에 인덱스 마이그레이션을 적용해도 행 보존');
  const due = await db.prepare(query).all();
  assert.deepEqual(due.results.map(row => row.r2_key),
    ['due/old.jpg', 'due/legacy.jpg', 'due/offset.jpg'], '미래 예정은 제외하고 기존 NULL·ISO offset과 원래 순서는 보존');
  const plan = (await db.prepare(`EXPLAIN QUERY PLAN ${query}`).all()).results.map(row => row.detail);
  console.log('cleanup plan:', plan);
  console.log('cleanup query rows_read before/after:', before.meta.rows_read, due.meta.rows_read);
  assert.ok(plan.some(detail => /SEARCH diary_photo_deletion_queue USING INDEX/.test(detail)),
    '미래 삭제 예정이 많이 쌓여도 대상 시각을 인덱스로 검색');
  assert.ok(due.meta.rows_read < 100, '미래 데이터5000건 전체를 스캔하지 않음');

  for (const key of ['due/old.jpg', 'due/legacy.jpg', 'due/offset.jpg', 'future/1']) await bucket.put(key, 'fixture');
  const run = () => mf.dispatchFetch('http://localhost/api/internal/data-retention', {
    method: 'POST', headers: { 'X-Internal-Key': 'local-photo-cleanup-key' },
  });
  assert.equal((await run()).status, 200);
  for (const key of ['due/old.jpg', 'due/legacy.jpg', 'due/offset.jpg']) {
    assert.equal(await bucket.get(key), null, '정리 대상 R2 객체 삭제');
    assert.equal(await db.prepare('SELECT r2_key FROM diary_photo_deletion_queue WHERE r2_key=?').bind(key).first(), null);
  }
  assert.ok(await bucket.get('future/1'), '유예 기간의 R2 객체는 보존');
  assert.equal((await db.prepare('SELECT COUNT(*) AS count FROM diary_photo_deletion_queue').first()).count, 5001);

  // R2 삭제 뒤 D1 완료 기록 삭제가 실패해도 키를 잃지 않고 다음 실행에서 복구한다.
  await db.prepare("INSERT INTO diary_photo_deletion_queue(r2_key,queued_at) VALUES('retry/photo.jpg','2000-01-01')").run();
  await db.prepare(`CREATE TRIGGER block_cleanup_test BEFORE DELETE ON diary_photo_deletion_queue
    WHEN OLD.r2_key='retry/photo.jpg' BEGIN SELECT RAISE(ABORT,'fixture cleanup failure'); END`).run();
  await bucket.put('retry/photo.jpg', 'fixture');
  assert.equal((await run()).status, 200, '정리 실패는 다음 실행으로 유예');
  assert.equal(await bucket.get('retry/photo.jpg'), null);
  assert.ok(await db.prepare("SELECT r2_key FROM diary_photo_deletion_queue WHERE r2_key='retry/photo.jpg'").first(), '실패한 완료 기록 보존');
  await db.exec('DROP TRIGGER block_cleanup_test');
  assert.equal((await run()).status, 200);
  assert.equal(await db.prepare("SELECT r2_key FROM diary_photo_deletion_queue WHERE r2_key='retry/photo.jpg'").first(), null,
    '이미 없는 R2 객체도 안전하게 재시도 후 대기 기록 제거');
  await db.exec(`WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1005)
    INSERT INTO diary_photo_deletion_queue(r2_key,queued_at)
    SELECT 'bounded/'||x, '2000-01-01 00:00:00' FROM n;`.replace(/\n/g, ' '));
  assert.equal((await run()).status, 200);
  assert.equal((await db.prepare("SELECT COUNT(*) AS count FROM diary_photo_deletion_queue WHERE r2_key LIKE 'bounded/%'").first()).count, 5,
    '한 번에 최대1000건만 처리하고 나머지는 다음 실행에 남김');
  assert.equal((await run()).status, 200);
  assert.equal((await db.prepare("SELECT COUNT(*) AS count FROM diary_photo_deletion_queue WHERE r2_key LIKE 'bounded/%'").first()).count, 0);
  console.log('PASS photo cleanup: indexed bounded scan, legacy dates, future exclusion, R2 cleanup, failed acknowledgement recovery and batch limit');
} finally {
  await mf.dispose();
}
