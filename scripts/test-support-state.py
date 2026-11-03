#!/usr/bin/env python3
"""Execute the production support model with deterministic asynchronous Swift tests."""
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


with tempfile.TemporaryDirectory(prefix='support-state-') as tmp:
    package = Path(tmp)
    sources = package / 'Sources/Dog_kindergarden'
    tests = package / 'Tests/SupportTests'
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SupportStateRegression", platforms: [.macOS(.v14)], targets: [.target(name: "Dog_kindergarden"), .testTarget(name: "SupportTests", dependencies: ["Dog_kindergarden"])])
''')
    view = (app / 'Views/MyPage/SupportViews.swift').read_text()
    model = view.split('struct SupportConversationView: View')[0].replace('import SwiftUI', 'import Foundation')
    dto = (app / 'APIClient.swift').read_text()
    declarations = '\n'.join(declaration(dto, marker) for marker in [
        'struct SupportConversation:', 'struct SupportConversationStatus:',
        'struct SupportMessageResponse:', 'enum APIError:',
    ])
    # Never use the real transport, Keychain, or live service in this local harness.
    stubs = '''
final class APIClient {
    static let shared = APIClient()
    func fetchMySupportConversation() async throws -> SupportConversationStatus { throw URLError(.unsupportedURL) }
    func openSupportConversation() async throws -> SupportConversation { throw URLError(.unsupportedURL) }
    func fetchSupportMessages(conversationId: Int) async throws -> [SupportMessageResponse] { throw URLError(.unsupportedURL) }
    func sendSupportMessage(conversationId: Int, content: String) async throws -> SupportMessageResponse { throw URLError(.unsupportedURL) }
}
'''
    (sources / 'Model.swift').write_text(model + '\n' + declarations + '\n' + stubs)
    (tests / 'SupportConversationStateTests.swift').write_text(
        (root / 'Dog_kindergarden/Dog_kindergardenTests/SupportConversationStateTests.swift').read_text()
    )
    subprocess.run(
        ['swift', 'test', '--disable-sandbox', '--package-path', tmp,
         '--scratch-path', str(package / '.build'), '--cache-path', str(package / 'cache'),
         '--config-path', str(package / 'config'), '--security-path', str(package / 'security')],
        check=True, timeout=240,
        env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(package / 'module-cache'),
             'SWIFTPM_MODULECACHE_OVERRIDE': str(package / 'module-cache')},
    )

# Supplement the executed model tests with the SwiftUI lifecycle wiring contract.
for expected in ['.task(id: conversationContext)', 'defer { viewModel.invalidate(generation: generation) }',
                 'configuredContext = nil', '.onDisappear {', 'ForEach(displayedMessages)',
                 'text: draftBinding', '.onSubmit(sendMessage)', 'Button(action: sendMessage)',
                 'viewModel.generation == generation', 'conversationContext == context']:
    assert expected in view, f'Missing support lifecycle wiring: {expected}'
print('PASS SwiftUI support wiring: context task, cancellation/invalidation, hidden stale data/draft, captured send')
