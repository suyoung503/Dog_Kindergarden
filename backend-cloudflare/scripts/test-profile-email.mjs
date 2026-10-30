#!/usr/bin/env node
// Isolated local Worker/D1 only; email format checks do not prove mailbox ownership.
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'profile-email-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'email local test', ALLOW_DEV_AUTH: 'true' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
let checks = 0;
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
    return { status: response.status, data: await response.json() };
  };
  const login = async identity => (await request('POST', '/api/auth/dev', { identity, nickname: identity })).data;
  const user = await login('email-owner');
  const other = await login('email-other');
  const path = `/api/users/${user.user_id}`;
  const update = body => request('PUT', path, body, user.session_token);
  const email = () => db.prepare('SELECT email FROM users WHERE user_id = ?').bind(user.user_id).first('email');
  const valid = await update({ email: '  owner+profile@example.co.kr  ' });
  equal(valid.status, 200, 'optional email can be registered alone');
  equal(valid.data.email, 'owner+profile@example.co.kr', 'email is trimmed and returned');
  equal(await email(), 'owner+profile@example.co.kr', 'email persists on server');
  equal((await login('email-owner')).email, 'owner+profile@example.co.kr', 'relogin restores app profile email');
  for (const value of ['bad', 'a@b', 'a b@example.com', 'a\n@example.com', 'a@@example.com', '@example.com', 'a@example.', 'a'.repeat(243) + '@example.com', 123, {}, []]) {
    equal((await update({ nickname: 'must-not-write', email: value })).status, 400, `reject invalid email ${JSON.stringify(value)}`);
    equal(await email(), 'owner+profile@example.co.kr', 'invalid request preserves old email');
    equal(await db.prepare('SELECT nickname FROM users WHERE user_id = ?').bind(user.user_id).first('nickname'), 'email-owner', 'invalid email does not partially update profile');
  }
  equal((await request('PUT', path, { email: 'hijack@example.com' }, other.session_token)).status, 403, 'another account cannot update email');
  equal((await request('PUT', path, { email: 'hijack@example.com' })).status, 401, 'anonymous update rejected');
  equal((await update({ nickname: 'email-renamed' })).status, 200, 'email omitted leaves existing email');
  equal(await email(), 'owner+profile@example.co.kr', 'omitted email is unchanged');
  for (const value of ['', '   ', null]) {
    equal((await update({ email: 'again@example.com' })).status, 200, 'email can be modified');
    equal((await update({ email: value })).data.email, null, 'blank or null clears optional email');
    equal(await email(), null, 'cleared email is database NULL');
    equal((await login('email-owner')).email, null, 'relogin does not resurrect cleared email');
  }
  console.log(`PASS profile email: ${checks} checks`);
} finally { await mf.dispose(); }
