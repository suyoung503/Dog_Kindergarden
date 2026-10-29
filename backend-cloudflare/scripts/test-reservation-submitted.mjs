#!/usr/bin/env node
// 실제 Worker + 격리 D1에서 고객 예약 접수와 사장님 새 요청 알림의 중복 방지를 검증한다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';
const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'reservation-submitted-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'reservation submitted local test' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort()) {
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  }
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner) VALUES(701,'submitted-customer','보호자',0),(702,'submitted-owner','사장님',1);
    INSERT INTO stores(store_id,name,store_key,owner_id,partner_status) VALUES(701,'예약 테스트','submitted-store',702,'ACTIVE');
    INSERT INTO pets(pet_id,user_id,name) VALUES(701,701,'초코');`.replace(/\n/g, ' '));
  for (const id of [701,702]) await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(`submitted-token-${id}`).digest('hex'), id).run();
  const api = (path, id, method = 'GET', body) => mf.dispatchFetch(`http://localhost/api${path}`, {
    method, headers: { Authorization: `Bearer submitted-token-${id}`, ...(body ? {'Content-Type':'application/json'} : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const feed = async (id, cursor) => {
    const response = await api(`/users/${id}/notifications${cursor ? `?cursor=${encodeURIComponent(JSON.stringify(cursor))}` : ''}`, id);
    assert.equal(response.status, 200); return response.json();
  };
  const customerBaseline = await feed(701), ownerBaseline = await feed(702);
  const response = await api('/reservations',701,'POST',{pet_id:701,store_id:701,store_name:'예약 테스트',start_date:'2099-01-01',end_date:'2099-01-01'});
  assert.equal(response.status,201);
  const reservation = await response.json();
  const customerFeed = await feed(701,customerBaseline.cursor);
  assert.equal(customerFeed.notifications.length,1,'고객에게 예약 접수 알림은 정확히 1개');
  const submitted = customerFeed.notifications[0];
  assert.equal(submitted.type,'reservation_submitted','예약 접수는 chat 대신 예약 알림이어야 한다');
  assert.equal(submitted.reservation_id,reservation.reservation_id);
  assert.equal(submitted.as_owner,false);
  assert.equal(submitted.body,'예약 요청이 완료되었습니다.');
  assert.ok(!customerFeed.notifications.some(n => n.type === 'chat'),'시스템 메시지의 일반 채팅 알림 중복 없음');
  const messages = await db.prepare('SELECT sender_id, message_type, content, event_type, reservation_id FROM chat_messages WHERE room_id = ?').bind(reservation.room_id).all();
  assert.deepEqual(messages.results,[{sender_id:0,message_type:'AUTO',content:'예약 요청이 완료되었습니다.',event_type:'reservation_submitted',reservation_id:reservation.reservation_id}],'채팅방 시스템 안내와 문구를 그대로 보존');
  const ownerFeed = await feed(702,ownerBaseline.cursor);
  assert.equal(ownerFeed.notifications.length,1,'사장님에게 새 예약 요청 알림만 1개');
  assert.equal(ownerFeed.notifications[0].type,'reservation_request');
  assert.equal(ownerFeed.notifications[0].as_owner,true,'예약 확정 대기 화면의 사장님 문맥 유지');
  assert.equal(ownerFeed.notifications[0].reservation_id,reservation.reservation_id);
  assert.deepEqual((await feed(701,customerFeed.cursor)).notifications,[]);
  assert.deepEqual((await feed(702,ownerFeed.cursor)).notifications,[]);
  console.log('PASS reservation submitted: 고객 예약 접수 1건, 시스템 안내 보존, 사장님 새 요청 문맥, 중복 없음');
} finally { await mf.dispose(); }
