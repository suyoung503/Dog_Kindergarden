#!/usr/bin/env node
// 실제 예약 HTTP/DO WebSocket과 격리 D1을 사용한다. 운영 데이터·토큰에는 접근하지 않는다.
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
const options = { name: 'notification-bootstrap-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'notification bootstrap local test' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
const sockets = [];
const until = async predicate => {
  const deadline = Date.now() + 4000;
  while (!predicate()) {
    assert.ok(Date.now() < deadline, '실제 Bearer WebSocket ready/change 대기 시간 초과');
    await new Promise(resolve => setTimeout(resolve, 10));
  }
};
try {
  const db = await mf.getD1Database('DB');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner) VALUES(801,'bootstrap-customer','보호자',0),(802,'bootstrap-owner','사장님',1),(803,'bootstrap-stranger','관계없음',0),(804,'bootstrap-admin','운영자',0); UPDATE users SET is_admin=1 WHERE user_id=804;
    INSERT INTO stores(store_id,name,store_key,owner_id,partner_status) VALUES(801,'예약 테스트','bootstrap-store',802,'ACTIVE');
    INSERT INTO pets(pet_id,user_id,name) VALUES(801,801,'초코');
    INSERT INTO chat_rooms(room_id,user_id,store_id) VALUES(801,801,801);`.replace(/\n/g, ' '));
  for (const id of [801,802,803,804]) await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(`bootstrap-token-${id}`).digest('hex'), id).run();
  const api = (path, id, method = 'GET', body) => mf.dispatchFetch(`http://localhost/api${path}`, {
    method, headers: { Authorization: `Bearer bootstrap-token-${id}`, ...(body ? {'Content-Type':'application/json'} : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const feed = async (id, cursor) => {
    const response = await api(`/users/${id}/notifications${cursor ? `?cursor=${encodeURIComponent(JSON.stringify(cursor))}` : '?bootstrap=1'}`, id);
    assert.equal(response.status, 200); return response.json();
  };
  const reserve = async () => {
    const response = await api('/reservations',801,'POST',{pet_id:801,store_id:801,store_name:'예약 테스트',start_date:'2099-01-01',end_date:'2099-01-01'});
    assert.equal(response.status,201); return response.json();
  };
  const connect = async id => {
    const url = new URL('/api/realtime', await mf.ready); url.protocol = 'ws:';
    const ws = new WebSocket(url,{headers:{Authorization:`Bearer bootstrap-token-${id}`}});
    sockets.push(ws);
    const messages=[]; ws.on('message',data=>messages.push(JSON.parse(data)));
    await until(()=>messages.some(m=>m.type==='ready'));
    return messages;
  };
  const reviewOnly = process.argv.includes('--review-only');
  const reviewCase = process.env.REVIEW_CASE;
  if (!reviewCase || reviewCase === 'admin') {
    await db.exec("INSERT INTO store_owner_applications(user_id,store_id) VALUES(802,801); INSERT INTO support_conversations(conversation_id,user_id) VALUES(801,801); INSERT INTO support_messages(conversation_id,sender_id,sender_role,content) VALUES(801,801,'USER','기존 문의');");
    const baseline = await (await api('/users/804/notifications',804)).json();
    const legacy = await feed(804,{message_id:baseline.cursor.message_id,request_id:baseline.cursor.request_id,canceled_at:baseline.cursor.canceled_at});
    assert.deepEqual(legacy.notifications,[],'운영자 구버전 커서에는 기존 문의/신청을 재노출하지 않는다');
    const restored = await feed(804);
    assert.ok(restored.notifications.some(n=>n.type==='owner_application'),'운영자 bootstrap은 실제 신청 시각 열로 정렬한다');
    assert.ok(restored.notifications.some(n=>n.type==='support'));
    console.log('PASS admin: 구버전 cursor 호환, 운영자 신청/문의 최초 복원');
  }
  if (!reviewCase || reviewCase === 'malformed') {
    for (const cursor of [null,[],1,'cursor',{message_id:'1'},{request_id:-1},{support_message_id:1.5},
      {owner_application_id:{}},{canceled_at:3},{canceled_ids:'1'},{canceled_ids:[1,'2']},{canceled_ids:[-1]},
      {message_id:9007199254740992},{canceled_at:'not-a-timestamp'}]) {
      const response = await api(`/users/801/notifications?cursor=${encodeURIComponent(JSON.stringify(cursor))}`,801);
      assert.equal(response.status,400,`malformed cursor는 SQL/500 대신 400: ${JSON.stringify(cursor)}`);
    }
    assert.deepEqual((await feed(803,{})).notifications,[],'빈 객체 구버전 커서는 유효');
    assert.equal((await api('/users/801/notifications?bootstrap=1',803)).status,403,'다른 사용자 feed 접근 차단');
    console.log('PASS malformed: cursor 구조/축 타입 검증과 계정 격리');
  }
  if (!reviewCase || reviewCase === 'bulk') {
    // 105개의 동초 취소 중 복원에서 잘린 5개도 다음 증분에서 신규 배너로 살아나지 않아야 한다.
    const now = await db.prepare('SELECT CURRENT_TIMESTAMP AS v').first();
    const clockBundle=await build({entryPoints:[`${backend}/src/index.ts`],bundle:true,write:false,format:'esm',platform:'node',
      plugins:[{name:'unused-do-base',setup(builder){
        builder.onResolve({filter:/^cloudflare:workers$/},()=>({path:'workers',namespace:'local-stub'}));
        builder.onLoad({filter:/.*/,namespace:'local-stub'},()=>({contents:'export class DurableObject {}'}));
      }}]});
    const {default:clockWorker}=await import(`data:text/javascript;base64,${Buffer.from(clockBundle.outputFiles[0].text).toString('base64')}`);
    const clockDB=new Proxy(db,{get(target,key){
      if(key!=='prepare')return typeof target[key]==='function'?target[key].bind(target):target[key];
      return sql=>sql==='SELECT CURRENT_TIMESTAMP AS v'?{first:async()=>now}:target.prepare(sql);
    }});
    const bulkFeed=async cursor=>{
      const response=await clockWorker.fetch(new Request(`http://localhost/api/users/802/notifications${cursor?`?cursor=${encodeURIComponent(JSON.stringify(cursor))}`:'?bootstrap=1'}`,
        {headers:{Authorization:'Bearer bootstrap-token-802'}}),{DB:clockDB},{waitUntil(){}});
      assert.equal(response.status,200);return response.json();
    };
    await db.batch(Array.from({length:105},(_,i)=>db.prepare(`INSERT INTO reservations(reservation_id,user_id,pet_id,store_id,reservation_type,status,start_date,end_date,canceled_by,canceled_at)
      VALUES(?,801,801,801,'유치원','CANCELED','2099-01-01','2099-01-01','USER',?)`).bind(2000+i,now.v)));
    const baseline = await bulkFeed();
    assert.equal(baseline.notifications.filter(n=>n.type==='reservation_canceled').length,100);
    assert.deepEqual((await bulkFeed(baseline.cursor)).notifications,[],'bootstrap에서 제외된 동초 취소는 신규 알림이 아니다');
    await db.prepare(`INSERT INTO reservations(reservation_id,user_id,pet_id,store_id,reservation_type,status,start_date,end_date,canceled_by,canceled_at)
      VALUES(2105,801,801,801,'유치원','CANCELED','2099-01-01','2099-01-01','USER',?)`).bind(now.v).run();
    const fresh = await bulkFeed(baseline.cursor);
    assert.deepEqual(fresh.notifications.map(n=>n.reservation_id),[2105],'같은 초에 새로 생긴 취소는 복구');
    assert.deepEqual((await bulkFeed(fresh.cursor)).notifications,[]);
    console.log('PASS bulk: 100개 초과 동초 취소 초기 복원/신규 복구/중복 없음');
  }
  if (!reviewCase || reviewCase === 'snapshot') {
    await db.exec("INSERT OR IGNORE INTO support_conversations(conversation_id,user_id) VALUES(801,801);");
    const nodeBundle=await build({entryPoints:[`${backend}/src/index.ts`],bundle:true,write:false,format:'esm',platform:'node',
      plugins:[{name:'unused-do-base',setup(builder){
        builder.onResolve({filter:/^cloudflare:workers$/},()=>({path:'workers',namespace:'local-stub'}));
        builder.onLoad({filter:/.*/,namespace:'local-stub'},()=>({contents:'export class DurableObject {}'}));
      }}]});
    const {default:worker}=await import(`data:text/javascript;base64,${Buffer.from(nodeBundle.outputFiles[0].text).toString('base64')}`);
    for (const id of [804,801,802]) {
      const before=await feed(id);
      const snapshotDB=new Proxy(db,{get(target,key){
        if(key!=='prepare')return typeof target[key]==='function'?target[key].bind(target):target[key];
        return sql=>{
          const statement=target.prepare(sql);
          const race=(id===802&&sql.includes('MAX(reservation_id)'))?'reservation'
            :((id===804||id===801)&&sql.includes('MAX(message_id)')&&sql.includes('FROM support_messages'))?'support'
            :(id===804&&sql.includes('MAX(application_id)'))?'application':undefined;
          if(!race)return statement;
          return new Proxy(statement,{get(stmt,method){
            if(method!=='first')return typeof stmt[method]==='function'?stmt[method].bind(stmt):stmt[method];
            return async(...args)=>{
              const snapshot=await stmt.first(...args);
              if(race==='reservation')await reserve();
              if(race==='support')await db.exec(`INSERT INTO support_messages(conversation_id,sender_id,sender_role,content) VALUES(801,${id===804?801:804},'${id===804?'USER':'ADMIN'}','snapshot 이후 문의/답장');`);
              if(race==='application')await db.exec("INSERT INTO stores(store_id,name,store_key) VALUES(901,'경쟁 등록','snapshot-store'); INSERT INTO store_owner_applications(user_id,store_id) VALUES(802,901);");
              return snapshot;
            };
          }});
        };
      }});
      const response=await worker.fetch(new Request(`http://localhost/api/users/${id}/notifications?cursor=${encodeURIComponent(JSON.stringify(before.cursor))}`,
        {headers:{Authorization:`Bearer bootstrap-token-${id}`}}),{DB:snapshotDB},{waitUntil(){}});
      assert.equal(response.status,200);
      const snapshot=await response.json();
      assert.deepEqual(snapshot.notifications,[],`${id}의 snapshot 상한 이후 이벤트는 현재 응답에 섞지 않는다`);
      const recovered=await feed(id,snapshot.cursor);
      assert.deepEqual(recovered.notifications.map(n=>n.type).sort(),id===804?['owner_application','support']:id===801?['support']:['reservation_request'],'snapshot 직후 생성 이벤트는 다음 증분에서 1회 복구');
      assert.deepEqual((await feed(id,recovered.cursor)).notifications,[],'snapshot 증분 중복 없음');
    }
    console.log('PASS snapshot: 운영자/고객 문의, 가게 신청, 실제 예약 요청 상한과 다음 증분 복구');
  }
  if (!reviewCase || reviewCase === 'cancel-race') {
    const nodeBundle=await build({entryPoints:[`${backend}/src/index.ts`],bundle:true,write:false,format:'esm',platform:'node',
      plugins:[{name:'unused-do-base',setup(builder){
        builder.onResolve({filter:/^cloudflare:workers$/},()=>({path:'workers',namespace:'local-stub'}));
        builder.onLoad({filter:/.*/,namespace:'local-stub'},()=>({contents:'export class DurableObject {}'}));
      }}]});
    const {default:worker}=await import(`data:text/javascript;base64,${Buffer.from(nodeBundle.outputFiles[0].text).toString('base64')}`);
    for (const bootstrap of (process.env.CANCEL_RACE_BOOTSTRAP_ONLY ? [true] : [false,true])) {
      const existing=await reserve(), before=await feed(802);
      const day=bootstrap?'02':'01';
      const earlier=`2098-01-${day} 00:00:00`,later=`2098-01-${day} 00:00:01`;
      let raced;
      const snapshotDB=new Proxy(db,{get(target,key){
        if(key!=='prepare')return typeof target[key]==='function'?target[key].bind(target):target[key];
        return sql=>{
          if(bootstrap&&sql==='SELECT CURRENT_TIMESTAMP AS v')return {first:async()=>({v:`2098-01-${day} 00:00:02`})};
          const statement=target.prepare(sql);
          if(!sql.includes('MAX(reservation_id)'))return statement;
          return new Proxy(statement,{get(stmt,method){
            if(method!=='first')return typeof stmt[method]==='function'?stmt[method].bind(stmt):stmt[method];
            return async(...args)=>{
              const snapshot=await stmt.first(...args);
              raced=await reserve();
              for(const reservation of [raced,existing])assert.equal((await api(`/reservations/${reservation.reservation_id}/cancel`,801,'PATCH')).status,200);
              await db.prepare('UPDATE reservations SET canceled_at=? WHERE reservation_id=?').bind(earlier,raced.reservation_id).run();
              await db.prepare('UPDATE reservations SET canceled_at=? WHERE reservation_id=?').bind(later,existing.reservation_id).run();
              return snapshot;
            };
          }});
        };
      }});
      const response=await worker.fetch(new Request(`http://localhost/api/users/802/notifications${bootstrap?'?bootstrap=1':`?cursor=${encodeURIComponent(JSON.stringify(before.cursor))}`}`,
        {headers:{Authorization:'Bearer bootstrap-token-802'}}),{DB:snapshotDB},{waitUntil(){}});
      assert.equal(response.status,200);
      const snapshot=await response.json(),catchup=await feed(802,snapshot.cursor);
      const seen=[...snapshot.notifications,...catchup.notifications].filter(n=>n.type==='reservation_canceled').map(n=>n.reservation_id);
      for(const reservation of [raced,existing])assert.equal(seen.filter(id=>id===reservation.reservation_id).length,1,`${bootstrap?'bootstrap':'증분'}: maxRes 이후 새 예약 취소를 더 늦은 기존 예약 취소가 영구 누락시키지 않는다`);
      assert.deepEqual(catchup.notifications,[],'취소축은 실제 읽은 timestamp/동초 ID로 전진해 재전달하지 않는다');
      assert.deepEqual((await feed(802,catchup.cursor)).notifications,[]);
    }
    console.log('PASS cancellation snapshot race: maxRes 이후 신규 예약 취소와 늦은 기존 예약 취소, 증분/최초 복원 유실 없음');
  }
  if (!reviewOnly && !process.argv.includes('--cancel-only')) {
    const customerEvents=await connect(801), ownerEvents=await connect(802), unrelatedEvents=await connect(803);
    // 105개의 과거 시스템 안내가 있어도 최초 알림함 복원은 최근 100개를 넘지 않는다.
    await db.batch(Array.from({length:105},(_,i)=>db.prepare(`INSERT INTO chat_messages(room_id,sender_id,message_type,content,event_type,reservation_id,created_at)
      VALUES(801,0,'AUTO',?,'reservation_submitted',?,'2020-01-01 00:00:00')`).bind(`과거 안내 ${i}`,1000+i)));
    const first=await reserve(); // 첫 feed 전에 성공한 실제 예약: 기존 서버는 이 이벤트를 영구히 버린다.
    await until(()=>customerEvents.some(e=>e.scope==='reservation'&&e.reservation_id===first.reservation_id)
      &&ownerEvents.some(e=>e.scope==='reservation'&&e.reservation_id===first.reservation_id));
    assert.equal(unrelatedEvents.filter(e=>e.type==='change').length,0,'audience가 아닌 사용자 격리');
    const legacyInitial=await (await api('/users/801/notifications',801)).json();
    assert.deepEqual(legacyInitial.notifications,[],'초기 배너 억제를 모르는 구버전 앱에는 과거 알림을 쏟지 않는다');
    const customerBootstrap=await feed(801), ownerBootstrap=await feed(802);
    assert.ok(customerBootstrap.notifications.some(n=>n.type==='reservation_submitted'&&n.reservation_id===first.reservation_id),'첫 cursor 생성 전에 완료된 실제 예약도 알림함으로 복원해야 한다');
    assert.ok(ownerBootstrap.notifications.some(n=>n.type==='reservation_request'&&n.reservation_id===first.reservation_id),'사장님의 첫 feed도 요청을 버리지 않는다');
    assert.ok(customerBootstrap.notifications.length<=100,'초기 backfill은 100개 이하');
    assert.equal(customerBootstrap.notifications.at(-1).reservation_id,first.reservation_id,'초기 응답은 최신 예약이 마지막인 시간순이라 앱 역순 삽입 후 맨 위에 보여야 한다');
    assert.equal(customerBootstrap.is_bootstrap,true,'앱이 과거 복원과 신규 배너를 구분할 수 있어야 한다');
    const second=await reserve();
    await until(()=>customerEvents.some(e=>e.scope==='reservation'&&e.reservation_id===second.reservation_id));
    const increment=await feed(801,customerBootstrap.cursor);
    assert.equal(increment.is_bootstrap,false,'baseline 이후 신규 알림은 배너를 억제하지 않는다');
    assert.deepEqual(increment.notifications.map(n=>[n.type,n.reservation_id]),[['reservation_submitted',second.reservation_id]]);
    assert.deepEqual((await feed(801,increment.cursor)).notifications,[],'동일 cursor 증분 중복 없음');
    assert.deepEqual((await feed(803)).notifications,[],'알림함도 사용자 격리');
    // 첫 응답의 MAX 스냅샷 직후 실제 예약이 완료되어도 다음 WS catchup에서 복구한다.
    const nodeBundle=await build({entryPoints:[`${backend}/src/index.ts`],bundle:true,write:false,format:'esm',platform:'node',
      plugins:[{name:'unused-do-base',setup(builder){
        builder.onResolve({filter:/^cloudflare:workers$/},()=>({path:'workers',namespace:'local-stub'}));
        builder.onLoad({filter:/.*/,namespace:'local-stub'},()=>({contents:'export class DurableObject {}'}));
      }}]});
    const {default:worker}=await import(`data:text/javascript;base64,${Buffer.from(nodeBundle.outputFiles[0].text).toString('base64')}`);
    let racedReservation;
    const snapshotDB=new Proxy(db,{get(target,key){
      if(key!=='prepare')return typeof target[key]==='function'?target[key].bind(target):target[key];
      return sql=>{
        const statement=target.prepare(sql);
        if(!sql.includes('MAX(message_id)')||!sql.includes('FROM chat_messages'))return statement;
        return new Proxy(statement,{get(stmt,method){
          if(method!=='first')return typeof stmt[method]==='function'?stmt[method].bind(stmt):stmt[method];
          return async(...args)=>{const snapshot=await stmt.first(...args);racedReservation=await reserve();return snapshot;};
        }});
      };
    }});
    const snapshotResponse=await worker.fetch(new Request('http://localhost/api/users/801/notifications?bootstrap=1',
      {headers:{Authorization:'Bearer bootstrap-token-801'}}),{DB:snapshotDB},{waitUntil(){}});
    assert.equal(snapshotResponse.status,200);
    const snapshot=await snapshotResponse.json();
    assert.ok(!snapshot.notifications.some(n=>n.reservation_id===racedReservation.reservation_id),'snapshot 이후의 예약은 초기 복원과 섞지 않는다');
    await until(()=>customerEvents.some(e=>e.scope==='reservation'&&e.reservation_id===racedReservation.reservation_id));
    const recovered=await feed(801,snapshot.cursor);
    assert.deepEqual(recovered.notifications.map(n=>[n.type,n.reservation_id]),[['reservation_submitted',racedReservation.reservation_id]],'첫 feed 처리 중 실제 예약은 다음 catchup에서 유실 없이 복구한다');
    assert.equal(recovered.is_bootstrap,false,'경쟁 중 생성된 신규 이벤트는 초기배너억제 대상이 아니다');
    console.log('PASS bootstrap: 실제 예약→audience/DO→Bearer WS change→최초/증분 feed, 최근 100건, 다른 계정 격리');
  }
  if (!reviewOnly) {
  const cancelTarget=await reserve();
  const ownerBaseline=await feed(802);
  assert.equal((await api(`/reservations/${cancelTarget.reservation_id}/cancel`,801,'PATCH')).status,200);
  // CURRENT_TIMESTAMP 초 경계는 실제 요청 뒤에도 같은 값일 수 있다. 경계를 고정해 비결정적 sleep 없이 재현한다.
  const actualCancel=await db.prepare('SELECT canceled_at FROM reservations WHERE reservation_id=?').bind(cancelTarget.reservation_id).first();
  ownerBaseline.cursor.canceled_at=actualCancel.canceled_at; // 기존 서버가 발급한 시계 기반 커서와 같은 경계
  ownerBaseline.cursor.canceled_ids=[];
  const canceled=await feed(802,ownerBaseline.cursor);
  assert.equal(canceled.notifications.filter(n=>n.type==='reservation_canceled'&&n.reservation_id===cancelTarget.reservation_id).length,1,'cursor와 같은 초의 고객 취소를 버리지 않는다');
  assert.deepEqual((await feed(802,canceled.cursor)).notifications,[],'같은 초 경계에서도 취소 알림 재전달 없음');
  console.log('PASS cancellation boundary: 실제 고객취소, 초정밀 cursor 동률 복구와 중복 방지');
  }
} finally {
  for (const ws of sockets) ws.terminate();
  await mf.dispose();
}
