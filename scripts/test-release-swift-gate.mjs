#!/usr/bin/env node
// Execute the real release driver. Only unrelated build/DB gates and child
// Python processes are fixtures; CLI selection, I08, reporting and exit stay real.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';

const script = fileURLToPath(new URL('./release-audit-smoke.sh', import.meta.url));
const source = await readFile(script, 'utf8');
const boundary = source.indexOf('echo "맡겨멍 Release Audit smoke 시작"');
assert.ok(boundary > 0, 'release driver entry point is missing');
const prefix = source.slice(0, boundary);
const rest = source.slice(boundary);
const children = ['test-list-mutations.py', 'test-account-deletion-state.py',
  'test-calendar-service.py', 'test-review-state.py', 'test-booking-submission.py'];
const unrelated = ['check_tools', 'check_repository_state', 'check_tracked_sensitive_files',
  'validate_app_icon', 'validate_privacy_declarations', 'check_ios_server_secrets',
  'check_repository_consistency', 'backend_dry_run', 'backend_migrations', 'start_worker',
  'backend_regression', 'ios_release_bundle_gate', 'ios_app_source_warning_gate',
  'ios_minimum_version_gate', 'ios_store_identity_gate', 'ios_privacy_manifest_gate',
  'ios_permission_declarations_gate'].map(name => `${name}() { return 0; }`).join('\n');
const fixtures = `${unrelated}\nios_release_build() { return "$BUILD_FAIL"; }\n`;

await test('Release Swift regression gate', async t => {
  const work = await mkdtemp(join(tmpdir(), 'release-swift-gate-'));
  try {
    const bin = join(work, 'bin'); await mkdir(bin);
    await writeFile(join(bin, 'python3'), `#!/bin/bash
printf '%s\\n' "$(basename "$1")" >> "$CALLS_FILE"
if [ "$(basename "$1")" = "$FAIL_SWIFT" ]; then echo 'fixture regression failure'; exit 23; fi
echo 'fixture regression passed'
`, { mode: 0o755 });
    const run = (name, args = [], extra = {}, body = prefix + fixtures + rest) => {
      const result = spawnSync('bash', ['-c', body, script, ...args], {
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RESULT_DIR: join(work, name),
          CALLS_FILE: join(work, `${name}.calls`), FAIL_SWIFT: '', BUILD_FAIL: '0', ...extra },
        encoding: 'utf8', timeout: 15000,
      });
      assert.ifError(result.error);
      return result;
    };
    const calls = async name => (await readFile(join(work, `${name}.calls`), 'utf8').catch(error => {
      if (error.code === 'ENOENT') return ''; throw error;
    })).trim().split('\n').filter(Boolean);
    const summary = name => readFile(join(work, name, 'summary.tsv'), 'utf8');

    for (const [name, args] of [['full', []], ['ios', ['--ios-only']]]) {
      await t.test(`${name}: all five regressions run and are reported`, async () => {
        const result = run(name, args);
        assert.equal(result.status, 0, result.stdout + result.stderr);
        assert.deepEqual(await calls(name), children);
        assert.match(await summary(name), /^I08\tPASS\t/m);
      });
    }
    await t.test('a failing child stops this group and fails the final release result', async () => {
      const result = run('failure', [], { FAIL_SWIFT: children[2] });
      assert.equal(result.status, 1, result.stdout + result.stderr);
      assert.deepEqual(await calls('failure'), children.slice(0, 3));
      assert.match(await summary('failure'), /^I08\tFAIL\t/m);
      assert.match(await summary('failure'), /^I01\tPASS\t/m);
      assert.match(await readFile(join(work, 'failure/logs/I08.log'), 'utf8'), /fixture regression failure/);
      assert.match(await readFile(join(work, 'failure/release-smoke-result.md'), 'utf8'), /종합 결과: \*\*FAIL\*\*/);
    });
    for (const [name, args] of [['backend', ['--backend-only']], ['quick', ['--quick']]]) {
      await t.test(`${name}: Swift is explicitly skipped, not marked passed`, async () => {
        const result = run(name, args);
        assert.equal(result.status, 0, result.stdout + result.stderr);
        assert.deepEqual(await calls(name), []);
        assert.match(await summary(name), /^I08\tSKIP\t/m);
      });
    }
    await t.test('Swift regressions are independent of Simulator build failure', async () => {
      const result = run('build-failure', [], { BUILD_FAIL: '1' });
      assert.equal(result.status, 1, result.stdout + result.stderr);
      assert.deepEqual(await calls('build-failure'), children);
      assert.match(await summary('build-failure'), /^I08\tPASS\t/m);
      assert.match(await summary('build-failure'), /^I01\tFAIL\t/m);
    });
    for (const tool of ['python3', 'swiftc', 'xcrun']) {
      await t.test(`full iOS preflight reports missing ${tool}`, () => {
        const probe = `\ncommand() { [ "$2" != "$MISSING_TOOL" ]; }\ncheck_tools\n`;
        const result = run(`missing-${tool}`, ['--ios-only'], { MISSING_TOOL: tool }, prefix + probe);
        assert.equal(result.status, 1, result.stdout + result.stderr);
        assert.match(result.stdout, new RegExp(`도구 없음:.*${tool}`));
      });
    }
    for (const [name, args] of [['no-tools-backend', ['--backend-only']], ['no-tools-quick', ['--quick']]]) {
      await t.test(`${name}: preflight does not require skipped Swift tools`, () => {
        const probe = `\ncommand() { case "$2" in python3|swiftc|xcrun) return 1 ;; *) return 0 ;; esac; }\ncheck_tools\n`;
        const result = run(name, args, {}, prefix + probe);
        assert.equal(result.status, 0, result.stdout + result.stderr);
      });
    }
  } finally {
    await rm(work, { recursive: true, force: true });
  }
});
