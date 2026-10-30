#!/usr/bin/env node
import assert from 'node:assert/strict';
import { build } from 'esbuild';
const bundle = await build({ entryPoints: [new URL('../src/storeSharePage.ts', import.meta.url).pathname], bundle: true, platform: 'node', format: 'esm', write: false });
const { storeShareResponse } = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
let reads = 0;
const key = '서울|멍 & 쉼/#?+%';
const row = { name: '<img src=x onerror=alert(1)>', address: '서울 & <script>bad</script>', phone: '02-1234-5678', owner_id: 'NEVER_EXPOSE_OWNER', session_token: 'NEVER_EXPOSE_TOKEN' };
const db = { prepare(sql) {
  assert.match(sql, /SELECT name, address, phone FROM stores/);
  assert.match(sql, /is_curated = 1/);
  assert.doesNotMatch(sql, /SELECT \*/);
  return { bind(value) { assert.equal(value, key); return { async first() { reads++; return row; } }; } };
} };
const response = await storeShareResponse(new Request(`https://example.com/store?key=${encodeURIComponent(key)}`), db);
assert.equal(response.status, 200);
const html = await response.text();
assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;/);
assert.doesNotMatch(html, /<script>|<img|NEVER_EXPOSE/);
assert.match(html, /앱이 설치되어 있지 않다면/);
const href = html.match(/href="(matgyeomung:[^"]+)"/)?.[1];
assert.ok(href);
const app = new URL(href.replaceAll('&amp;', '&'));
assert.equal(app.protocol, 'matgyeomung:');
assert.equal(app.hostname, 'store');
assert.equal(app.searchParams.get('key'), key);
assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
assert.match(response.headers.get('content-security-policy'), /default-src 'none'/);
for (const query of ['key=', 'key=%20', 'key=a&key=b', 'key=a&token=secret', `key=${'a'.repeat(513)}`, 'key=%00', 'key=%0A', 'key=%20padded', 'key=%F0%9F%90%B6'.repeat(129)]) {
  const result = await storeShareResponse(new Request('https://example.com/store?' + query), db);
  assert.equal(result.status, 400, query);
}
assert.equal(reads, 1, 'invalid requests never query DB');
const missingDB = { prepare() { return { bind() { return { async first() { return null; } }; } }; } };
assert.equal((await storeShareResponse(new Request('https://example.com/store?key=missing'), missingDB)).status, 404);
const failingDB = { prepare() { throw Error('SECRET_DB_ERROR'); } };
const failure = await storeShareResponse(new Request('https://example.com/store?key=missing'), failingDB);
assert.equal(failure.status, 503);
assert.doesNotMatch(await failure.text(), /SECRET_DB_ERROR/);
console.log('PASS store share landing validation, escaping, public-only fields, missing store and failure');
