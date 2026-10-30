#!/usr/bin/env python3
"""Run Swift Testing against the real diary DTO and day-group helper, without Xcode."""
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


with tempfile.TemporaryDirectory(prefix='diary-day-groups-') as tmp:
    package = Path(tmp)
    sources = package / 'Sources/Dog_kindergarden'
    tests = package / 'Tests/DiaryTests'
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "DiaryDayGroupsRegression", platforms: [.macOS(.v14)], targets: [.target(name: "Dog_kindergarden"), .testTarget(name: "DiaryTests", dependencies: ["Dog_kindergarden"])])
''')
    dto = (app / 'APIClient.swift').read_text()
    (sources / 'DTO.swift').write_text('import Foundation\n' + '\n'.join(
        declaration(dto, name) for name in ['struct DiaryPhoto:', 'struct DiaryEntry:']
    ))
    (sources / 'DiaryTimelineGrouping.swift').write_text(
        (app / 'Views/Diary/DiaryTimelineGrouping.swift').read_text()
    )
    (tests / 'DiaryTimelineGroupingTests.swift').write_text(
        (root / 'Dog_kindergarden/Dog_kindergardenTests/DiaryTimelineGroupingTests.swift').read_text()
    )
    subprocess.run(
        ['swift', 'test', '--disable-sandbox', '--package-path', tmp, '--scratch-path', str(package / '.build')],
        check=True,
        env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(package / 'module-cache'),
             'SWIFTPM_MODULECACHE_OVERRIDE': str(package / 'module-cache')},
    )
