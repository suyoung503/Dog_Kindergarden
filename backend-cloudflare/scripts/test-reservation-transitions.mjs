#!/usr/bin/env node
// 실제 Worker/D1/채팅 이벤트를 로컬에서 검사한다. 운영 자원은 사용하지 않는다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'reservation-transition-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
const failures = [];
const check = async (name, run) => {
  try { await run(); console.log(`PASS ${name}`); }
  catch (error) { failures.push(name); console.error(`FAIL ${name}: ${error.message}`); }
};
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner) VALUES
    (980,'transition-customer','보호자',0),(981,'transition-owner','점주',1);
    INSERT INTO stores(store_id,name,store_key,owner_id,partner_status) VALUES(980,'동시성 유치원','transition-store',981,'ACTIVE');
    INSERT INTO pets(pet_id,user_id,name) VALUES(980,980,'초코');`.replace(/\n/g, ' '));
  for (const id of [980,981]) await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(`transition-token-${id}`).digest('hex'),id).run();
  const api = (path, id, method='PATCH', body) => mf.dispatchFetch(`http://localhost/api${path}`, {
    method, headers: { Authorization:`Bearer transition-token-${id}`, ...(body ? {'Content-Type':'application/json'} : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const booking = {pet_id:980,store_id:980,start_date:'2099-01-02',end_date:'2099-01-03',reservation_type:'돌봄'};
  const book = async () => {
    const response = await api('/reservations',980,'POST',booking);
    assert.equal(response.status,201); return (await response.json()).reservation_id;
  };
  const state = id => db.prepare('SELECT status,confirmed_at,canceled_at,canceled_by FROM reservations WHERE reservation_id=?').bind(id).first();
  const events = (id,type) => db.prepare('SELECT COUNT(*) AS count FROM chat_messages WHERE reservation_id=? AND event_type=?').bind(id,type).first().then(row=>row.count);
  await check('예약 생성 안내가 실패하면 예약 자체도 남지 않음', async () => {
    const before = (await db.prepare('SELECT COUNT(*) AS count FROM reservations').first()).count;
    await db.prepare(`CREATE TRIGGER fail_booking_event BEFORE INSERT ON chat_messages
      WHEN NEW.event_type='reservation_submitted' BEGIN SELECT RAISE(ABORT,'fixture booking event failure'); END`).run();
    try {
      assert.equal((await api('/reservations',980,'POST',booking)).status,500);
      assert.equal((await db.prepare('SELECT COUNT(*) AS count FROM reservations').first()).count,before,
        '500 응답 후 재시도로 중복 예약이 생기지 않게 미완료 예약 rollback');
    } finally { await db.exec('DROP TRIGGER fail_booking_event'); }
    const id = await book();
    assert.equal((await db.prepare('SELECT COUNT(*) AS count FROM reservations').first()).count,before+1);
    assert.equal(await events(id,'reservation_submitted'),1);
  });
  for (const action of ['confirm','cancel']) await check(`${action}: 상태와 안내는 함께 성공하거나 함께 실패`, async () => {
    const id = await book(), type = action === 'confirm' ? 'reservation_confirmed' : 'reservation_canceled';
    await db.prepare(`CREATE TRIGGER fail_transition_event BEFORE INSERT ON chat_messages
      WHEN NEW.event_type='${type}' BEGIN SELECT RAISE(ABORT,'fixture transition event failure'); END`).run();
    try {
      const response = await api(`/reservations/${id}/${action}`,981,'PATCH',action==='cancel'?{by_owner:true}:undefined);
      assert.equal(response.status,500,'안내 쓰기 실패를 성공으로 응답하지 않음');
      assert.deepEqual(await state(id),{status:'REQUEST',confirmed_at:null,canceled_at:null,canceled_by:null},'중간 실패 뒤 상태만 바뀌지 않음');
      assert.equal(await events(id,type),0);
    } finally { await db.exec('DROP TRIGGER fail_transition_event'); }
    assert.equal((await api(`/reservations/${id}/${action}`,981,'PATCH',action==='cancel'?{by_owner:true}:undefined)).status,200);
    assert.equal(await events(id,type),1,'재시도 시 영속 안내1건 생성');
  });
  for (const action of ['confirm','cancel']) await check(`${action}: 같은 상태 변경10개가 와도 안내1건`, async () => {
    const id = await book();
    const responses = await Promise.all(Array.from({length:10},()=>api(`/reservations/${id}/${action}`,981,'PATCH',action==='cancel'?{by_owner:true}:undefined)));
    assert.ok(responses.every(response=>[200,409].includes(response.status)),'경쟁 패자는 미변경 또는 충돌로 처리');
    assert.equal((await state(id)).status,action==='confirm'?'CONFIRMED':'CANCELED');
    assert.equal(await events(id,action==='confirm'?'reservation_confirmed':'reservation_canceled'),1);
    assert.equal((await api(`/reservations/${id}/${action}`,981,'PATCH',action==='cancel'?{by_owner:true}:undefined)).status,200);
    assert.equal(await events(id,action==='confirm'?'reservation_confirmed':'reservation_canceled'),1,'응답 유실 뒤 재호출도 중복 안내 없음');
  });
  await check('확정과 고객 취소가 동시에 들어와도 취소를 되돌리지 않음', async () => {
    const id = await book();
    const responses = await Promise.all(Array.from({length:10},(_,i)=>api(`/reservations/${id}/${i%2?'confirm':'cancel'}`,i%2?981:980)));
    assert.ok(responses.every(response=>[200,409].includes(response.status)));
    assert.equal((await state(id)).status,'CANCELED');
    assert.ok(await events(id,'reservation_confirmed')<=1);
    assert.equal(await events(id,'reservation_canceled'),0,'고객 본인 취소는 점주 취소 안내를 생성하지 않음');
  });
  assert.deepEqual(failures,[],`실패한 회귀: ${failures.join(', ')}`);
} finally { await mf.dispose(); }
