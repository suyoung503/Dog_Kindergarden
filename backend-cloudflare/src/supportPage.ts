const supportPageHTML = `<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light">
  <title>맡겨멍 고객지원</title>
  <style>
    :root { color: #3f2d25; background: #fffaf3; font-family: -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif; }
    body { margin: 0; line-height: 1.68; }
    main { width: min(760px, calc(100% - 40px)); margin: 0 auto; padding: 48px 0 72px; }
    h1 { font-size: 2rem; line-height: 1.25; margin: 0 0 8px; }
    h2 { margin-top: 36px; padding-top: 8px; border-top: 1px solid #eaded2; font-size: 1.2rem; }
    p, li { font-size: 0.96rem; }
    .meta { color: #765f52; }
    .contact { margin: 28px 0; padding: 20px; border-radius: 16px; background: #fff0dc; }
    .contact strong { display: block; margin-bottom: 4px; }
    a { color: #9a4f24; }
    footer { margin-top: 48px; color: #765f52; font-size: 0.88rem; }
  </style>
</head>
<body>
<main>
  <h1>맡겨멍 고객지원</h1>
  <p class="meta">가게 탐색, 예약, 계정 이용 중 도움이 필요하면 아래 방법으로 문의해 주세요.</p>

  <section class="contact">
    <strong>이메일 문의</strong>
    <a href="mailto:yikum503@naver.com">yikum503@naver.com</a>
    <p>앱에서는 <strong>마이페이지 → 1:1 문의</strong>를 이용할 수 있습니다.</p>
  </section>

  <h2>로그인과 계정</h2>
  <p>맡겨멍은 카카오 계정으로 로그인합니다. 로그아웃과 회원 탈퇴는 앱의 마이페이지에서 진행할 수 있습니다. 로그인이 반복해서 실패한다면 사용 기종과 iOS 버전, 오류가 발생한 화면을 함께 알려주세요.</p>

  <h2 id="account-deletion">회원 탈퇴와 데이터 삭제</h2>
  <ol>
    <li>앱에 로그인한 뒤 <strong>마이페이지 → 회원 탈퇴</strong>를 엽니다.</li>
    <li>삭제되는 정보와 남을 수 있는 최소 기록을 확인하고 탈퇴 버튼과 최종 확인을 누릅니다.</li>
    <li>현재 진행 중인 내 예약이나 내 가게 예약이 있으면 완료하거나 취소한 뒤 다시 요청합니다. 오류가 나면 탈퇴 완료로 간주하지 말고 화면 안내를 확인해 주세요.</li>
  </ol>
  <p>탈퇴가 완료되면 모든 기기의 맡겨멍 세션이 폐기되고, 프로필·반려견·찜·본인 고객센터 대화와 보호자 예약의 알림장 등을 삭제·처리합니다. 사진 조회 연결은 먼저 제거하고, 저장소 삭제가 실패하면 삭제 대기 기록으로 재시도합니다. 사장님 탈퇴 시 가게 연결은 종료되지만 다른 보호자의 예약별 기록까지 일괄 삭제되지는 않습니다.</p>
  <p>최소 예약 기록·내부 사용자 번호·별점/태그 등 남는 기록과 보유기간은 <a href="/privacy">개인정보처리방침</a>에서 확인할 수 있습니다. 표시 이름 제거가 모든 기록의 완전한 익명화를 뜻하지는 않습니다.</p>
  <p>탈퇴는 카카오 계정 자체를 삭제하는 것이 아닙니다. 재가입 시 새 맡겨멍 계정으로 처리하며 이전 데이터를 자동 복구하지 않습니다. 위 앱 내 탈퇴 절차에 이메일이나 전화 상담은 필수가 아닙니다. 앱 로그인에 접근할 수 없는 경우에만 위 이메일로 도움을 요청해 주세요. 비밀번호·카카오 액세스 토큰·신분증 원본을 보내지 마세요.</p>

  <h2>가게와 예약</h2>
  <p>앱에서 예약 기능이 활성화된 파트너 가게에 예약을 요청할 수 있습니다. 예약 요청만으로 이용이 확정되거나 결제가 완료되는 것은 아니며, 가게의 확정 상태를 확인해 주세요.</p>

  <h2>사장님 가게 등록</h2>
  <p>사장님 계정으로 전환한 뒤 가게를 찾아 등록을 신청할 수 있습니다. 실제 가게 운영자 확인과 관리자 승인을 마쳐야 예약·채팅 등 파트너 기능을 이용할 수 있습니다.</p>

  <h2>개인정보 문의</h2>
  <p>개인정보의 열람, 정정, 삭제와 처리 관련 문의는 위 이메일 또는 앱의 1:1 문의로 접수해 주세요. 자세한 내용은 <a href="/privacy">개인정보처리방침</a>에서 확인할 수 있습니다.</p>

  <footer>맡겨멍 고객지원 · <a href="/privacy">개인정보처리방침</a> · <a href="/terms">이용약관(출시 준비안)</a></footer>
</main>
</body>
</html>`;

export { supportPageHTML };
