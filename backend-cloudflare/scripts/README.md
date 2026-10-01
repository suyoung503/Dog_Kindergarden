# scripts/

서울 애견 유치원·호텔 큐레이션 데이터를 만들 때 쓰는 크롤링/보강 도구 모음.
CI에 연결되지 않은 수동 실행 스크립트이며, 결과는 `crawl-results/`에 쌓인다.

## 실행 순서

1. **crawl-store-details.mjs** (`npm run crawl:seoul`)
   data.go.kr 공공데이터에서 지역 후보를 뽑고 네이버/카카오 API + 홈페이지 크롤링으로 주소·전화·이미지·가격 텍스트를 보강한다.
   입력: 없음 (공공데이터 API 직접 호출)
   출력: `crawl-results/seoul-store-details-{timestamp}.json`, `.sql`

2. **check-naver-category.mjs**
   1번 결과를 네이버 플레이스에서 재검색해 `category` 필드로 배제 후보(미용/카페/용품/병원 등)를 표시한다.
   입력: `--input=<1번 결과 json>`
   출력: `crawl-results/category-check-result-{timestamp}.json`

3. **scrape-naver-place-prices.mjs** (`npm run scrape:naver-prices`)
   네이버 플레이스 상세의 텍스트 메뉴(`Menu:`)에서 가격 정보를 수집한다.
   입력: `--input=<1번 결과 json>` (생략 시 최신 `seoul-store-details-*.json` 자동 탐색)
   출력: `crawl-results/naver-place-prices-{timestamp}.json`, `.sql`

4. **scan-price-images.mjs**
   3번에서 텍스트 메뉴를 못 찾은 가게를 대상으로, 네이버 플레이스의 "가격표 이미지"를 비전 AI(Cloudflare Workers AI)로 OCR한다.
   입력: `--input=<{store_key, store_name, place_id}[] 형태의 json>`
   출력: `crawl-results/price-image-scan-result.json` (+ 체크포인트 `price-image-scan-progress.json`, 중단 후 재실행 시 이어서 처리)

이후 키워드/카테고리 기준으로 최종 목록을 추리고 `apply-curated-*.sql`을 만드는 과정은 스크립트가 아니라
직접 검토하며 진행했다 — 산출물은 `crawl-results/`에 SQL 파일로만 남아있다.

5. **crawl-store-images.mjs** (`npm run crawl:images`)
   배포 API(`GET /api/stores`)에서 `image_url`이 비어있는 큐레이션 가게를 뽑아, 네이버 플레이스
   검색 목록 페이지가 제공하는 대표 이미지(`imageUrl` 필드)로 채운다. 상세페이지를 열 필요 없이
   가격/카테고리 스크립트와 같은 목록 페이지 fetch 한 번으로 끝난다.
   입력: 없음 (배포 API 직접 호출)
   출력: `crawl-results/store-images-{timestamp}.json`, `.sql`

6. **crawl-store-enrichment.mjs** (`npm run crawl:enrichment`)
   배포 API의 큐레이션 가게를 네이버 플레이스 상세에서 다시 찾아 영업시간, 업체 등록 사진
   최대 5장, 대형견·픽업·운동장 키워드를 보강한다. 편의 태그는 업체 정보·가격표를 우선하고
   공개 리뷰를 보조 근거로 사용하며, 긍정 근거가 있을 때만 `1`로 갱신한다.
   입력: 없음 (배포 API 직접 호출)
   출력: `crawl-results/store-enrichment-{timestamp}.json`, `.sql`
   로컬 D1 반영: `npm run crawl:enrichment:local`

   네이버가 연속 요청을 제한할 수 있으므로 전체 목록은 `--offset=0 --limit=40`처럼 작은 묶음으로
   나눠 실행하고, 연속 fetch 실패로 멈추면 충분히 기다린 뒤 마지막 처리 위치부터 재개한다.
   특정 가게만 재수집할 때는 `--name="가게명 일부" --limit=1 --apply-local`을 사용한다.
   `large_dog`, `pickup`, `playground`의 `0`은 "불가" 확정이 아니라 **긍정 근거 미확인**을 뜻한다.

7. **crawl-store-prices.mjs** (`npm run crawl:prices`)
   가격 정보가 비어 있는 큐레이션 가게만 대상으로 네이버 플레이스의 구조화된 `Menu.price`를
   다시 수집한다. 과거 상세 보강 결과의 `place_id`를 재사용하고, 가격표 이미지밖에 없는 곳은
   OCR 후보 URL만 결과 JSON에 남긴다. 불확실한 이미지 OCR 결과는 DB에 자동 반영하지 않는다.
   입력: 없음 (배포 API + 기존 `store-enrichment-*.json` 결과 사용)
   출력: `crawl-results/store-prices-{timestamp}.json`, `.sql`
   로컬 D1 반영: `npm run crawl:prices:local`
   기존 가격을 현재 구조화 가격으로 재검증할 때는 `--name="가게명" --refresh --overwrite --apply-local`을 사용한다.

8. **ocr-price-images-local.mjs** (`npm run ocr:prices:local`)
   7번 결과에서 가격표 이미지만 있는 가게를 macOS Vision의 한국어 OCR로 읽는다.
   생성형 모델을 사용하지 않으며, 서로 다른 금액 2개 이상과 서비스 문맥이 함께 잡힌 경우만
   고신뢰로 판정해 로컬 D1의 빈 `price_info`에 반영한다.
   입력: `crawl-results/price-ocr-input-*.json`
   출력: `crawl-results/local-price-ocr-{timestamp}.json`, `.sql`

## 공통 유틸 (lib.mjs)

Apollo State 파싱, 이름 매칭(`namesLikelyMatch`), SQL 문자열 이스케이프, rate-limit용 `sleep`,
`--key=value` 인자 파싱 등 여러 스크립트가 동일하게 쓰던 로직을 모았다. 새 스크립트를 추가할 때
네이버 플레이스 페이지를 다시 fetch/파싱해야 한다면 여기부터 확인할 것.

## 원칙

- 캡차/로그인/차단 우회를 하지 않는다 — 일반 GET으로 받아지는 공개 HTML/API만 쓴다.
- 네이버 요청 사이에는 `sleep`으로 딜레이를 두고, 연속 실패가 이어지면 중단한다(차단 의심).
- OCR 결과는 낮은 신뢰도의 텍스트를 자동 반영하지 않는다. 가격표 이미지처럼 구조화가 어려운 값은
  원본 근거와 함께 별도 검증하고, 확실하지 않으면 빈 값으로 둔다.
