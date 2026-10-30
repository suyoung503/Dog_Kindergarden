#!/usr/bin/env node
// Two fake clients against disposable local Worker/D1 only; no real account credentials.
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'profile-sync-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'profile sync local test', ALLOW_DEV_AUTH: 'true' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
let checks = 0;
let otherServer;
const equal = (actual, expected, name) => { assert.deepEqual(actual, expected, name); checks++; };
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort()) {
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  }
  const request = async (method, path, body, token) => {
    const response = await mf.dispatchFetch(`http://localhost${path}`, { method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    const text = await response.text();
    return { status: response.status, data: text.startsWith('{') ? JSON.parse(text) : text };
  };
  const login = async (identity = 'owner') => (await request('POST', '/api/auth/dev', { identity, is_owner: true, nickname: '테스트사장님' })).data;
  const fields = user => ({ nickname: user.nickname, phone: user.phone, address: user.address, email: user.email });
  const deviceA = await login();
  const deviceB = await login();
  equal(deviceA.user_id, deviceB.user_id, 'same server and dev identity is the same app account');
  const profile = { nickname: '동기화 보호자', phone: '010-0000-1234', address: '서울시 테스트 주소', email: 'sync@example.com' };
  const saved = await request('PUT', `/api/users/${deviceA.user_id}`, profile, deviceA.session_token);
  equal(saved.status, 200, 'device A saves all four profile fields');
  equal(fields(saved.data), profile, 'save response returns all four fields');
  equal(await db.prepare('SELECT nickname, phone, address, email FROM users WHERE user_id = ?').bind(deviceA.user_id).first(), profile, 'all four fields persist on server');
  equal(fields(await login()), profile, 'fresh device login restores server profile rather than default login nickname');
  const restored = await request('GET', '/api/auth/me', undefined, deviceB.session_token);
  equal(restored.status, 200, 'device B existing session can refresh server profile on cold restore');
  equal(restored.data.user_id, deviceB.user_id, 'whoami returns authenticated app account');
  equal(fields(restored.data), profile, 'cold restore returns all four latest fields');
  equal(restored.data.session_token, undefined, 'profile refresh does not rotate or return credentials');
  equal(restored.data.kakao_id, undefined, 'profile refresh does not expose provider identity');
  // 같은 역할/identity나 숫자 ID여도 다른 서버 DB면 동일 앱 계정으로 간주하지 않는다.
  const otherOptions = { ...options, name: 'profile-sync-other-server' };
  otherServer = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(otherOptions) : otherOptions);
  const otherDB = await otherServer.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort()) {
    await otherDB.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  }
  const otherLogin = await otherServer.dispatchFetch('http://localhost/api/auth/dev', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ identity: 'owner', is_owner: true, nickname: '테스트사장님' }),
  });
  equal(fields(await otherLogin.json()), { nickname: '테스트사장님', phone: null, address: null, email: null },
    'same dev identity on a different server database must not import profile automatically');
  const wrongServerSession = await otherServer.dispatchFetch('http://localhost/api/auth/me', {
    headers: { Authorization: `Bearer ${deviceA.session_token}` },
  });
  equal(wrongServerSession.status, 401, 'server A session is not valid on server B');
  const other = await login('different-owner');
  assert.notEqual(other.user_id, deviceA.user_id);
  equal(fields((await request('GET', '/api/auth/me', undefined, other.session_token)).data),
    { nickname: '테스트사장님', phone: null, address: null, email: null }, 'different dev identity cannot inherit another account profile');
  equal((await request('GET', '/api/auth/me')).status, 401, 'anonymous whoami is rejected');
  equal((await request('GET', '/api/auth/me', undefined, 'fake-expired-token')).status, 401, 'invalid session is rejected');
  await request('PUT', `/api/users/${deviceA.user_id}`, { nickname: '빈 선택 필드', phone: null, address: null, email: '' }, deviceA.session_token);
  equal(fields((await request('GET', '/api/auth/me', undefined, deviceB.session_token)).data),
    { nickname: '빈 선택 필드', phone: null, address: null, email: null }, 'server nulls cannot resurrect stale cached fields');
  await request('POST', '/api/auth/logout', {}, deviceB.session_token);
  equal((await request('GET', '/api/auth/me', undefined, deviceB.session_token)).status, 401, 'logged out session cannot restore profile');
  console.log(`PASS profile sync: ${checks} checks`);
} finally { if (otherServer) await otherServer.dispose(); await mf.dispose(); }
