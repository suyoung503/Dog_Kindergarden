# 맡겨멍 App Icon 출시 점검

**점검일:** 2026-10-18  
**대상:** `Dog_kindergarden/Dog_kindergarden/Assets.xcassets/AppIcon.appiconset`

<img src="../Dog_kindergarden/Dog_kindergarden/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" alt="맡겨멍 App Icon" width="180">

## 점검 결과

| 항목 | 결과 | 확인 내용 |
|---|---|---|
| 기본 아이콘 연결 | 통과 | `Contents.json`의 iOS universal 1024×1024 기본 슬롯이 `AppIcon-1024.png` 한 파일을 참조 |
| 픽셀 크기 | 통과 | 1024×1024 |
| 파일 형식 | 통과 | 8-bit RGB PNG |
| 투명도 | 통과 | alpha와 `tRNS` 투명도 청크 없음 |
| 시스템 마스킹 | 통과 | 파일 자체는 정사각형이며 바깥 모서리를 투명하게 잘라내지 않음 |
| 작은 크기 식별성 | 통과 | 180px와 60px 축소 확인에서 강아지·집·브랜드 색상 식별 가능 |
| Release 포함 | 통과 | Asset Catalog를 사용한 iOS Simulator Release 빌드 성공 |

Apple은 iOS App Icon의 기본 레이아웃을 1024×1024 정사각형으로 안내하며, 시스템이 최종 둥근 모서리와 작은 크기 변형을 적용한다. 현재 단일 1024×1024 기본 이미지를 사용하는 방식은 Xcode의 자동 변형 생성 방식과 맞는다.

## 자동 검사

```bash
node scripts/validate-app-icon.mjs
```

`scripts/release-audit-smoke.sh`의 `A04` 단계가 다음 항목을 매번 확인한다.

1. 기본 iOS 1024×1024 슬롯이 정확히 하나인지
2. 카탈로그에 지정된 파일이 실제로 존재하는지
3. PNG 크기가 정확히 1024×1024인지
4. 8-bit RGB이고 alpha·투명도 청크가 없는지

## 제출 전 수동 보관 항목

Git 이력에는 2026-09-01 아이콘 파일을 추가한 기록이 있지만, 원본 제작 파일이나 외부 제작 도구·라이선스 증빙은 저장되어 있지 않다. 직접 제작한 자산이면 원본 파일을, 외부 도구·디자이너를 사용했다면 상업적 이용 권한을 확인할 수 있는 기록을 비공개 보관한다. 이 확인은 이미지 규격과 별개의 권리 증빙 작업이다.

## 공식 기준

- [Apple Human Interface Guidelines — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Xcode에서 Asset Catalog App Icon 구성](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
