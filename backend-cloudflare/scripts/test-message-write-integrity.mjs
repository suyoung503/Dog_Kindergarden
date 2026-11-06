#!/usr/bin/env node
// 실제 Hono/로컬 D1/R2/DO. SELECT 결과의 전달 시점만 지연하며 값·권한·SQL은 대체하지 않는다.
// Node의 DurableObject 기반 클래스만 격리하고 실제 DO는 원본 workerd에서 실행한다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { test } from 'node:test';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const backend = fileURLToPath(new URL('..', import.meta.url));
const temporary = await mkdtemp(`${tmpdir()}/message-write-integrity-`);
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
  const options = { name: 'message-write-integrity-test', modules: true, script: workerBundle.outputFiles[0].text,
    compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
    durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
  mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
  const db = await mf.getD1Database('DB');
  const env = { DB: db, DIARY_PHOTOS: await mf.getR2Bucket('DIARY_PHOTOS'),
    USER_REALTIME: await mf.getDurableObjectNamespace('USER_REALTIME') };
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  const rows = async (sql, ...values) => (await db.prepare(sql).bind(...values).all()).results;
  const api = async (path, user, body, database = db, method = 'POST') => {
    const response = await worker.fetch(new Request(`http://localhost/api${path}`, {
      method, headers: { Authorization: `Bearer message-write-${user}`, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), { ...env, DB: database }, { waitUntil() {} });
    const raw = await response.text();
    let data; try { data = JSON.parse(raw); } catch { data = raw; }
    return { status: response.status, data };
  };
  const removeAccount = user => api(`/users/${user}/account`, user, undefined, db, 'DELETE');
  let nextId = 9800;
  async function fixture() {
    nextId += 10;
    const f = { room: nextId, customer: nextId + 1, owner: nextId + 2, admin: nextId + 3, outsider: nextId + 4 };
    for (const user of [f.customer, f.owner, f.admin, f.outsider]) {
      await db.prepare(`INSERT INTO users(user_id,kakao_id,nickname,is_owner,is_admin) VALUES(?,?,?,?,?)`)
        .bind(user, `message-write-${user}`, `사용자${user}`, user === f.owner ? 1 : 0, user === f.admin ? 1 : 0).run();
      await db.prepare(`INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))`)
        .bind(createHash('sha256').update(`message-write-${user}`).digest('hex'), user).run();
    }
    await db.prepare(`INSERT INTO stores(store_id,store_key,name,owner_id,partner_status) VALUES(?,?,?,?,'ACTIVE')`)
      .bind(f.room, `message-store-${f.room}`, '메시지 가게', f.owner).run();
    await db.prepare(`INSERT INTO chat_rooms(room_id,user_id,store_id) VALUES(?,?,?)`).bind(f.room, f.customer, f.room).run();
    return f;
  }
  async function open(f) {
    const response = await api('/support/conversation', f.customer);
    assert.equal(response.status, 201);
    return response.data.conversation_id;
  }
  function onceAfter(pattern, action) {
    let arrivals = 0;
    const database = new Proxy(db, { get(target, key) {
      if (key !== 'prepare') return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
      return sql => {
        const statement = target.prepare(sql);
        if (!pattern.test(sql)) return statement;
        const wrap = prepared => new Proxy(prepared, { get(target, key) {
          if (key === 'bind') return (...values) => wrap(target.bind(...values));
          if (key === 'first') return async (...args) => {
            const result = await target.first(...args);
            if (!arrivals) {
              arrivals += 1;
              await action(result);
            }
            return result;
          };
          return typeof target[key] === 'function' ? target[key].bind(target) : target[key];
        } });
        return wrap(statement);
      };
    } });
    return { database, arrivals: () => arrivals };
  }
  const chatRead = /SELECT 1 AS allowed\s+FROM chat_rooms r/;
  const supportRead = /SELECT conversation_id\s+FROM support_conversations\s+WHERE conversation_id = \? AND user_id = \?/;
  const adminSupportRead = /SELECT conversation_id FROM support_conversations WHERE conversation_id = \?/;
  const authRead = /SELECT s.user_id, u.is_owner, u.is_admin\s+FROM auth_sessions s/;
  const availableRead = /SELECT 1 AS available\s+FROM users\s+WHERE is_admin = 1 AND deleted_at IS NULL/;

  await test('채팅·고객센터의 저장 시점 권한과 원자성', { timeout: 90000 }, async t => {
    await t.test('가게 채팅은 양쪽 전송·실제 계정 표시명·외부 계정 거절을 유지한다', { timeout: 15000 }, async () => {
      const f = await fixture();
      for (const user of [f.customer, f.owner]) {
        const response = await api(`/chatrooms/${f.room}/messages`, user, { content: `정상-${user}`, sender_name: '위조' });
        assert.equal(response.status, 201);
        assert.equal(response.data.sender_id, user);
        assert.equal(response.data.sender_name, `사용자${user}`);
      }
      assert.equal((await api(`/chatrooms/${f.room}/messages`, f.outsider, { content: '금지' })).status, 403);
      assert.equal((await api(`/chatrooms/${f.room}/messages`, f.customer, { sender_id: f.owner, content: '사칭' })).status, 403);
      assert.equal((await rows('SELECT * FROM chat_messages WHERE room_id=?', f.room)).length, 2);
    });

    for (const actor of ['customer', 'owner']) await t.test(`${actor} 탈퇴가 먼저 끝나면 늦은 채팅은 개인정보를 남기지 않는다`, { timeout: 15000 }, async t => {
      const f = await fixture();
      const gate = onceAfter(chatRead, async result => {
        assert.equal(result.allowed, 1);
        assert.equal((await removeAccount(f[actor])).status, 200);
      });
      const response = await api(`/chatrooms/${f.room}/messages`, f[actor], { content: '탈퇴 후 저장 금지' }, gate.database);
      const messages = await rows('SELECT * FROM chat_messages WHERE room_id=?', f.room);
      t.diagnostic(`gate=${gate.arrivals()} response=${response.status} messages=${messages.length}`);
      assert.equal(gate.arrivals(), 1);
      assert.equal(response.status, 403);
      assert.equal(messages.length, 0);
    });

    await t.test('방 접근을 읽은 뒤 가게 연결이 종료되면 새 채팅을 저장하지 않는다', { timeout: 15000 }, async () => {
      const f = await fixture();
      const gate = onceAfter(chatRead, async result => {
        assert.equal(result.allowed, 1);
        assert.equal((await api(`/owners/${f.owner}/stores/${f.room}`, f.owner, undefined, db, 'DELETE')).status, 200);
      });
      const response = await api(`/chatrooms/${f.room}/messages`, f.customer, { content: '연결 해제 후 금지' }, gate.database);
      assert.equal(gate.arrivals(), 1);
      assert.equal(response.status, 403);
      assert.equal((await rows('SELECT * FROM chat_messages WHERE room_id=?', f.room)).length, 0);
    });

    await t.test('고객센터는 기존 방 재사용·양쪽 역할·외부 계정 거절을 유지한다', { timeout: 15000 }, async () => {
      const f = await fixture(), id = await open(f);
      const again = await api('/support/conversation', f.customer);
      assert.equal(again.status, 200); assert.equal(again.data.conversation_id, id);
      for (const [user, role] of [[f.customer, 'USER'], [f.admin, 'ADMIN']]) {
        const response = await api(`/support/conversations/${id}/messages`, user, { content: `정상-${role}` });
        assert.equal(response.status, 201); assert.equal(response.data.sender_role, role);
      }
      assert.equal((await api(`/support/conversations/${id}/messages`, f.outsider, { content: '금지' })).status, 403);
      assert.equal((await rows('SELECT * FROM support_messages WHERE conversation_id=?', id)).length, 2);
    });

    for (const actor of ['customer', 'admin']) await t.test(`고객 탈퇴 후 지연된 ${actor} 문의는 FK500이나 잔여 메시지 대신403이다`, { timeout: 15000 }, async t => {
      const f = await fixture(), id = await open(f);
      const gate = onceAfter(actor === 'admin' ? adminSupportRead : supportRead, async result => {
        assert.equal(result.conversation_id, id);
        assert.equal((await removeAccount(f.customer)).status, 200);
      });
      const response = await api(`/support/conversations/${id}/messages`, f[actor], { content: '삭제된 대화 저장 금지' }, gate.database);
      t.diagnostic(`gate=${gate.arrivals()} response=${response.status}`);
      assert.equal(gate.arrivals(), 1); assert.equal(response.status, 403);
      assert.equal((await rows('SELECT * FROM support_messages WHERE conversation_id=?', id)).length, 0);
    });

    await t.test('현재 DB에서 운영자 역할이 해제되면 이전 인증의 ADMIN 답변을 거절한다', { timeout: 15000 }, async () => {
      const f = await fixture(), id = await open(f);
      await db.prepare("UPDATE support_conversations SET status='CLOSED',updated_at='2000-01-01' WHERE conversation_id=?").bind(id).run();
      const gate = onceAfter(adminSupportRead, async result => {
        assert.equal(result.conversation_id, id);
        // 운영자 구성 변경을 실제 DB에 반영한다. 인증 SELECT 결과를 가짜 값으로 바꾸지 않는다.
        await db.prepare('UPDATE users SET is_admin=0 WHERE user_id=?').bind(f.admin).run();
      });
      const response = await api(`/support/conversations/${id}/messages`, f.admin, { content: '운영자 해제 후 금지' }, gate.database);
      assert.equal(gate.arrivals(), 1); assert.equal(response.status, 403);
      assert.equal((await rows('SELECT * FROM support_messages WHERE conversation_id=?', id)).length, 0);
      assert.deepEqual(await rows('SELECT status,updated_at FROM support_conversations WHERE conversation_id=?', id),
        [{ status: 'CLOSED', updated_at: '2000-01-01' }]);
    });

    await t.test('문의 상태 갱신 오류는 메시지도 rollback하며 재시도는 한 건만 저장한다', { timeout: 15000 }, async () => {
      const f = await fixture(), id = await open(f);
      await db.prepare("UPDATE support_conversations SET status='CLOSED',updated_at='2000-01-01' WHERE conversation_id=?").bind(id).run();
      const trigger = `fail_support_update_${id}`;
      await db.prepare(`CREATE TRIGGER ${trigger} BEFORE UPDATE ON support_conversations WHEN OLD.conversation_id=${id}
        BEGIN SELECT RAISE(ABORT,'fixture support update failure'); END`).run();
      try {
        assert.equal((await api(`/support/conversations/${id}/messages`, f.customer, { content: '재시도할 글' })).status, 500);
        assert.deepEqual(await rows('SELECT status,updated_at FROM support_conversations WHERE conversation_id=?', id),
          [{ status: 'CLOSED', updated_at: '2000-01-01' }]);
        assert.equal((await rows('SELECT * FROM support_messages WHERE conversation_id=?', id)).length, 0);
      } finally { await db.prepare(`DROP TRIGGER ${trigger}`).run(); }
      const retried = await api(`/support/conversations/${id}/messages`, f.customer, { content: '재시도할 글' });
      assert.equal(retried.status, 201);
      const messages = await rows('SELECT * FROM support_messages WHERE conversation_id=?', id);
      assert.equal(messages.length, 1); assert.equal(messages[0].message_id, retried.data.message_id);
      assert.equal((await rows('SELECT status FROM support_conversations WHERE conversation_id=?', id))[0].status, 'OPEN');
    });

    await t.test('인증 뒤 탈퇴가 끝나면 고객센터 방을 다시 만들지 않는다', { timeout: 15000 }, async () => {
      const f = await fixture();
      const gate = onceAfter(authRead, async result => {
        assert.equal(result.user_id, f.customer);
        assert.equal((await removeAccount(f.customer)).status, 200);
      });
      const response = await api('/support/conversation', f.customer, undefined, gate.database);
      assert.equal(gate.arrivals(), 1); assert.equal(response.status, 403);
      assert.equal((await rows('SELECT * FROM support_conversations WHERE user_id=?', f.customer)).length, 0);
    });

    for (const operation of ['message', 'open']) await t.test(`마지막 운영자 탈퇴 후 지연된 ${operation}은503이며 새 데이터를 만들지 않는다`, { timeout: 15000 }, async () => {
      const f = await fixture(), id = operation === 'message' ? await open(f) : null;
      if (id !== null) await db.prepare("UPDATE support_conversations SET status='CLOSED',updated_at='2000-01-01' WHERE conversation_id=?").bind(id).run();
      await db.prepare('UPDATE users SET is_admin=0 WHERE is_admin=1 AND user_id<>?').bind(f.admin).run();
      const gate = onceAfter(availableRead, async result => {
        assert.equal(result.available, 1);
        assert.equal((await removeAccount(f.admin)).status, 200);
      });
      const response = operation === 'message'
        ? await api(`/support/conversations/${id}/messages`, f.customer, { content: '운영자 없음' }, gate.database)
        : await api('/support/conversation', f.customer, undefined, gate.database);
      assert.equal(gate.arrivals(), 1); assert.equal(response.status, 503);
      assert.equal(response.data.code, 'SUPPORT_ADMIN_UNAVAILABLE');
      assert.equal((await rows('SELECT * FROM support_messages WHERE sender_id=?', f.customer)).length, 0);
      if (operation === 'open') assert.equal((await rows('SELECT * FROM support_conversations WHERE user_id=?', f.customer)).length, 0);
      else assert.deepEqual(await rows('SELECT status,updated_at FROM support_conversations WHERE conversation_id=?', id),
        [{ status: 'CLOSED', updated_at: '2000-01-01' }]);
    });
  });
} finally {
  try { if (mf) await mf.dispose(); } finally { await rm(temporary, { recursive: true, force: true }); }
}
