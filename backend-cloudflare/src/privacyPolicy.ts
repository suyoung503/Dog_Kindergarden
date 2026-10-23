const privacyPolicyHTML = `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light">
  <title>맡겨멍 개인정보처리방침</title>
  <style>
    :root { color: #3f2d25; background: #fffaf3; font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif; }
    body { margin: 0; line-height: 1.68; }
    main { width: min(860px, calc(100% - 40px)); margin: 0 auto; padding: 48px 0 72px; }
    h1 { font-size: 2rem; line-height: 1.25; margin: 0 0 8px; }
    h2 { margin-top: 40px; padding-top: 8px; border-top: 1px solid #eaded2; font-size: 1.25rem; }
    p, li, td, th { font-size: 0.96rem; }
    .meta, .note { color: #765f52; }
    .note { background: #fff0dc; border-radius: 14px; padding: 16px; }
    table { width: 100%; border-collapse: collapse; display: block; overflow-x: auto; }
    th, td { min-width: 150px; padding: 12px; border: 1px solid #dfd1c4; text-align: left; vertical-align: top; }
    th { background: #f8ecdf; }
    a { color: #9a4f24; }
    footer { margin-top: 48px; color: #765f52; font-size: 0.88rem; }
  </style>
</head>
<body>
<main>
  <h1>맡겨멍 개인정보처리방침</h1>
  <p class="meta">공고일·시행일: 2026년 10월 23일</p>
  <p>맡겨멍(이하 “서비스”)은 이용자의 개인정보를 중요하게 생각하며, 서비스 제공에 필요한 최소한의 정보만 처리합니다.</p>

  <h2>1. 처리하는 개인정보</h2>
  <table>
    <thead><tr><th>구분</th><th>처리 항목</th><th>수집 방법·목적</th></tr></thead>
    <tbody>
      <tr><td>계정·로그인</td><td>카카오 사용자 식별자, 닉네임, 동의한 경우 이메일, 내부 사용자 ID, 보호자·사장님 역할</td><td>카카오 로그인, 이용자 식별과 권한 관리</td></tr>
      <tr><td>프로필</td><td>닉네임, 전화번호, 주소</td><td>이용자가 직접 입력·수정, 예약과 연락 기능 제공</td></tr>
      <tr><td>반려견</td><td>이름, 견종, 나이, 몸무게, 성별, 사회성, 알레르기, 특이사항, 선택한 사진 1장</td><td>반려견 프로필과 예약 기능 제공</td></tr>
      <tr><td>예약·서비스 콘텐츠</td><td>가게, 이용일시, 서비스 종류, 상태, 요청사항, 채팅·문의·알림장 내용과 선택 사진(건당 최대 3장)·리뷰 내용</td><td>예약 처리, 의사소통, 이용 기록과 분쟁 대응</td></tr>
      <tr><td>인증·보안</td><td>세션 토큰의 SHA-256 해시, 생성·만료 시각</td><td>로그인 유지와 부정 접근 방지. 원문 토큰은 서버에 저장하지 않음</td></tr>
    </tbody>
  </table>
  <p>서비스 서버는 기기의 현재 위치·이동 경로, 캘린더 내용, 광고 식별자(IDFA)를 수집하지 않습니다. 캘린더와 알림 권한은 이용자가 해당 기능을 선택한 경우 기기 안에서만 사용합니다.</p>

  <h2>2. 이용 목적</h2>
  <ol>
    <li>로그인, 계정 보안, 보호자·사장님·운영자 권한 구분</li>
    <li>반려견 프로필, 가게 탐색, 찜, 예약, 채팅, 알림장과 리뷰 제공</li>
    <li>사장님 가게 등록 신청의 확인·승인·거절</li>
    <li>고객 문의, 장애 대응, 부정 이용 방지와 분쟁 처리</li>
  </ol>
  <p>개인정보를 맞춤형 광고, 제3자 광고 또는 앱 간 추적 목적으로 사용하지 않습니다.</p>

  <h2>3. 보유기간과 파기</h2>
  <table>
    <thead><tr><th>정보</th><th>보유기간·처리 기준</th></tr></thead>
    <tbody>
      <tr><td>로그인 세션</td><td>발급 후 30일. 로그아웃·탈퇴 시 즉시 폐기하며, 만료된 세션 기록은 만료 후 30일 이내 삭제</td></tr>
      <tr><td>계정·프로필·반려견·찜</td><td>회원 탈퇴 시 서비스 DB에서 즉시 삭제하거나 개인을 알아볼 수 없도록 익명화</td></tr>
      <tr><td>개인 채팅·고객센터 대화·알림장 내용·사진</td><td>회원 탈퇴 시 데이터베이스 기록과 비공개 저장소의 사진 파일 삭제. 계정이 유지되는 동안에는 기능 제공과 문의 이력 확인을 위해 보관</td></tr>
      <tr><td>완료·취소 예약 최소 기록</td><td>계약·청약철회 및 서비스 공급 기록에 관련 법령이 적용되는 경우 완료·취소일부터 5년. 탈퇴 시 요청사항과 계정 식별정보를 먼저 제거하고 기간 종료 후 삭제</td></tr>
      <tr><td>소비자 불만·분쟁 처리 기록</td><td>관련 법령이 적용되는 경우 처리 완료일부터 3년</td></tr>
      <tr><td>사장님 등록 신청·승인 이력</td><td>파트너 관계 중 보관하며, 거절 또는 관계 종료 후 3년 이내 삭제·익명화</td></tr>
      <tr><td>운영자가 생성한 복구용 백업</td><td>생성일부터 30일 이내 안전하게 삭제. 법령상 보존 대상은 별도로 분리해 정해진 기간만 보관</td></tr>
    </tbody>
  </table>
  <p class="note">회원 탈퇴는 앱의 <strong>마이페이지 → 회원 탈퇴</strong>에서 할 수 있습니다. 진행 중인 예약이 있으면 완료하거나 취소한 뒤 탈퇴할 수 있습니다. 탈퇴가 완료되면 모든 기기의 로그인 세션이 폐기되며, 재가입은 새 계정으로 처리됩니다.</p>

  <h2>4. 제3자 제공</h2>
  <p>개인정보를 판매하지 않습니다. 이용자가 예약·채팅·알림장 기능을 요청한 경우 필요한 범위에서 관리자 승인을 받아 연결된 해당 가게 사장님에게 보호자 연락처, 반려견 정보, 예약 요청사항 등이 제공될 수 있습니다. 법령에 따른 요청이나 이용자의 별도 동의가 있는 경우를 제외하고 다른 제3자에게 제공하지 않습니다.</p>

  <h2>5. 외부 서비스와 처리위탁</h2>
  <table>
    <thead><tr><th>사업자·서비스</th><th>목적</th><th>관련 정보</th></tr></thead>
    <tbody>
      <tr><td>Cloudflare, Inc. (Workers, D1, R2)</td><td>API, 데이터베이스와 비공개 이미지 저장소 운영</td><td>서비스 계정, 서버 저장 데이터와 알림장 사진</td></tr>
      <tr><td>Kakao Corp.</td><td>카카오 로그인, 지도와 장소 검색</td><td>로그인 식별정보 및 가게 검색 질의</td></tr>
      <tr><td>NAVER Corp.</td><td>가게·블로그 검색 결과 제공</td><td>가게명과 위치 기반 검색 질의</td></tr>
      <tr><td>Apple Inc.</td><td>기기 캘린더와 알림 기능</td><td>이용자가 허용한 기기 안에서 처리</td></tr>
    </tbody>
  </table>

  <h2>6. 안전성 확보 조치</h2>
  <ul>
    <li>카카오 액세스 토큰을 서버에서 검증한 뒤 맡겨멍 세션 발급</li>
    <li>서버에는 세션 원문 대신 SHA-256 해시만 저장하고 앱 원문은 Keychain에 저장</li>
    <li>보호 API에서 로그인 사용자, 역할, 가게 소유 관계 검사</li>
    <li>관리자 승인된 자기 가게에만 사장님 기능 허용</li>
    <li>알림장 사진은 비공개 저장소에 두고 해당 예약의 보호자와 가게 사장님에게만 인증 후 제공</li>
    <li>HTTPS 통신과 내부 관리 API 비밀키 적용</li>
  </ul>

  <h2>7. 이용자의 권리</h2>
  <p>이용자는 자신의 개인정보에 대해 열람, 정정, 삭제, 처리정지를 요청할 수 있습니다. 프로필은 앱에서 직접 수정할 수 있고 회원 탈퇴도 앱에서 직접 완료할 수 있습니다. 그 밖의 요청은 아래 이메일로 접수해 주세요.</p>

  <h2>8. 만 14세 미만 아동</h2>
  <p>서비스는 만 14세 미만 아동을 대상으로 설계되지 않았으며 법정대리인의 동의 없이 해당 아동의 개인정보를 수집하지 않습니다.</p>

  <h2>9. 개인정보 보호책임자 및 문의</h2>
  <ul>
    <li>책임자: 맡겨멍 운영자</li>
    <li>이메일: <a href="mailto:yikum503@naver.com">yikum503@naver.com</a></li>
  </ul>

  <h2>10. 방침 변경</h2>
  <p>방침이 변경되면 시행 전에 앱 공지사항 또는 이 페이지에서 알립니다. 이용자의 권리에 중대한 영향을 주는 변경은 필요한 경우 별도로 안내합니다.</p>

  <footer>
    <p>법정 보존기간 참고: <a href="https://www.law.go.kr/LSW/lsInfoP.do?lsId=009338" rel="noreferrer">전자상거래 등에서의 소비자보호에 관한 법률 시행령 제6조</a></p>
  </footer>
</main>
</body>
</html>`;

export { privacyPolicyHTML };
