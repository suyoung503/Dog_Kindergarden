#!/usr/bin/env node
// 격리된 Worker/D1/R2만 사용하며 운영 데이터에는 접근하지 않는다.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';
const backend = fileURLToPath(new URL('..', import.meta.url));
const bundle = await build({ entryPoints: [`${backend}/src/index.ts`], bundle: true, write: false,
  format: 'esm', platform: 'neutral', external: ['cloudflare:*'] });
const options = { name: 'reservation-pet-photo-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20', d1Databases: ['DB'], r2Buckets: ['DIARY_PHOTOS'],
  bindings: { APP_NAME: 'reservation pet photo local test' },
  durableObjects: { USER_REALTIME: { className: 'UserRealtime', useSQLite: true } } };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
let checks = 0;
const equal = (a,b,label) => { assert.deepEqual(a,b,label); checks++; };
try {
  const db = await mf.getD1Database('DB'), bucket = await mf.getR2Bucket('DIARY_PHOTOS');
  for (const file of (await readdir(`${backend}/migrations`)).filter(f => f.endsWith('.sql')).sort())
    await db.exec((await readFile(`${backend}/migrations/${file}`, 'utf8')).replace(/--[^\n]*/g, '').replace(/\n/g, ' '));
  await db.exec(`INSERT INTO users(user_id,kakao_id,nickname,is_owner,is_admin) VALUES
    (951,'photo-customer','보호자',0,0),(952,'photo-owner','사장님',1,0),
    (953,'photo-other-owner','무관 사장님',1,0),(954,'photo-admin','관리자',0,1),(955,'photo-other-customer','다른 보호자',0,0);
    INSERT INTO stores(store_id,name,store_key,owner_id,partner_status) VALUES(951,'사진 유치원','photo-store',952,'ACTIVE');
    INSERT INTO pets(pet_id,user_id,name,image_url) VALUES(951,951,'초코','/api/pets/951/photo'),(952,951,'보리',NULL);
    INSERT INTO pet_photos(pet_id,r2_key) VALUES(951,'pet-photos/951/test.jpg');
    INSERT INTO reservations(reservation_id,user_id,pet_id,store_id,start_date,end_date,reservation_type,status)
    VALUES(951,951,951,951,'2099-01-01','2099-01-01','돌봄','CONFIRMED'),
    (952,951,952,951,'2099-01-01','2099-01-01','돌봄','CONFIRMED'),
    (953,951,951,951,'2099-01-01','2099-01-01','돌봄','REQUEST');`.replace(/\n/g,' '));
  for (const id of [951,952,953,954,955]) await db.prepare("INSERT INTO auth_sessions(token_hash,user_id,expires_at) VALUES(?,?,datetime('now','+1 day'))")
    .bind(createHash('sha256').update(`photo-token-${id}`).digest('hex'),id).run();
  const api = (path,id=951,method='GET') => mf.dispatchFetch(`http://localhost/api${path}`, {
    method,headers:id?{Authorization:`Bearer photo-token-${id}`}:{}});
  const list = async (path,id) => { const response=await api(path,id); equal(response.status,200,'list allowed'); return response.json(); };
  const photoPath = '/reservations/951/pet-photo';
  await bucket.put('pet-photos/951/test.jpg',new Uint8Array([255,216,255,217]));
  for (const id of [951,952]) {
    const photo=await api(photoPath,id);
    equal(photo.status,200,'confirmed customer and approved store owner can read');
    equal(photo.headers.get('cache-control'),'private, no-store','photo never shared-cached');
    equal(photo.headers.get('content-type'),'image/jpeg','JPEG response');
    equal(new Uint8Array(await photo.arrayBuffer()),new Uint8Array([255,216,255,217]),'R2 bytes');
  }
  for (const id of [953,954,955]) equal((await api(photoPath,id)).status,403,'unrelated owner, admin and customer denied');
  equal((await api(photoPath,null)).status,401,'unauthenticated denied');
  for (const method of ['GET','PUT','DELETE']) equal((await api('/pets/951/photo',952,method)).status,403,'original endpoint stays pet-owner-only');
  equal((await api('/users/951/pets',952)).status,403,'owner cannot list customer account pets');
  for (const path of ['/users/951/reservations','/owners/952/reservations/confirmed']) {
    const rows=await list(path,path.startsWith('/users')?951:952);
    equal(rows.find(r=>r.reservation_id===951).pet_image_url,'/api/reservations/951/pet-photo','correct authenticated reservation photo URL');
    equal(rows.find(r=>r.reservation_id===952).pet_image_url,null,'nil image remains nil');
    equal(JSON.stringify(rows).includes('pet-photos/'),false,'raw R2 keys never exposed');
  }
  const requestPhotoPath = '/reservations/953/pet-photo';
  for (const id of [951,952]) {
    const photo = await api(requestPhotoPath,id);
    equal(photo.status,200,'REQUEST customer and ACTIVE recipient owner can read');
    equal(photo.headers.get('cache-control'),'private, no-store','REQUEST photo never shared-cached');
    equal(new Uint8Array(await photo.arrayBuffer()),new Uint8Array([255,216,255,217]),'REQUEST R2 bytes');
  }
  for (const id of [953,954,955]) equal((await api(requestPhotoPath,id)).status,403,'REQUEST unrelated owner, admin and customer denied');
  equal((await api(requestPhotoPath,null)).status,401,'REQUEST unauthenticated denied');
  for (const [path,id] of [['/owners/952/reservations/pending',952],['/users/951/reservations',951]]) {
    const rows = await list(path,id);
    equal(rows.find(r=>r.reservation_id===953).pet_image_url,'/api' + requestPhotoPath,'REQUEST DTO delivers private same-origin photo URL');
    equal(JSON.stringify(rows).includes('pet-photos/'),false,'REQUEST DTO never exposes raw R2 key');
  }
  const requestDetail = await list('/reservations/953',952);
  equal(requestDetail.pet_image_url,'/api' + requestPhotoPath,'REQUEST detail shares same image URL');
  equal(requestDetail.information_source,'CURRENT_PROFILE','legacy reservation remains current profile');
  await db.exec('UPDATE users SET is_owner=0 WHERE user_id=952');
  for (const path of [photoPath,requestPhotoPath]) {
    equal((await api(path,952)).status,403,'revoked owner role cannot read even when store owner_id remains');
    equal((await api(path,951)).status,200,'actual customer keeps their scoped read when owner role changes');
  }
  await db.exec('UPDATE users SET is_owner=1 WHERE user_id=952');
  await db.exec('UPDATE stores SET owner_id=NULL WHERE store_id=951');
  for (const path of [photoPath,requestPhotoPath]) equal((await api(path,951)).status,403,'ACTIVE store without recipient owner cannot share photo');
  const ownerlessRows = await list('/users/951/reservations',951);
  for (const id of [951,953]) equal(ownerlessRows.find(r=>r.reservation_id===id).pet_image_url,null,'ownerless store customer DTO removes photo');
  await db.exec('UPDATE stores SET owner_id=952 WHERE store_id=951');
  await db.exec("INSERT INTO pets(pet_id,user_id,name,image_url) VALUES(953,955,'다른 보호자의 강아지','/api/pets/953/photo'); INSERT INTO pet_photos(pet_id,r2_key) VALUES(953,'pet-photos/955/other.jpg'); INSERT INTO reservations(reservation_id,user_id,pet_id,store_id,start_date,end_date,reservation_type,status) VALUES(954,951,953,951,'2099-01-01','2099-01-01','돌봄','REQUEST')");
  await bucket.put('pet-photos/955/other.jpg',new Uint8Array([255,216,255,217]));
  for (const id of [951,952]) equal((await api('/reservations/954/pet-photo',id)).status,404,'corrupt reservation cannot expose another customers pet');
  equal((await list('/reservations/954',952)).pet_image_url,null,'corrupt reservation detail omits photo');
  equal((await list('/users/951/reservations',951)).find(r=>r.reservation_id===954).pet_image_url,null,'corrupt reservation customer DTO omits photo');
  await db.exec('DELETE FROM reservations WHERE reservation_id=954; DELETE FROM pet_photos WHERE pet_id=953; DELETE FROM pets WHERE pet_id=953');
  await bucket.delete('pet-photos/955/other.jpg');
  await db.prepare('UPDATE reservations SET booking_snapshot=? WHERE reservation_id=953').bind(JSON.stringify({pet_name:'신청 당시 초코',pet_image_url:'https://evil.example/snapshot.jpg'})).run();
  const snapshotDetail = await list('/reservations/953',952);
  equal(snapshotDetail.pet_name,'신청 당시 초코','snapshot presentation preserved');
  equal(snapshotDetail.pet_image_url,'/api' + requestPhotoPath,'snapshot cannot replace actual private photo URL');
  equal((await list('/owners/952/reservations/pending',952)).find(r=>r.reservation_id===953).pet_image_url,snapshotDetail.pet_image_url,'snapshot pending and detail deliver same actual image');
  await db.exec("UPDATE stores SET partner_status='SUSPENDED' WHERE store_id=951");
  for (const id of [951,952]) equal((await api(requestPhotoPath,id)).status,403,'REQUEST revoked partner blocks customer and owner');
  equal((await list('/owners/952/reservations/pending',952)).length,0,'REQUEST revoked partner gets no pending list');
  const revokedCustomerRows = await list('/users/951/reservations',951);
  for (const id of [951,953]) equal(revokedCustomerRows.find(r=>r.reservation_id===id).pet_image_url,null,'revoked partner customer DTO removes scoped photo');
  equal((await api('/reservations/953',952)).status,403,'REQUEST revoked partner gets no detail');
  await db.exec("UPDATE stores SET partner_status='ACTIVE' WHERE store_id=951; UPDATE reservations SET status='CANCELED' WHERE reservation_id=953");
  for (const id of [951,952]) equal((await api(requestPhotoPath,id)).status,403,'canceled REQUEST blocks customer and owner');
  equal((await list('/users/951/reservations',951)).find(r=>r.reservation_id===953).pet_image_url,null,'canceled REQUEST removes photo URL');
  await db.exec("UPDATE reservations SET status='REQUEST' WHERE reservation_id=953");
  equal((await api('/reservations/952/pet-photo',952)).status,404,'no photo');
  equal((await api('/reservations/999999/pet-photo',952)).status,404,'unknown reservation');
  await db.exec("UPDATE reservations SET status='CANCELED' WHERE reservation_id=951");
  equal((await api(photoPath,952)).status,403,'canceled owner read denied immediately');
  equal((await list('/users/951/reservations',951)).find(r=>r.reservation_id===951).pet_image_url,null,'canceled DTO removes photo');
  await db.exec("UPDATE reservations SET status='CONFIRMED' WHERE reservation_id=951; UPDATE stores SET partner_status='SUSPENDED' WHERE store_id=951");
  for (const id of [951,952]) equal((await api(photoPath,id)).status,403,'revoked partner read denied for owner and customer');
  equal((await list('/owners/952/reservations/confirmed',952)).length,0,'revoked partner has no confirmed photo list');
  await db.exec("UPDATE stores SET partner_status='ACTIVE' WHERE store_id=951");
  const legacy='data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAgP/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=';
  await db.prepare('UPDATE pets SET image_url=? WHERE pet_id=952').bind(legacy).run();
  equal((await list('/owners/952/reservations/confirmed',952)).find(r=>r.reservation_id===952).pet_image_url,legacy,'legacy valid Base64 remains compatible');
  await db.exec('UPDATE reservations SET pet_id=952 WHERE reservation_id=953');
  equal((await list('/owners/952/reservations/pending',952)).find(r=>r.reservation_id===953).pet_image_url,legacy,'REQUEST legacy Base64 pending remains compatible');
  equal((await list('/reservations/953',952)).pet_image_url,legacy,'REQUEST legacy Base64 detail remains compatible');
  for (const id of [951,952]) {
    const response = await api(requestPhotoPath,id);
    equal(response.status,200,'REQUEST reads valid legacy photo');
    equal(response.headers.get('cache-control'),'private, no-store','REQUEST legacy photo cache policy');
    equal(Buffer.from(await response.arrayBuffer()).toString('base64'),legacy.split(',')[1],'REQUEST legacy bytes preserved');
  }
  await db.exec("UPDATE stores SET partner_status='SUSPENDED' WHERE store_id=951");
  const revokedLegacyRows = await list('/users/951/reservations',951);
  for (const id of [952,953]) equal(revokedLegacyRows.find(r=>r.reservation_id===id).pet_image_url,null,'revoked partner customer DTO never exposes legacy photo bytes');
  await db.exec("UPDATE stores SET partner_status='ACTIVE' WHERE store_id=951");
  const legacyPhoto=await api('/reservations/952/pet-photo',952);
  equal(legacyPhoto.status,200,'notification URL also reads legacy photo');
  equal(Buffer.from(await legacyPhoto.arrayBuffer()).toString('base64'),legacy.split(',')[1],'legacy bytes preserved');
  for (const bad of ['https://evil.example/photo.jpg','/api/pets/951/photo','data:image/svg+xml;base64,AAAA','data:image/jpeg;base64,bad!','data:image/jpeg;base64,AAAA']) {
    await db.prepare('UPDATE pets SET image_url=? WHERE pet_id=952').bind(bad).run();
    equal((await list('/owners/952/reservations/confirmed',952)).find(r=>r.reservation_id===952).pet_image_url,null,'arbitrary reference excluded');
  }
  await bucket.delete('pet-photos/951/test.jpg');
  equal((await api(photoPath,952)).status,404,'missing R2 object yields no photo');
  await bucket.put('pet-photos/951/test.jpg',new Uint8Array([255,216,255,217]));
  equal((await api('/pets/951/photo',951,'DELETE')).status,200,'customer photo deletion');
  equal((await api(photoPath,952)).status,404,'D1 photo removal revokes reservation image');
  equal(await bucket.get('pet-photos/951/test.jpg'),null,'photo deletion drains R2');
  equal((await db.prepare('SELECT COUNT(*) AS count FROM pet_photos WHERE pet_id=951').first()).count,0,'photo metadata removed');
  equal((await list('/owners/952/reservations/confirmed',952)).find(r=>r.reservation_id===951).pet_image_url,null,'deleted photo omitted from DTO');
  console.log(`PASS ${checks} reservation pet photo checks`);
} finally { await mf.dispose(); }
