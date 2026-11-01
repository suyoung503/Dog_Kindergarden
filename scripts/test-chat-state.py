#!/usr/bin/env python3
"""Execute the production chat model with deterministic asynchronous Swift tests."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = root / 'Dog_kindergarden/Dog_kindergarden'


def declaration(source, marker):
    begin = source.index(marker)
    opening = source.index('{', begin)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end]


with tempfile.TemporaryDirectory(prefix='chat-state-') as tmp:
    package = Path(tmp)
    sources = package / 'Sources/Dog_kindergarden'
    tests = package / 'Tests/ChatTests'
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ChatStateRegression", platforms: [.macOS(.v14)], targets: [.target(name: "Dog_kindergarden"), .testTarget(name: "ChatTests", dependencies: ["Dog_kindergarden"])])
''')
    view = (app / 'Views/Chat/ChatRoomView.swift').read_text()
    model = view.split('struct ChatRoomView: View')[0].replace('import SwiftUI', 'import Foundation')
    dto = declaration((app / 'Views/Chat/ChatService.swift').read_text(), 'struct ChatMessageDTO:')
    error = declaration((app / 'APIClient.swift').read_text(), 'enum APIError:')
    # Live defaults must never perform network or touch the real Keychain in this harness.
    stubs = '''
enum AuthTokenStore { static func load() -> String? { nil } }
enum APIEnvironment { static var apiBaseURL: URL { URL(string: "https://unused.invalid/api")! } }
enum ChatService {
    static func messages(roomId: Int) async throws -> [ChatMessageDTO] { throw URLError(.unsupportedURL) }
    static func openRoom(userId: Int, storeKey: String, storeName: String, storeAddress: String) async throws -> Int { throw URLError(.unsupportedURL) }
    static func send(roomId: Int, senderId: Int, content: String) async throws { throw URLError(.unsupportedURL) }
    static func markRead(roomId: Int, userId: Int) async {}
}
'''
    (sources / 'Model.swift').write_text(model + '\n' + dto + '\n' + error + '\n' + stubs)
    (tests / 'ChatRoomStateTests.swift').write_text((root / 'Dog_kindergarden/Dog_kindergardenTests/ChatRoomStateTests.swift').read_text())
    subprocess.run(
        ['swift', 'test', '--disable-sandbox', '--package-path', tmp, '--scratch-path', str(package / '.build')],
        check=True, timeout=240,
        env={**os.environ, 'CLANG_MODULE_CACHE_PATH': '/tmp/matgyeomung-chat-module-cache',
             'SWIFTPM_MODULECACHE_OVERRIDE': '/tmp/matgyeomung-chat-module-cache'},
    )

# Structural wiring checks supplement, not replace, the real model tests above.
for expected in ['.task(id: chatIdentity)', 'vm.invalidate(generation: generation)',
                 'ForEach(displayedMessages)', 'text: draftBinding', '.onSubmit(sendMessage)',
                 'Button(action: sendMessage)', '.disabled(vm.isSending',
                 'vm.generation == generation, vm.identity == expected, chatIdentity == expected',
                 '.onChange(of: displayedMessages.last?.id)']:
    assert expected in view, f'Missing chat lifecycle wiring: {expected}'
print('PASS SwiftUI chat wiring: scoped task, invalidation, hidden stale data/draft, captured send and busy button')
