#!/usr/bin/env python3
"""Run the production timeline state with deterministic async Swift Testing, without Xcode."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = root / 'Dog_kindergarden/Dog_kindergarden'


def declaration(source, start):
    begin = source.index(start)
    opening = source.index('{', begin)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end]


with tempfile.TemporaryDirectory(prefix='diary-async-') as tmp:
    package = Path(tmp)
    sources = package / 'Sources/Dog_kindergarden'
    tests = package / 'Tests/DiaryTests'
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DiaryAsyncRegression", platforms: [.macOS(.v14)], targets: [.target(name: "Dog_kindergarden"), .testTarget(name: "DiaryTests", dependencies: ["Dog_kindergarden"])])
''')
    dto = (app / 'APIClient.swift').read_text()
    phase = (app / 'Views/AsyncLoadState.swift').read_text()
    (sources / 'DTO.swift').write_text('import Foundation\n' + '\n'.join(
        declaration(dto, name) for name in ['struct DiaryPhoto:', 'struct DiaryEntry:', 'enum APIError:']
    ) + '\n' + declaration(phase, 'enum AsyncLoadPhase:'))
    (sources / 'DiaryTimelineState.swift').write_text((app / 'Views/Diary/DiaryTimelineState.swift').read_text())
    (tests / 'DiaryTimelineStateTests.swift').write_text(
        (root / 'Dog_kindergarden/Dog_kindergardenTests/DiaryTimelineStateTests.swift').read_text()
    )
    subprocess.run(
        ['swift', 'test', '--disable-sandbox', '--package-path', tmp, '--scratch-path', str(package / '.build')],
        check=True,
        env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(package / 'module-cache'),
             'SWIFTPM_MODULECACHE_OVERRIDE': str(package / 'module-cache')},
    )

# Supplement the executed state tests with the SwiftUI wiring contract; no simulator is used here.
view = (app / 'Views/Diary/DiaryTimelineView.swift').read_text()
timeline_view = view.split('// MARK: - Composer', 1)[0]
assert '.task(id: timelineIdentity)' in timeline_view
assert '.onDisappear { timeline.invalidate() }' in timeline_view
assert 'defer { timeline.invalidate(lease: lease) }' in timeline_view
assert 'currentIdentity: { timelineIdentity }' in timeline_view
assert 'composerContext = (identity, timeline.lease)' in timeline_view
assert 'reservationId: savedContext.identity.reservationId' in timeline_view
access_dismiss = timeline_view.split('.onChange(of: timeline.accessFailureRevision)', 1)[1].split('.sheet(', 1)[0]
assert 'composer = nil' in access_dismiss and 'isGalleryPresented = false' in access_dismiss
assert 'galleryPhotos = []' in access_dismiss
assert '.onChange(of: timeline.loadPhase)' not in timeline_view, 'Ordinary refresh failures must preserve presentations'
assert '.sheet(item: $composer)' in timeline_view
assert '.fullScreenCover(isPresented: $isGalleryPresented)' in timeline_view
assert '.id(' not in timeline_view, 'Refresh must not replace the timeline/presentation identity'
load_action = timeline_view.split('private func load(', 1)[1].split('private func presentComposer(', 1)[0]
assert 'composer =' not in load_action and 'galleryPhotos =' not in load_action
assert 'DiaryTimelineGrouping.groups(entries)' in timeline_view
assert 'if canWrite' in timeline_view and 'Button("수정")' in timeline_view and 'Button("삭제"' in timeline_view
assert '.disabled(timeline.deletingIDs.contains(entry.id))' in timeline_view
assert 'DiaryPhotoPolicy.maxPhotoCount' in view
print('PASS SwiftUI wiring: context task/lifecycle guards, captured composer context, stable refresh presentations, owner-only pending delete')
