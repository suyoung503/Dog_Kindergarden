#!/usr/bin/env node
// 격리된 실제 D1/Worker/DO만 사용한다. 운영 데이터·토큰은 읽지 않는다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';
import WebSocket from 'ws';
const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'owner-application-rejection-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'owner application rejection local test' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
const sockets = [];
const until = async predicate => {
  const end = Date.now() + 4000;
  while (!predicate()) { assert.ok(Date.now() < end, '실제 WebSocket change 대기 시간 초과'); await new Promise(r => setTimeout(r, 10)); }
};
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner,is_admin) VALUES
    (901,'rejection-owner','신청자',1,0),(902,'rejection-admin','관리자',0,1),
    (903,'rejection-other','다른 계정',1,0),(904,'rejection-admin-owner','관리자 신청자',1,1);
    INSERT INTO stores(store_id,name,store_key,partner_status) VALUES(901,'거절 테스트','rejection-store','PENDING'),(902,'관리자 신청 가게','rejection-admin-store','PENDING');
    INSERT INTO store_owner_applications(application_id,user_id,store_id,status) VALUES
    (901,901,901,'PENDING'),(902,904,902,'PENDING'),(903,901,901,'APPROVED'),(904,901,901,'REJECTED');`.replace(/\n/g, ' '));
  for (const id of [901,902,903,904]) await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(`rejection-token-${id}`).digest('hex'), id).run();
  const api = (path,id,method='GET',body) => mf.dispatchFetch(`http://localhost/api${path}`,{
    method,headers:{Authorization:`Bearer rejection-token-${id}`,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,
  });
  const feed = async(id,cursor,bootstrap=true) => {
    const response=await api(`/users/${id}/notifications${cursor?`?cursor=${encodeURIComponent(JSON.stringify(cursor))}`:bootstrap?'?bootstrap=1':''}`,id);
    assert.equal(response.status,200); return response.json();
  };
  const connect=async id=>{
    const url=new URL('/api/realtime',await mf.ready);url.protocol='ws:';
    const ws=new WebSocket(url,{headers:{Authorization:`Bearer rejection-token-${id}`}});sockets.push(ws);
    const events=[];ws.on('message',v=>events.push(JSON.parse(v)));await until(()=>events.some(e=>e.type==='ready'));return events;
  };
  const applicant=await connect(901), admin=await connect(902), stranger=await connect(903), adminApplicant=await connect(904);
  const before=await feed(901);
  assert.equal((await api('/owner-applications/901/reject',902,'PATCH',{user_id:903,store_name:'위조'})).status,200);
  await until(()=>applicant.some(e=>e.scope==='owner_application'&&e.application_id===901));
  const rejected=await feed(901,before.cursor);
  assert.equal(rejected.notifications.filter(n=>n.type==='owner_application_rejected').length,1,'최초 거절은 신청자의 영속 알림에 저장되어야 한다');
  const item=rejected.notifications.find(n=>n.type==='owner_application_rejected');
  assert.equal((await db.prepare('SELECT partner_status FROM stores WHERE store_id=901').first()).partner_status,'NONE');
  assert.equal(item.application_id,901);assert.equal(item.title,'가게 등록 요청이 거절되었어요');
  assert.ok(item.body.includes('거절 테스트'));assert.ok(item.body.includes('신청 내역'));
  assert.deepEqual((await feed(901,rejected.cursor)).notifications,[],'동일 축의 증분 중복 없음');
  assert.equal((await api('/owner-applications/901/reject',902,'PATCH')).status,200);
  assert.equal((await api('/owner-applications/903/reject',902,'PATCH')).status,409);
  assert.equal((await api('/owner-applications/999/reject',902,'PATCH')).status,404);
  assert.equal((await api('/owner-applications/902/reject',903,'PATCH')).status,403);
  assert.equal((await api('/owner-applications/904/reject',902,'PATCH')).status,200);
  await new Promise(r=>setTimeout(r,75));
  assert.equal(applicant.filter(e=>e.type==='change').length,1,'중복·과거 거절·실패는 전경 이벤트 미발행');
  for(const events of [admin,stranger,adminApplicant])assert.equal(events.filter(e=>e.type==='change').length,0,'심사자·위조 수신자·다른 신청자에게 누출 금지');
  assert.equal((await feed(903)).notifications.filter(n=>n.type==='owner_application_rejected').length,0);
  assert.equal((await api('/users/901/notifications?bootstrap=1',903)).status,403);
  assert.equal((await api('/users/901/notifications?cursor='+encodeURIComponent(JSON.stringify({owner_application_rejection_id:-1})),901)).status,400);
  const legacy={...before.cursor};delete legacy.owner_application_rejection_id;
  assert.equal((await feed(901,legacy)).notifications.filter(n=>n.type==='owner_application_rejected').length,1,'새 축 없는 배포 전 cursor는 신규 거절을 버리지 않는다');
  assert.deepEqual((await feed(901,undefined,false)).notifications,[],'bootstrap을 모르는 구버전 초기 feed 동작 보존');
  assert.equal((await feed(901)).notifications.filter(n=>n.type==='owner_application_rejected').length,1,'기존 과거 거절 임의 backfill 금지');
  const adminBefore=await feed(904);
  assert.equal((await api('/owner-applications/902/reject',902,'PATCH')).status,200);
  await until(()=>adminApplicant.some(e=>e.scope==='owner_application'&&e.application_id===902));
  assert.equal((await feed(904,adminBefore.cursor)).notifications.filter(n=>n.type==='owner_application_rejected').length,1,'관리자 겸직 신청자도 자기 거절을 받는다');
  console.log('PASS HTTP→DB→DO WebSocket→feed: 최초 거절·중복·권한·실패·수신자 격리·관리자 겸직·구 cursor');

  // 실제 SQLite trigger 실패로 상태와 이벤트가 함께 rollback되는지 검증한다.
  await db.exec("UPDATE stores SET partner_status='PENDING' WHERE store_id=901; INSERT INTO store_owner_applications(application_id,user_id,store_id) VALUES(905,901,901); CREATE TRIGGER test_fail_rejection BEFORE INSERT ON owner_application_rejections WHEN NEW.application_id=905 BEGIN SELECT RAISE(ABORT,'test rejection event failure'); END;");
  const failed=await api('/owner-applications/905/reject',902,'PATCH');assert.equal(failed.status,500);
  assert.equal((await db.prepare('SELECT status FROM store_owner_applications WHERE application_id=905').first()).status,'PENDING');
  assert.equal((await db.prepare('SELECT partner_status FROM stores WHERE store_id=901').first()).partner_status,'PENDING');
  assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM owner_application_rejections WHERE application_id=905').first()).n,0);
  await db.exec('DROP TRIGGER test_fail_rejection;');
  await new Promise(r=>setTimeout(r,50));assert.equal(applicant.filter(e=>e.type==='change').length,1,'트랜잭션 실패는 전경 무발행');
  console.log('PASS 실제 D1 batch 실패: 상태·이벤트 원자성 및 무발행');

  // max snapshot 이후에 생성된 거절은 이번 응답에 섞이지 않고 다음 증분에서 복구한다.
  const nodeBundle=await build({entryPoints:[`${backend}/src/index.ts`],bundle:true,write:false,format:'esm',platform:'node',plugins:[{name:'do-base',setup(b){b.onResolve({filter:/^cloudflare:workers$/},()=>({path:'workers',namespace:'stub'}));b.onLoad({filter:/.*/,namespace:'stub'},()=>({contents:'export class DurableObject {}'}));}}]});
  const {default:worker}=await import(`data:text/javascript;base64,${Buffer.from(nodeBundle.outputFiles[0].text).toString('base64')}`);
  const snapshotBefore=await feed(901);
  const snapshotDB=new Proxy(db,{get(t,k){if(k!=='prepare')return typeof t[k]==='function'?t[k].bind(t):t[k];return sql=>{
    const statement=t.prepare(sql);if(!sql.includes('MAX(rejection_id)'))return statement;
    return new Proxy(statement,{get(s,m){if(m!=='first')return typeof s[m]==='function'?s[m].bind(s):s[m];return async(...args)=>{
      const max=await s.first(...args);assert.equal((await api('/owner-applications/905/reject',902,'PATCH')).status,200);return max;
    };}});
  };}});
  const response=await worker.fetch(new Request(`http://localhost/api/users/901/notifications?cursor=${encodeURIComponent(JSON.stringify(snapshotBefore.cursor))}`,{headers:{Authorization:'Bearer rejection-token-901'}}),{DB:snapshotDB},{waitUntil(){}});
  assert.equal(response.status,200);const snapshot=await response.json();assert.deepEqual(snapshot.notifications,[]);
  const catchup=await feed(901,snapshot.cursor);assert.deepEqual(catchup.notifications.map(n=>n.application_id),[905]);assert.deepEqual((await feed(901,catchup.cursor)).notifications,[]);
  console.log('PASS snapshot max bound 및 다음 증분 1회 복구');

  await db.batch(Array.from({length:105},(_,i)=>db.prepare('INSERT INTO store_owner_applications(application_id,user_id,store_id,status) VALUES(?,901,901,\'REJECTED\')').bind(1000+i)));
  await db.batch(Array.from({length:105},(_,i)=>db.prepare('INSERT INTO owner_application_rejections(application_id,user_id,store_name) VALUES(?,901,\'최근 거절\')').bind(1000+i)));
  const bulk=await feed(901);assert.equal(bulk.notifications.length,100);assert.equal(bulk.is_bootstrap,true);
  assert.deepEqual((await feed(901,bulk.cursor)).notifications,[],'bootstrap에서 생략된 오래된 거절이 신규로 살아나지 않는다');
  await db.prepare('DELETE FROM store_owner_applications WHERE application_id=?').bind(1000).run();
  assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM owner_application_rejections WHERE application_id=1000').first()).n,0,'실제 FK ON DELETE CASCADE: 신청 이력 retention 시 이벤트도 정리');
  assert.equal((await api('/users/901/account',901,'DELETE')).status,200);
  assert.equal((await db.prepare('SELECT COUNT(*) AS n FROM owner_application_rejections WHERE user_id=901').first()).n,0,'실제 탈퇴 경로에서 이벤트 정리');
  console.log('PASS bootstrap 100건 및 신청 FK cascade/실제 탈퇴 cleanup');

  const ios=await readFile(`${backend}/../Dog_kindergarden/Dog_kindergarden/Views/Notification/AppNotificationService.swift`,'utf8');
  assert.match(ios,/case "owner_application_rejected":\s*return \.myStoreApplication/,'거절은 심사 목록 대신 본인 신청 내역 딥링크');
  const root=await readFile(`${backend}/../Dog_kindergarden/Dog_kindergarden/Views/RootView.swift`,'utf8');
  assert.match(root,/case \.myStoreApplication:\s*router.go\(\.myStoreApplication\)/);
  assert.match(root,/case \.myStoreApplication:\s*MyPageView\(openStoreApplicationOnAppear: true\)/);
  const myStores=await readFile(`${backend}/../Dog_kindergarden/Dog_kindergarden/Views/MyPage/MyStoreSheet.swift`,'utf8');
  assert.match(myStores,/applications\.filter \{ \$0\.status == "REJECTED" \}/,'신청 내역 sheet는 거절 상태를 숨기지 않는다');
  assert.match(myStores,/pendingSection\s+rejectedSection\s+searchSection/);
  console.log('PASS iOS 소스 contract: 거절 → 본인 MyPage 신청 sheet와 거절 이력 표시');
} finally { for(const ws of sockets)ws.terminate();await mf.dispose(); }
