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

## 공통 유틸 (lib.mjs)

Apollo State 파싱, 이름 매칭(`namesLikelyMatch`), SQL 문자열 이스케이프, rate-limit용 `sleep`,
`--key=value` 인자 파싱 등 여러 스크립트가 동일하게 쓰던 로직을 모았다. 새 스크립트를 추가할 때
네이버 플레이스 페이지를 다시 fetch/파싱해야 한다면 여기부터 확인할 것.

## 원칙

- 캡차/로그인/차단 우회를 하지 않는다 — 일반 GET으로 받아지는 공개 HTML/API만 쓴다.
- 네이버 요청 사이에는 `sleep`으로 딜레이를 두고, 연속 실패가 이어지면 중단한다(차단 의심).
