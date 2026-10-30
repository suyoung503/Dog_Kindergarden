#!/usr/bin/env node
// 실제 Worker와 격리 D1에서 알림장 도착 문맥과 고객 간 격리를 검증한다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';
const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'diary-notification-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'diary notification local test' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort()) {
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  }
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner) VALUES(801,'diary-customer','보호자',0),(802,'diary-owner','사장님',1),(803,'diary-other','다른 보호자',0);
    INSERT INTO stores(store_id,name,store_key,owner_id,partner_status) VALUES(801,'알림장 유치원','diary-store',802,'ACTIVE');
    INSERT INTO pets(pet_id,user_id,name) VALUES(801,801,'초코'),(802,801,'보리'),(803,803,'다른 아이');
    INSERT INTO chat_rooms(room_id,user_id,store_id) VALUES(801,801,801),(803,803,801);`.replace(/\n/g,' '));
  for (const id of [801,802,803]) await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(`diary-token-${id}`).digest('hex'), id).run();
  const api = (path,id,method='GET',body) => mf.dispatchFetch(`http://localhost/api${path}`, {
    method,headers:{Authorization:`Bearer diary-token-${id}`,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined});
  const feed = async (id,cursor) => {
    const response = await api(`/users/${id}/notifications${cursor?`?cursor=${encodeURIComponent(JSON.stringify(cursor))}`:''}`,id);
    assert.equal(response.status,200); return response.json();
  };
  const reservations = [];
  for (const [user,pet] of [[801,801],[801,802],[803,803]]) {
    const response = await api('/reservations',user,'POST',{pet_id:pet,store_id:801,store_name:'알림장 유치원',start_date:'2099-01-01',end_date:'2099-01-01'});
    assert.equal(response.status,201); const reservation = await response.json();
    assert.equal((await api(`/reservations/${reservation.reservation_id}/confirm`,802,'PATCH')).status,200);
    reservations.push(reservation);
  }
  const baseline = await feed(801), otherBaseline = await feed(803), ownerBaseline = await feed(802);
  const diaries = [];
  for (const reservation of reservations) {
    const response = await api(`/reservations/${reservation.reservation_id}/diaries`,802,'POST',{content:'오늘 잘 지냈어요'});
    assert.equal(response.status,200); diaries.push(await response.json());
  }
  const result = await feed(801,baseline.cursor);
  assert.equal(result.notifications.length,2,'같은 방의 알림장은 예약별 개별 이벤트로 보존');
  for (let index=0; index<2; index++) {
    const item = result.notifications[index];
    assert.equal(item.type,'diary','알림장은 일반 chat으로 분류하지 않는다');
    assert.equal(item.reservation_id,reservations[index].reservation_id);
    assert.equal(item.diary_id,diaries[index].diary_id);
    assert.equal(item.pet_name,['초코','보리'][index]);
    assert.equal(item.store_name,'알림장 유치원');
    assert.equal(item.can_write,false,'고객에게 작성 권한을 부여하지 않는다');
    assert.equal(item.body,`${item.pet_name}의 새 알림장이 도착했어요.\n확정예약. 알림장에서 확인해주세요.`);
  }
  const messages = await db.prepare("SELECT content,event_type,reservation_id,diary_id FROM chat_messages WHERE room_id=801 AND event_type='diary' ORDER BY message_id").all();
  assert.equal(messages.results.length,2);
  assert.equal(messages.results[0].content,result.notifications[0].body,'회색 채팅 안내도 동일한 동적 문구');
  assert.equal(messages.results[0].diary_id,diaries[0].diary_id);
  const others = await feed(803,otherBaseline.cursor);
  assert.equal(others.notifications.length,1);
  assert.equal(others.notifications[0].pet_name,'다른 아이');
  assert.deepEqual((await feed(802,ownerBaseline.cursor)).notifications,[],'사장님에게 고객 알림장 도착 알림을 중복 전달하지 않는다');
  assert.equal((await api(`/reservations/${reservations[0].reservation_id}/diaries`,803)).status,403,'다른 계정의 알림장 접근 금지');
  assert.equal((await api('/users/801/notifications',803)).status,403);
  await db.prepare("INSERT INTO chat_messages(room_id,sender_id,message_type,content,event_type,reservation_id,diary_id) VALUES(801,0,'AUTO','잘못 연결된 문맥','diary',?,?)")
    .bind(reservations[2].reservation_id,diaries[2].diary_id).run();
  assert.deepEqual((await feed(801,result.cursor)).notifications,[],'방과 다른 계정의 예약 메타데이터는 노출하지 않는다');
  assert.deepEqual((await feed(803,others.cursor)).notifications,[],'cursor 이후 재전달하지 않는다');
  console.log('PASS diary notification: 동적 이름·문구, 예약별 개별 알림장 문맥, 고객 읽기 전용, 계정 격리');
} finally { await mf.dispose(); }
