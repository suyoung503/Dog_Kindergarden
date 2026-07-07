# 맡겨멍

반려견을 맡길 수 있는 애견 유치원·호텔을 지도 기반으로 탐색하고 예약하는 iOS 플랫폼입니다.
공공데이터 동물위탁관리업 API로 전국 업체를 지도에 표시하고, 리뷰·채팅·예약·찜하기 기능을 통합 제공합니다.

## 왜 만들었나

기존에는 여러 지도 앱을 오가며 업체를 검색하고, 예약도 전화나 카카오톡으로만 가능해 불편했습니다.
맡겨멍은 지도 탐색부터 예약, 그리고 예약 이후 업체와의 채팅까지 한 앱에서 끝낼 수 있게 만듭니다.

## 주요 기능

- **지도 기반 업체 탐색** — 공공데이터 동물위탁관리업 API + 카카오맵. 뷰포트 안의 업체만 표시하고, 카카오 로컬 API로 마스킹된 주소를 보강합니다.
- **예약** — 날짜·서비스를 선택해 예약 신청. 예약과 동시에 업체와의 채팅방이 자동 생성됩니다.
- **실시간 채팅** — 보호자와 업체 간 1:1 채팅 (사용자+가게 조합당 채팅방 1개).
- **리뷰** — 실제 이용자가 남기는 펫 특화 리뷰(CCTV, 픽업, 대형견 가능 여부 등 태그 포함), 네이버 블로그 후기 연동.
- **찜한 가게** — 가게 상세에서 하트로 찜하고, 마이페이지에서 목록으로 모아보기.
- **카카오 로그인** — 프로필(이름·연락처·주소) 저장 및 수정.

## 구조

모노레포로 구성되어 있습니다.

```
Dog_kindergarden/       iOS 앱 (Swift, SwiftUI + Observation, iOS 16+)
backend-cloudflare/     백엔드 (TypeScript, Hono, Cloudflare Workers + D1)
docs/                   기획·진행상황·포트폴리오 문서
```

- iOS 앱 빌드는 [`Dog_kindergarden/README.md`](Dog_kindergarden/README.md) 참고
- 백엔드 배포는 [`backend-cloudflare/README.md`](backend-cloudflare/README.md) 참고
- 개발 계획·진행상황은 [`docs/PLAN.md`](docs/PLAN.md), [`docs/PROGRESS.md`](docs/PROGRESS.md) 참고

## 기술 스택

| 영역 | 기술 |
|---|---|
| iOS | Swift 5.9, SwiftUI, Observation, CocoaPods |
| 지도 | KakaoMapsSDK, 공공데이터 동물위탁관리업 API (TM→WGS84 좌표 변환 직접 구현) |
| 로그인 | 카카오 로그인 (KakaoSDKAuth/User) |
| 백엔드 | Hono, Cloudflare Workers |
| DB | Cloudflare D1 (SQLite) |
| 배포 | `https://matgyeomung-api.dog-kindergarden.workers.dev` |

## 배포 상태

포트폴리오 완성 후 App Store 출시까지 이어가는 것을 목표로 진행 중입니다. 현재 진행상황은 [`docs/PROGRESS.md`](docs/PROGRESS.md)에서 확인할 수 있습니다.
