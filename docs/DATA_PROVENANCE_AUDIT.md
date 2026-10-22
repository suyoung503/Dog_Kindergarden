# 맡겨멍 데이터 출처·업체 유형 감사

**감사일:** 2026-10-10  
**범위:** 저장소 코드, 마이그레이션, 크롤러와 기본 로컬 D1  
**주의:** 이 문서는 기술적 출처와 노출 경로를 조사한 결과이며 네이버·카카오·공공데이터의 법률적 사용 허용 여부를 단정하지 않는다.

## 결론

현재 `stores`와 `store_images`에는 공공데이터, 네이버 플레이스 크롤링, 네이버·카카오 API, 홈페이지, OCR, 수동 보정 결과가 섞여 있지만 필드별 출처와 권리 상태가 없다. 따라서 삭제보다 먼저 다음 순서가 필요하다.

1. 권리 미확인 크롤링 데이터의 운영 API 노출 차단
2. 자동 네이버 상세 갱신 동결
3. 운영 D1과 수집 근거 백업
4. 필드별 provenance와 이미지 자산 출처 도입
5. 일반 업체와 맡겨멍 파트너 분리
6. 권리 확인 또는 사장님 직접 제공 데이터만 다시 노출

## 확인된 데이터 규모

아래 수량은 2026-10-10 감사 당시 기본 로컬 D1 스냅샷 기준이며 현재 운영 DB 현황이 아니다. 운영 DB와 일치 여부는 별도 확인이 필요하다.

| 항목 | 수량 |
|---|---:|
| 전체 가게 | 301 |
| 앱 노출 대상 `is_curated=1` | 285 |
| 영업시간 있음 | 284 |
| 가격 있음 | 199 |
| 대표 이미지 있음 | 285 |
| 추가 이미지 | 1,138장 / 285개 가게 |
| 픽업·운동장·대형견 표시 | 97 / 106 / 39 |

대표 이미지 268장과 추가 이미지 1,134장은 네이버 `pstatic.net` 주소다. 영업시간 284건 중 138건에 `10/3`, `10/5`처럼 특정 날짜가 포함되어 있어 순환 갱신 전에는 과거 날짜가 최신 정보처럼 보일 수 있다.

감사 시점에는 `Dog_kindergarden/All_data.csv`가 삭제됐다는 기존 기록과 달리 Git에 다시 추적되어 있었다. 1,349줄, 약 376KB였고 실행 경로와 문서 외 참조가 없으며 과거에도 미사용 파일로 삭제한 기록이 확인되어 2026-10-10 후속 정리에서 제거했다. 앞으로 공공데이터 원본이 필요하면 출처·이용 조건·갱신일을 기록한 별도 보안 저장소에서 관리한다.

## 필드별 출처 혼합

| 필드 | 현재 출처 | 문제 |
|---|---|---|
| 이름·주소·전화·좌표 | 공공데이터, 네이버, 카카오, 수동 보정 | 최종 채택 출처를 DB에서 판별 불가 |
| 영업시간 | 네이버 플레이스, 홈페이지·리뷰·당근 일부 | 수집 URL·수집일·권리 상태 없음 |
| 가격 | 네이버 메뉴, 가격표 OCR, 홈페이지·검색, 수동 SQL | 수집 방식과 신뢰도를 구분할 수 없음 |
| 대표·추가 이미지 | 대부분 네이버 플레이스 업체 이미지 | 권리 상태·업체 동의·수집 시각 없음 |
| 픽업·운동장·대형견 | 소개·메뉴·리뷰·홈페이지 키워드 | `0`이 불가와 미확인을 동시에 의미 |
| `details_checked_at` | 자동 크롤러 실행 시각 | 성공한 필드와 실패 여부를 알 수 없음 |

## 저장·노출 경로

- 이미지 수집: `crawl-store-images.mjs`, `crawl-store-enrichment.mjs`, `src/storeDetailRefresh.ts`
- 가격 수집: `crawl-store-details.mjs`, `scrape-naver-place-prices.mjs`, `crawl-store-prices.mjs`, `ocr-price-images-local.mjs`, 수동 SQL
- 저장: `stores.open_time`, `stores.price_info`, `stores.image_url`, `store_images.image_url`
- 공개 노출: `GET /api/stores`, `GET /api/stores/detail`, 지도 카드, 가게 상세, 전체 화면 이미지 갤러리
- 운영 자동 갱신: `wrangler.toml`의 4시간 Cron이 오래 확인하지 않은 8곳의 영업시간·이미지를 갱신

가게 상세의 크롤링 가격과 예약 화면의 고정 가격은 서로 연결되지 않는다. 예약 화면은 시간당 5,000원·종일 35,000원·숙박 50,000원·픽업 10,000원을 별도로 계산하므로 실제 업체 가격처럼 오해될 수 있다.

## 출시 차단 위험

1. 크롤링 상세가 인증 없는 공개 API에서 그대로 반환된다.
2. 일반 업체에도 예약·채팅·리뷰가 열려 실제 사장님이 없는 예약이 생길 수 있다.
3. 출처가 섞여 특정 출처만 선택적으로 숨기거나 삭제할 수 없다.
4. 자동 크롤러가 권리 검토 중에도 값을 계속 덮어쓴다.
5. `crawl-results`·적용 SQL·D1 백업이 Git 제외 상태라 출처 복원 근거가 유실될 수 있다.

## 권장 스키마

`stores.source` 하나가 아니라 필드별 사실과 권리 상태가 필요하다.

```sql
CREATE TABLE store_field_facts (
  fact_id INTEGER PRIMARY KEY AUTOINCREMENT,
  store_id INTEGER NOT NULL,
  field_name TEXT NOT NULL,
  value_json TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_url TEXT,
  source_record_id TEXT,
  collected_at TEXT NOT NULL,
  verified_at TEXT,
  verification_level TEXT NOT NULL DEFAULT 'RAW',
  rights_status TEXT NOT NULL DEFAULT 'REVIEW_REQUIRED',
  extractor_version TEXT,
  value_hash TEXT,
  is_active INTEGER NOT NULL DEFAULT 1
);
```

- `source_type`: `PUBLIC_DATA`, `NAVER_PLACE_CRAWL`, `NAVER_SEARCH_API`, `KAKAO_API`, `HOMEPAGE`, `OWNER`, `USER_REVIEW`, `ADMIN`
- `rights_status`: `REVIEW_REQUIRED`, `ALLOWED`, `ATTRIBUTION_REQUIRED`, `RESTRICTED`, `REMOVED`
- `verification_level`: `RAW`, `AUTO_MATCHED`, `ADMIN_VERIFIED`, `OWNER_VERIFIED`

이미지는 `source_type`, `source_url`, `collected_at`, `rights_status`, `owner_confirmed_at`, `is_active`를 가진 별도 자산 구조로 확장한다. 장기적으로 파트너 사진은 외부 CDN URL을 직접 표시하는 대신 사장님이 제공한 파일을 R2에 저장한다.

## 일반 업체·파트너 기준

`owner_id`와 파트너 계약·노출 동의는 분리한다.

- `NONE`: 일반 업체
- `PENDING`: 입점·소유 확인 중
- `ACTIVE`: 운영자 확인과 업체 동의 완료
- `SUSPENDED`: 일시 중지
- `TERMINATED`: 계약 종료

일반 업체는 허용이 확인된 공공 기본정보, 전화, 외부 지도, 찜만 제공한다. 이미지 대신 자체 기본 이미지를 쓰고, 미확인 가격·영업시간은 업체 문의 안내로 대체하며 예약·채팅·알림장·앱 내부 리뷰는 서버와 iOS 양쪽에서 차단한다.

파트너 업체는 `ACTIVE` 상태에서만 사장님이 직접 입력한 가격·영업시간·편의정보와 제공 이미지를 노출하고 예약·채팅·알림장·이용 완료 리뷰를 활성화한다.

## 백업 후 정리 원칙

1. 운영 크롤러와 운영 DB 반영을 중지한다.
2. `wrangler d1 export`로 전체·`stores`·`store_images` SQL을 각각 백업한다.
3. 수집 JSON, OCR 입력·결과, 네이버 장소 ID, 적용 SQL, 수집 시각과 크롤러 버전을 접근 제한 저장소에 보관한다.
4. 생성 시각, D1 bookmark, SHA-256, 행 수, 마이그레이션 번호를 manifest로 남긴다.
5. 새 로컬 D1에 복원해 수량과 API를 검증한다.
6. 즉시 삭제하지 않고 `REVIEW_REQUIRED` 또는 `is_active=0`으로 먼저 격리한다.

## 외부 확인이 필요한 사항

- 네이버 플레이스 HTML과 업체 등록 이미지의 저장·직접 노출 허용 범위
- 네이버 검색 API 결과의 출처 표시, 원문 링크, 저장 기간 조건
- 실제 공공데이터포털 데이터셋 ID, 공공누리 유형, 상업 이용·가공·재배포 조건
- 카카오·당근·업체 홈페이지에서 가져온 각 필드의 이용 조건

권리 확인 전 기본 정책은 **운영 비노출·자동 수집 중지·파트너 직접 제공 데이터로 교체**다.
