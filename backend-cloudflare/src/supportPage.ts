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

  <h2>가게와 예약</h2>
  <p>앱에서 예약 기능이 활성화된 파트너 가게에 예약을 요청할 수 있습니다. 예약 요청만으로 이용이 확정되거나 결제가 완료되는 것은 아니며, 가게의 확정 상태를 확인해 주세요.</p>

  <h2>사장님 가게 등록</h2>
  <p>사장님 계정으로 전환한 뒤 가게를 찾아 등록을 신청할 수 있습니다. 실제 가게 운영자 확인과 관리자 승인을 마쳐야 예약·채팅 등 파트너 기능을 이용할 수 있습니다.</p>

  <h2>개인정보 문의</h2>
  <p>개인정보의 열람, 정정, 삭제와 처리 관련 문의는 위 이메일 또는 앱의 1:1 문의로 접수해 주세요. 자세한 내용은 <a href="/privacy">개인정보처리방침</a>에서 확인할 수 있습니다.</p>

  <footer>맡겨멍 고객지원 · <a href="/privacy">개인정보처리방침</a></footer>
</main>
</body>
</html>`;

export { supportPageHTML };
