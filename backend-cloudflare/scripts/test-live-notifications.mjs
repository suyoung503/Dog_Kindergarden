#!/usr/bin/env node
// 격리 Miniflare/D1에서 앱 사용 중 변경 알림 수신자와 영속 피드를 검증한다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';
import WebSocket from 'ws';
const backend = fileURLToPath(new URL('..', import.meta.url));
const result = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'live-notifications', modules: true, script: result.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
const sockets = [];
async function until(predicate, label) {
  const deadline = Date.now() + 2000;
  while (!predicate()) {
    assert.ok(Date.now() < deadline, label);
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner,is_admin) VALUES
    (901,'live-customer','초코 보호자',0,0),(902,'live-owner','사장님',1,0),(903,'live-admin','운영자',0,1),
    (904,'live-unrelated','다른 가게 사장님',1,0),(905,'live-deleted-admin','탈퇴 운영자',0,1);
    UPDATE users SET deleted_at = CURRENT_TIMESTAMP WHERE user_id = 905;
    INSERT INTO stores(store_id,name,store_key,owner_id,partner_status) VALUES
    (901,'초코 유치원','live-store',902,'ACTIVE'),(902,'신청 유치원','live-claim',NULL,'NONE'),
    (903,'다른 유치원','live-other',904,'ACTIVE');
    INSERT INTO chat_rooms(room_id,user_id,store_id) VALUES(901,901,901),(902,901,903);`.replace(/\n/g, ' '));
  for (const id of [901,902,903,904]) await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(`live-token-${id}`).digest('hex'), id).run();
  const api = (path,id,method='GET',body) => mf.dispatchFetch(`http://localhost/api${path}`,{
    method, headers:{Authorization:`Bearer live-token-${id}`,...(body ? {'Content-Type':'application/json'} : {})},
    body:body ? JSON.stringify(body) : undefined,
  });
  const feed = async (id,cursor) => {
    const res = await api(`/users/${id}/notifications${cursor ? `?cursor=${encodeURIComponent(JSON.stringify(cursor))}` : ''}`,id);
    assert.equal(res.status,200);return res.json();
  };
  const connect = async id => {
    const url = new URL('/api/realtime',await mf.ready);url.protocol='ws:';
    // 쿼리의 임의 사용자·역할은 서버 수신자 결정에 사용하면 안 된다.
    url.search='user_id=903&is_admin=1&room_id=901';
    const ws = new WebSocket(url,{headers:{Authorization:`Bearer live-token-${id}`}});sockets.push(ws);
    const messages=[];ws.on('message',data=>messages.push(JSON.parse(data)));
    await until(()=>messages.some(m=>m.type==='ready'),'ready timeout');
    return messages;
  };
  const streams = Object.fromEntries(await Promise.all([901,902,903,904].map(async id=>[id,await connect(id)])));
  const changes = id => streams[id].filter(m=>m.type==='change');
  let customer = await feed(901), owner = await feed(902), admin = await feed(903);
  assert.equal((await api('/chatrooms/901/messages',902,'POST',{content:'내일 뵐게요'})).status,201);
  await until(()=>changes(901).some(m=>m.scope==='chat'),'chat customer invalidation');
  customer = await feed(901,customer.cursor);
  const customerChat = customer.notifications.find(n=>n.type==='chat');
  assert.equal(customerChat.title,'초코 유치원','보호자에게 가게 이름');
  assert.match(customerChat.body,/새 채팅.*내일 뵐게요/,'명확한 새 채팅 안내 + 내용');
  assert.equal(customerChat.room_id,901);assert.equal(customerChat.as_owner,false);
  assert.equal((await api('/chatrooms/901/messages',901,'POST',{content:'감사합니다'})).status,201);
  await until(()=>changes(902).some(m=>m.scope==='chat'),'chat owner invalidation');
  owner = await feed(902,owner.cursor);
  const ownerChat=owner.notifications.find(n=>n.type==='chat');
  assert.equal(ownerChat.title,'초코 보호자','사장님에게 고객 이름');
  assert.match(ownerChat.body,/새 채팅.*감사합니다/);
  assert.equal(ownerChat.room_id,901);assert.equal(ownerChat.as_owner,true);
  assert.equal(changes(903).length,0);assert.equal(changes(904).length,0,'다른 가게로 채팅 이벤트 유출 금지');
  const deniedCount=changes(901).length;
  assert.equal((await api('/chatrooms/901/messages',904,'POST',{content:'금지'})).status,403);
  assert.equal(changes(901).length,deniedCount,'실패한 쓰기는 invalidate 금지');
  assert.equal((await api('/stores/claim',901,'POST',{store_key:'live-claim'})).status,403);
  assert.equal(changes(903).length,0,'미권한 신청 실패는 알림 금지');
  const claim=await api('/stores/claim',902,'POST',{store_key:'live-claim'});
  assert.equal(claim.status,201);
  const application=await claim.json();
  await until(()=>changes(903).some(m=>m.scope==='owner_application'),'가게 등록 요청은 60초 기다리지 않고 기존 admin에게 즉시 change');
  admin=await feed(903,admin.cursor);
  const notice=admin.notifications.find(n=>n.type==='owner_application');
  assert.equal(notice.application_id,application.application_id);assert.equal(notice.title,'새 가게 등록 요청');
  assert.match(notice.body,/신청 유치원/);
  assert.equal(changes(904).length,0,'다른 가게에 신청 이벤트 유출 금지');
  const adminCount=changes(903).length;
  assert.equal((await api('/stores/claim',902,'POST',{store_key:'live-claim'})).status,200);
  assert.equal(changes(903).length,adminCount,'동일 PENDING 재요청은 새 신청 알림이 아니다');
  assert.deepEqual((await feed(903,admin.cursor)).notifications,[]);
  assert.equal((await api('/users/903/notifications',904)).status,403);
  const conversation=await (await api('/support/conversation',901,'POST')).json();
  assert.equal((await api(`/support/conversations/${conversation.conversation_id}/messages`,901,'POST',{content:'도와주세요'})).status,201);
  await until(()=>changes(903).some(m=>m.scope==='support'),'사용자 문의는 운영자에게 즉시 change');
  assert.equal(changes(904).length,0);
  const beforeReply=changes(901).length;
  assert.equal((await api(`/support/conversations/${conversation.conversation_id}/messages`,903,'POST',{content:'확인할게요'})).status,201);
  await until(()=>changes(901).length>beforeReply,'운영자 답변은 대화 소유자에게 즉시 change');
  const customerChanges=changes(901).length;
  assert.equal((await api(`/support/conversations/${conversation.conversation_id}/messages`,904,'POST',{content:'다른 계정'})).status,403);
  assert.equal(changes(901).length,customerChanges);assert.equal(changes(904).length,0);
  // 세션을 다시 만들지 않아도 DB 권한 변경은 다음 수신자 조회에 즉시 반영한다.
  await db.exec("UPDATE users SET is_admin = 0 WHERE user_id = 903; INSERT INTO stores(store_id,name,store_key,partner_status) VALUES(904,'두번째 신청','live-claim-2','NONE');");
  const demotedAdminCount=changes(903).length;
  assert.equal((await api('/stores/claim',902,'POST',{store_key:'live-claim-2'})).status,201);
  assert.equal(changes(903).length,demotedAdminCount,'기존 소켓이 있어도 admin 권한 해제 후 신청 이벤트 금지');
  const demotedFeed=await feed(903,admin.cursor);
  assert.ok(!demotedFeed.notifications.some(n=>n.type==='owner_application'),'피드도 현재 DB admin 권한을 따름');
  assert.equal((await api('/owner-applications',903)).status,403);
  const applicantFeed=await feed(902,owner.cursor);
  assert.ok(!applicantFeed.notifications.some(n=>n.type==='owner_application'),'신청자에 운영자용 신청 알림 권한 추가 금지');
  assert.equal((await api('/users/902/store-owner-applications',902)).status,200,'신청자의 기존 신청 이력 권한은 보존');
  console.log('PASS live notifications: 역할별 채팅 이름/문구/room, 신청·문의 즉시 DO invalidation, 권한/가게 격리, 실패·중복 신청 무발행');
} finally { for(const ws of sockets)ws.terminate();await mf.dispose(); }
