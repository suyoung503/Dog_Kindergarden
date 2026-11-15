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

  // 안내 저장만 실패해도 게시 본문이 남으면 앱의 재시도가 같은 글을 중복 게시한다.
  const reservationId = reservations[0].reservation_id;
  const beforeFailure = await db.prepare(`SELECT
    (SELECT COUNT(*) FROM diaries) AS diaries,
    (SELECT COUNT(*) FROM chat_messages) AS messages`).first();
  const failureBaseline = await feed(801);
  await db.prepare(`CREATE TRIGGER fail_diary_event BEFORE INSERT ON chat_messages
    WHEN NEW.event_type='diary' BEGIN SELECT RAISE(ABORT,'fixture diary event failure'); END`).run();
  try {
    assert.equal((await api(`/reservations/${reservationId}/diaries`,802,'POST',{content:'재시도할 알림장'})).status,500);
    const afterFailure = await db.prepare(`SELECT
      (SELECT COUNT(*) FROM diaries) AS diaries,
      (SELECT COUNT(*) FROM chat_messages) AS messages`).first();
    console.log('diary event failure counts:', { before: beforeFailure, after: afterFailure });
    assert.deepEqual(afterFailure,beforeFailure,'안내 저장 실패 시 본문과 안내 모두 남지 않아야 한다');
    assert.deepEqual((await feed(801,failureBaseline.cursor)).notifications,[],'게시 실패를 도착 알림으로 표시하지 않는다');
  } finally { await db.exec('DROP TRIGGER fail_diary_event'); }
  const retryResponse = await api(`/reservations/${reservationId}/diaries`,802,'POST',{content:'재시도할 알림장'});
  assert.equal(retryResponse.status,200);
  const retried = await retryResponse.json();
  const afterRetry = await db.prepare(`SELECT
    (SELECT COUNT(*) FROM diaries) AS diaries,
    (SELECT COUNT(*) FROM chat_messages) AS messages`).first();
  assert.deepEqual(afterRetry,{diaries:beforeFailure.diaries+1,messages:beforeFailure.messages+1},'재시도는 본문1개·안내1개만 추가한다');
  const retryEvents = (await feed(801,failureBaseline.cursor)).notifications;
  assert.equal(retryEvents.length,1);
  assert.equal(retryEvents[0].diary_id,retried.diary_id);
  assert.equal(retryEvents[0].reservation_id,reservationId);
  assert.equal(retryEvents[0].pet_name,'초코');
  console.log('PASS diary atomic failure and retry: 실패 rollback·재시도1건·실제 게시물 알림 연결');

  await db.prepare(`CREATE TRIGGER fail_diary_body BEFORE INSERT ON diaries
    BEGIN SELECT RAISE(ABORT,'fixture diary body failure'); END`).run();
  try {
    assert.equal((await api(`/reservations/${reservationId}/diaries`,802,'POST',{content:'저장 실패할 본문'})).status,500);
    const afterBodyFailure = await db.prepare(`SELECT
      (SELECT COUNT(*) FROM diaries) AS diaries,
      (SELECT COUNT(*) FROM chat_messages) AS messages`).first();
    assert.deepEqual(afterBodyFailure,afterRetry,'본문 저장 실패도 본문·안내를 남기지 않는다');
  } finally { await db.exec('DROP TRIGGER fail_diary_body'); }
  console.log('PASS diary body failure: 본문 실패 시 안내도 없음');

  const parallelResponses = await Promise.all(Array.from({length:10},(_,index) =>
    api(`/reservations/${reservationId}/diaries`,802,'POST',{content:`동시 게시-${index}`})));
  assert.ok(parallelResponses.every(response=>response.status===200));
  const parallelEntries = await Promise.all(parallelResponses.map(response=>response.json()));
  const parallelIds = parallelEntries.map(entry=>entry.diary_id);
  assert.equal(new Set(parallelIds).size,10,'서로 다른 게시10개는 합치지 않는다');
  const linked = await db.prepare(`SELECT d.diary_id,d.content,m.diary_id AS notified_diary_id,m.reservation_id,m.room_id
    FROM diaries d LEFT JOIN chat_messages m ON m.diary_id=d.diary_id AND m.event_type='diary'
    WHERE d.diary_id IN (${parallelIds.map(()=>'?').join(',')})`).bind(...parallelIds).all();
  assert.equal(linked.results.length,10);
  for (const [index,entry] of parallelEntries.entries()) {
    assert.equal(entry.content,`동시 게시-${index}`);
    const row = linked.results.find(row=>row.diary_id===entry.diary_id);
    assert.equal(row.notified_diary_id,entry.diary_id);
    assert.equal(row.reservation_id,reservationId);
    assert.equal(row.room_id,801);
  }
  console.log('PASS diary concurrent posts: 별도 본문10개·안내10개·각 diary_id 연결');

  // 기존의 채팅방 없는 확정 예약도 게시할 수 있고 다른 고객 방에 안내하지 않는다.
  await db.exec("INSERT INTO stores(store_id,name,store_key,owner_id,partner_status) VALUES(804,'방 없는 가게','diary-no-room',802,'ACTIVE')");
  const noRoomReservation = await db.prepare(`INSERT INTO reservations
    (user_id,pet_id,store_id,start_date,end_date,reservation_type,status)
    VALUES(803,803,804,'2099-01-01','2099-01-01','NORMAL','CONFIRMED')`).run();
  const messagesBeforeNoRoom = (await db.prepare('SELECT COUNT(*) AS count FROM chat_messages').first()).count;
  const noRoomResponse = await api(`/reservations/${noRoomReservation.meta.last_row_id}/diaries`,802,'POST',{content:'방 없는 예약의 기록'});
  assert.equal(noRoomResponse.status,200);
  const noRoomEntry = await noRoomResponse.json();
  assert.equal(noRoomEntry.reservation_id,noRoomReservation.meta.last_row_id);
  assert.equal(noRoomEntry.content,'방 없는 예약의 기록');
  assert.deepEqual(noRoomEntry.photos,[]);
  assert.equal((await db.prepare('SELECT COUNT(*) AS count FROM chat_messages').first()).count,messagesBeforeNoRoom);
  assert.equal((await api(`/reservations/${reservationId}/diaries`,801,'POST',{content:'보호자 작성 금지'})).status,403);
  assert.equal((await api(`/reservations/${reservationId}/diaries`,803,'POST',{content:'다른 고객 작성 금지'})).status,403);
  assert.equal((await api(`/reservations/${reservationId}/diaries`,802,'POST',{content:'  '})).status,400);
  console.log('PASS diary compatibility: 채팅방 없음·빈 사진·기존 권한·빈 본문 거절 유지');
  console.log('PASS diary notification: 동적 이름·문구, 예약별 개별 알림장 문맥, 고객 읽기 전용, 계정 격리, 게시 원자성');
} finally { await mf.dispose(); }
