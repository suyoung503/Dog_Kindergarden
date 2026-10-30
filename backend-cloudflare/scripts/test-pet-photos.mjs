#!/usr/bin/env node
// Local Worker only: wrangler dev --local --port 8797 --persist-to /tmp/device-fix07-state --var ALLOW_DEV_AUTH:true
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
const localDB = process.env.PET_PHOTO_TEST_DB;
if (localDB && !localDB.startsWith('/tmp/')) throw new Error('Test database must be under /tmp');
const sql = query => execFileSync('/usr/bin/sqlite3', [localDB, query], { encoding: 'utf8' }).trim();
const base = process.env.API_BASE_URL ?? 'http://127.0.0.1:8797';
if (!/^http:\/\/(127\.0\.0\.1|localhost):/.test(base)) throw new Error('Local Worker only');
const suffix = crypto.randomUUID();
let checks = 0;
async function request(method, path, token, body, contentType = 'application/json') {
  const response = await fetch(base + path, { method, headers: {
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...(body !== undefined ? { 'Content-Type': contentType } : {}),
  }, body: body === undefined ? undefined : contentType === 'application/json' ? JSON.stringify(body) : body });
  const bytes = new Uint8Array(await response.arrayBuffer());
  let data; try { data = JSON.parse(new TextDecoder().decode(bytes)); } catch { data = bytes; }
  return { status: response.status, data, bytes, headers: response.headers };
}
function equal(actual, expected, name) { assert.deepEqual(actual, expected, name); checks++; }
async function login(identity) {
  const result = await request('POST', '/api/auth/dev', undefined, { identity: `pet-photos-${identity}-${suffix}`, nickname: identity });
  equal([200, 201].includes(result.status), true, 'dev login'); return result.data;
}
const owner = await login('owner');
const other = await login('other');
const token = owner.session_token;
const created = await request('POST', `/api/users/${owner.user_id}/pets`, token, { name: '큰사진' });
equal(created.status, 201, 'pet creation');
const id = created.data.pet_id;
const path = `/api/pets/${id}/photo`;
// An actual 1x1 JPEG; structure alone is not enough for API acceptance.
const jpeg = Uint8Array.from(Buffer.from('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAgP/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=', 'base64'));
equal((await request('PUT', path, token, jpeg, 'image/jpeg')).status, 201, 'own JPEG uploads to private R2');
const listed = await request('GET', `/api/users/${owner.user_id}/pets`, token);
equal(listed.data.find(p => p.pet_id === id).image_url, path, 'DB stores authenticated path, not R2 URL/base64');
const fetched = await request('GET', path, token);
equal(fetched.status, 200, 'owner fetch');
equal(fetched.bytes, jpeg, 'R2 bytes preserved');
equal(fetched.headers.get('cache-control'), 'private, no-store', 'private cache');
if (localDB) {
  const originalKey = sql(`SELECT r2_key FROM pet_photos WHERE pet_id = ${id}`);
  sql(`CREATE TRIGGER fail_pet_photo_test BEFORE INSERT ON pet_photos BEGIN SELECT RAISE(ABORT, 'test metadata failure'); END;`);
  try {
    equal((await request('PUT', path, token, jpeg, 'image/jpeg')).status, 500, 'DB commit failure surfaces, rather than false success');
    equal(sql(`SELECT r2_key FROM pet_photos WHERE pet_id = ${id}`), originalKey, 'failed replacement preserves previous photo');
    equal((await request('GET', path, token)).bytes, jpeg, 'previous R2 photo remains readable after failed replacement');
    equal(sql(`SELECT COUNT(*) FROM diary_photo_deletion_queue WHERE r2_key LIKE 'pet-photos/${owner.user_id}/%'`), '0', 'failed upload staged object cleaned through durable queue');
  } finally { sql(`DROP TRIGGER fail_pet_photo_test;`); }
}
equal((await request('GET', path)).status, 401, 'unauthenticated fetch denied');
for (const method of ['GET', 'PUT', 'DELETE']) equal((await request(method, path, other.session_token, method === 'PUT' ? jpeg : undefined, 'image/jpeg')).status, 403, `other user ${method} denied`);
equal((await request('PUT', path, token, new Uint8Array(1_500_001), 'image/jpeg')).status, 413, 'optimized upload over 1.5MB denied');
equal((await request('PUT', path, token, jpeg, 'image/png')).status, 400, 'non-JPEG rejected');
equal((await request('PUT', path, token, new Uint8Array([255,216,255,217]), 'image/jpeg')).status, 400, 'fake JPEG rejected');
equal((await request('PUT', path, token, jpeg, 'image/jpeg')).status, 201, 'photo replacement');
equal((await request('DELETE', path, token)).status, 200, 'owner photo deletion');
equal((await request('GET', path, token)).status, 404, 'deleted photo hidden');
equal((await request('DELETE', path, token)).status, 200, 'photo deletion idempotent');
for (const image_url of ['https://other.r2.dev/private.jpg', '/api/pets/999/photo', { bad: true }]) equal((await request('POST', `/api/users/${owner.user_id}/pets`, token, { name: '위조', image_url })).status, 400, 'arbitrary photo reference rejected');
const legacyURL = `data:image/jpeg;base64,${Buffer.from(jpeg).toString('base64')}`;
const legacy = await request('POST', `/api/users/${owner.user_id}/pets`, token, { name: '기존사진', image_url: legacyURL });
equal(legacy.status, 201, 'legacy client remains compatible');
equal(legacy.data.image_url, legacyURL, 'legacy base64 preserved');
equal((await request('PUT', path, token, jpeg, 'image/jpeg')).status, 201, 'upload before pet deletion');
equal((await request('DELETE', `/api/pets/${id}`, token)).status, 200, 'pet deletion');
equal((await request('GET', path, token)).status, 404, 'deleted pet photo unavailable');
if (localDB) {
  equal(sql(`SELECT COUNT(*) FROM pet_photos WHERE pet_id = ${id}`), '0', 'pet deletion removes metadata');
  equal(sql(`SELECT COUNT(*) FROM diary_photo_deletion_queue WHERE r2_key LIKE 'pet-photos/${owner.user_id}/%'`), '0', 'pet deletion drains R2 cleanup queue');
}
const accountPet = await request('POST', `/api/users/${owner.user_id}/pets`, token, { name: '탈퇴사진' });
equal((await request('PUT', `/api/pets/${accountPet.data.pet_id}/photo`, token, jpeg, 'image/jpeg')).status, 201, 'upload before account deletion');
equal((await request('DELETE', `/api/users/${owner.user_id}/account`, token)).status, 200, 'account deletion with R2 photo');
equal((await request('GET', `/api/pets/${accountPet.data.pet_id}/photo`, other.session_token)).status, 404, 'deleted account photo unavailable');
if (localDB) {
  equal(sql(`SELECT COUNT(*) FROM pet_photos WHERE pet_id = ${accountPet.data.pet_id}`), '0', 'account deletion removes metadata');
  equal(sql(`SELECT COUNT(*) FROM diary_photo_deletion_queue WHERE r2_key LIKE 'pet-photos/${owner.user_id}/%'`), '0', 'account deletion drains R2 cleanup queue');
}
equal((await request('DELETE', `/api/users/${other.user_id}/account`, other.session_token)).status, 200, 'test account cleanup');
console.log(`PASS ${checks} pet photo API checks`);
