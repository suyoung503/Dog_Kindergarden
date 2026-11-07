#!/usr/bin/env node
// 실제 공개 라우트는 인증·DB 없이 열리며 고지는 구현된 삭제 범위를 설명해야 한다.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { build } from 'esbuild';
import * as miniflare from 'miniflare';

const bundle = await build({ entryPoints: [new URL('../src/index.ts', import.meta.url).pathname],
  bundle: true, platform: 'neutral', format: 'esm', write: false, external: ['cloudflare:*'] });
const options = { name: 'legal-pages-test', modules: true, script: bundle.outputFiles[0].text,
  compatibilityDate: '2026-05-20' };
const mf = new miniflare.Miniflare(miniflare.convertV4MiniflareOptions ? miniflare.convertV4MiniflareOptions(options) : options);
try {
  await test('이용약관·개인정보·탈퇴 공개 안내', { timeout: 30000 }, async t => {
    for (const [path, title] of [['/terms', '맡겨멍 이용약관'], ['/privacy', '맡겨멍 개인정보처리방침'], ['/support', '맡겨멍 고객지원']]) {
      await t.test(`${path}: 인증·DB 없이 HTML과 보안 헤더를 제공한다`, async () => {
        const response = await mf.dispatchFetch(`https://example.com${path}`);
        assert.equal(response.status, 200);
        assert.match(response.headers.get('content-type'), /text\/html/);
        assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
        assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
        assert.match(response.headers.get('content-security-policy'), /default-src 'none'/);
        assert.match(response.headers.get('cache-control'), /public, max-age=3600/);
        const html = await response.text();
        assert.ok(html.includes(title));
        assert.match(html, /<html lang="ko">/);
        assert.doesNotMatch(html, /<script|<form|javascript:/i);
        for (const link of html.matchAll(/href="(\/[^"<>]*)"/g)) {
          const target = new URL(link[1], 'https://example.com');
          const linked = await mf.dispatchFetch(target.href);
          assert.equal(linked.status, 200, link[1]);
          if (target.hash) assert.ok((await linked.text()).includes(`id="${target.hash.slice(1)}"`), link[1]);
        }
      });
    }
    await t.test('미확정 약관은 준비안·미시행이고 로그인 동의를 주장하지 않는다', async () => {
      const html = await (await mf.dispatchFetch('https://example.com/terms')).text();
      for (const text of ['출시 준비안', '미시행', '운영자', 'yikum503@naver.com', '앱 내 결제', '동의로 간주하지 않습니다']) assert.ok(html.includes(text), text);
      assert.doesNotMatch(html, /동의한 것으로|모든 책임을 지지 않/);
    });
    await t.test('탈퇴 고지는 지연 사진 삭제·역할별 기록·재가입 경계를 설명한다', async () => {
      const html = await (await mf.dispatchFetch('https://example.com/privacy')).text();
      for (const text of ['삭제 대기', '재시도', '내부 사용자 번호', '사장님', '재가입', '7일']) assert.ok(html.includes(text), text);
      const support = await (await mf.dispatchFetch('https://example.com/support')).text();
      assert.match(support, /id="account-deletion"/);
      assert.ok(support.includes('마이페이지 → 회원 탈퇴'));
      assert.ok(support.includes('카카오 계정 자체'));
    });
    await t.test('로그인 전·후 약관과 탈퇴 시 보유기간 열람 연결을 유지한다', async () => {
      const app = new URL('../../Dog_kindergarden/Dog_kindergarden/', import.meta.url);
      const start = await readFile(new URL('Views/Start/StartView.swift', app), 'utf8');
      const page = await readFile(new URL('Views/MyPage/MyPageView.swift', app), 'utf8');
      assert.match(start, /Link\("이용약관\(준비안\)".*APIEnvironment\.termsOfServiceURL/);
      assert.match(page, /label: "이용약관"/);
      assert.match(page, /open\(APIEnvironment\.termsOfServiceURL\)/);
      assert.match(page, /Link\("개인정보 보유기간 확인".*APIEnvironment\.privacyPolicyURL/);
      for (const text of ['삭제 대기', '재시도', '카카오 계정 자체']) assert.ok(page.includes(text), text);
    });
    await t.test('공개 문서 추가가 회원 탈퇴 API 인증을 열지 않는다', async () => {
      const response = await mf.dispatchFetch('https://example.com/api/users/1/account', { method: 'DELETE' });
      assert.equal(response.status, 401);
      assert.equal(response.headers.get('cache-control'), 'private, no-store');
    });
  });
} finally { await mf.dispose(); }
