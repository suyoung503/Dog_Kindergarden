#!/usr/bin/env node
// 실제 Worker + 격리된 임시 Miniflare/D1/R2만 사용한다. 운영 데이터에는 접근하지 않는다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';
const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'reservation-details-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'reservation details local test' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
let checks = 0;
const equal = (actual,expected,label) => { assert.deepEqual(actual,expected,label); checks++; };
try {
  const db = await mf.getD1Database('DB'), bucket = await mf.getR2Bucket('DIARY_PHOTOS');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f=>f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`,'utf8')).replace(/--[^\n]*/g,'').replace(/\n/g,' '));
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,phone,address,is_owner,is_admin) VALUES
    (961,'details-customer','원래 보호자','01011112222','원래 주소',0,0),
    (962,'details-owner','사장님',NULL,NULL,1,0),(963,'details-other-owner','다른 사장님',NULL,NULL,1,0),
    (964,'details-admin','운영자',NULL,NULL,0,1),(965,'details-other-customer','다른 보호자',NULL,NULL,0,0);
    INSERT INTO stores(store_id,name,store_key,owner_id,partner_status) VALUES(961,'예약 상세 유치원','details-store',962,'ACTIVE');
    INSERT INTO pets(pet_id,user_id,name,breed,age,weight,gender,note,image_url) VALUES
    (961,961,'초코','말티푸',3,5.2,'남아','원래 주의사항','/api/pets/961/photo'),
    (962,965,'다른 강아지','푸들',5,8,'여아','다른 개인정보',NULL),
    (963,961,'누리',NULL,NULL,NULL,NULL,NULL,NULL);`.replace(/\n/g,' '));
  for (const id of [961,962,963,964,965]) await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(`details-token-${id}`).digest('hex'),id).run();
  const api = (path,id=961,method='GET',body) => mf.dispatchFetch(`http://localhost/api${path}`, {
    method, headers:{Authorization:`Bearer details-token-${id}`,...(body?{'Content-Type':'application/json'}:{})},
    body:body?JSON.stringify(body):undefined });
  const json = async (path,id=962) => { const response=await api(path,id); equal(response.status,200,path); return response.json(); };
  const book = async (overrides={}) => {
    const response=await api('/reservations',961,'POST',{
      pet_id:961,store_id:961,start_date:'2099-01-02',end_date:'2099-01-03',reservation_type:'돌봄',request_message:'신청 요청사항',...overrides});
    equal(response.status,201,'예약 생성'); return (await response.json()).reservation_id;
  };
  const first=await book({guardian_phone:'01033334444',guardian_address:'신청 주소',user_name:'위조 이름',pet_name:'위조 반려견'});
  const path=`/reservations/${first}`;
  const detail=await json(path);
  equal(detail.user_name,'원래 보호자','이름은 인증 사용자 DB에서');
  equal(detail.user_phone,'01033334444','예약별 전화번호');
  equal(detail.user_address,'신청 주소','예약별 주소');
  equal(detail.pet_name,'초코','반려견은 본인 DB에서');
  equal(detail.information_source,'BOOKING_SNAPSHOT','신규 예약 스냅샷 출처');
  equal(detail.end_date,'2099-01-03','종료일 보존');
  equal(detail.status,'REQUEST','신청 상태');
  equal(detail.pet_image_url,`/api/reservations/${first}/pet-photo`,'요청 상세도 해당 예약 private 사진 URL 전달');
  equal(detail.request_message,'신청 요청사항','예약 요청사항 보존');
  equal(JSON.stringify(detail).includes('booking_snapshot'),false,'저장 JSON은 DTO에 노출하지 않음');
  equal(JSON.stringify(detail).includes('email'),false,'이메일은 예약정보 범위 아님');
  const second=await book(), nullable=await book({pet_id:963});
  const empty=await book({guardian_phone:'',guardian_address:''}), explicitNull=await book({guardian_phone:null,guardian_address:null});
  equal((await json(`/reservations/${empty}`)).user_phone,'','전달된 빈 전화번호는 그대로 유지');
  equal((await json(`/reservations/${empty}`)).user_address,'','전달된 빈 주소는 그대로 유지');
  equal((await json(`/reservations/${explicitNull}`)).user_phone,null,'명시적 null 전화번호는 미입력');
  equal((await json(`/reservations/${explicitNull}`)).user_address,null,'명시적 null 주소는 미입력');
  equal((await json(`/reservations/${second}`)).user_phone,'01011112222','미전달 번호는 사용자 DB fallback');
  equal((await json(`/reservations/${second}`)).user_address,'원래 주소','미전달 주소는 사용자 DB fallback');
  await api('/users/961',961,'PUT',{nickname:'변경 보호자',phone:'01099998888',address:'변경 주소'});
  await db.exec("UPDATE pets SET name='변경 초코',breed='변경 품종',age=9,weight=9.9,gender='변경 성별',note='변경 메모' WHERE pet_id=961; UPDATE pets SET breed='새 품종',age=1,weight=2,gender='새 성별',note='새 메모' WHERE pet_id=963;");
  const fixed=await json(path);
  for (const key of ['user_name','user_phone','user_address','pet_name','pet_breed','pet_age','pet_weight','pet_gender','pet_note'])
    equal(fixed[key],detail[key],`프로필 변경 후 ${key} 불변`);
  const fixedNullable=await json(`/reservations/${nullable}`);
  for (const key of ['pet_breed','pet_age','pet_weight','pet_gender','pet_note']) equal(fixedNullable[key],null,`신청시 null ${key}도 고정`);
  const pending=(await json('/owners/962/reservations/pending')).find(r=>r.reservation_id===first);
  equal(pending,fixed,'대기 목록과 상세 동일 flat DTO');
  const beforeInvalid=(await db.prepare('SELECT COUNT(*) AS count FROM reservations').first()).count;
  for (const overrides of [{pet_id:962},{guardian_phone:123},{guardian_address:{invalid:true}}]) {
    const response=await api('/reservations',961,'POST',{pet_id:961,store_id:961,start_date:'2099-01-02',end_date:'2099-01-03',...overrides});
    equal(response.status,overrides.pet_id?403:400,'외부 반려견/잘못된 연락처 타입 차단');
  }
  equal((await db.prepare('SELECT COUNT(*) AS count FROM reservations').first()).count,beforeInvalid,'실패 요청은 예약을 만들지 않음');
  for (const id of [961,963,964,965]) equal((await api(path,id)).status,403,'고객·다른 사장님·운영자 상세 접근 차단');
  equal((await api('/reservations/999999',962)).status,404,'존재하지 않는 예약');
  await db.prepare(`INSERT INTO reservations(reservation_id,user_id,pet_id,store_id,start_date,end_date,reservation_type,status)
    VALUES(9991,961,961,961,'2099-01-02','2099-01-03','돌봄','REQUEST'),(9992,961,962,961,'2099-01-02','2099-01-03','돌봄','REQUEST')`).run();
  const legacy=await json('/reservations/9991');
  equal(legacy.information_source,'CURRENT_PROFILE','기존 nullable 스냅샷은 현재 정보 출처');
  equal(legacy.user_name,'변경 보호자','기존 예약은 현재 프로필 표시');
  equal(legacy.pet_name,'변경 초코','기존 예약은 현재 반려견 표시');
  equal((await json('/reservations/9992')).pet_name,null,'잘못 연결된 과거 예약도 다른 사람 반려견 노출 금지');
  equal((await db.prepare('SELECT booking_snapshot FROM reservations WHERE reservation_id=9991').first()).booking_snapshot,null,'과거 예약 백필 안 함');
  equal((await api(`/reservations/${first}/pet-photo`,962)).status,404,'요청 사진 권한은 허용하되 미등록 R2 사진은 404');
  equal((await api(`${path}/confirm`,962,'PATCH')).status,200,'예약 확정');
  await db.prepare("INSERT INTO pet_photos(pet_id,r2_key) VALUES(961,'pet-photos/details.jpg')").run();
  await bucket.put('pet-photos/details.jpg',new Uint8Array([255,216,255,217]));
  const confirmed=await json(path);
  equal(confirmed.status,'CONFIRMED','확정 상태');
  for (const key of ['user_name','user_phone','user_address','pet_name','pet_breed','pet_age','pet_weight','pet_gender','pet_note']) equal(confirmed[key],detail[key],`확정 후 ${key} 불변`);
  equal(confirmed.pet_image_url,`/api/reservations/${first}/pet-photo`,'기존 private 사진 URL 사용');
  equal((await json('/owners/962/reservations/confirmed')).find(r=>r.reservation_id===first),confirmed,'확정 목록과 상세 일치');
  for (const id of [961,962]) equal((await api(`${path}/pet-photo`,id)).status,200,'기존 확정 고객/점주 사진 권한 유지');
  for (const id of [963,964,965]) equal((await api(`${path}/pet-photo`,id)).status,403,'무관 계정 사진 권한 차단');
  for (const method of ['GET','PUT','DELETE']) equal((await api('/pets/961/photo',962,method)).status,403,'계정 원본 사진은 점주 접근 불가');
  await db.exec("UPDATE stores SET partner_status='SUSPENDED' WHERE store_id=961");
  equal((await api(path,962)).status,403,'승인 해제 상세 차단');
  equal((await json('/owners/962/reservations/confirmed')).length,0,'승인 해제 목록 차단');
  equal((await api(`${path}/pet-photo`,962)).status,403,'승인 해제 사진 차단');
  await db.exec("UPDATE stores SET partner_status='ACTIVE' WHERE store_id=961");
  equal((await api(`${path}/cancel`,961,'PATCH')).status,200,'고객 예약 취소');
  equal((await api(path,962)).status,403,'취소 예약 상세 차단');
  equal((await api(`${path}/pet-photo`,962)).status,403,'취소 예약 사진 차단');
  await db.exec("UPDATE reservations SET status='CANCELED',canceled_at=CURRENT_TIMESTAMP WHERE user_id=961");
  equal((await api('/users/961/account',961,'DELETE')).status,200,'예약 취소 후 회원 탈퇴');
  const erased=await db.prepare('SELECT booking_snapshot,request_message FROM reservations WHERE user_id=961').all();
  for (const row of erased.results) equal(row,{booking_snapshot:null,request_message:null},'탈퇴시 신청 스냅샷과 요청 개인정보 제거');
  equal((await db.prepare('SELECT COUNT(*) AS count FROM pets WHERE user_id=961').first()).count,0,'탈퇴시 반려견 제거');
  console.log(`PASS ${checks} reservation detail checks`);
} finally { await mf.dispose(); }
