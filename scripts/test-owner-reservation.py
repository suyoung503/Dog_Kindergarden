#!/usr/bin/env python3
"""Run real Swift Testing against production owner reservation state without Xcode."""
from pathlib import Path
import subprocess, tempfile, os
root = Path(__file__).resolve().parents[1]
app = root / 'Dog_kindergarden/Dog_kindergarden'
def declaration(source, start):
    begin = source.index(start); opening = source.index('{', begin)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[begin:end]
with tempfile.TemporaryDirectory(prefix='owner-reservation-tests-') as tmp:
    package = Path(tmp)
    (package / 'Sources/Dog_kindergarden').mkdir(parents=True)
    router = (app / 'Views/Navigation/AppRouter.swift').read_text().replace('import SwiftUI', 'import Foundation')
    stubs = 'struct MapPin: Codable { var storeKey: String = "" }; struct Notice {}; enum ReviewTag: Hashable {}; struct MapBounds {}\n'
    (package / 'Sources/Dog_kindergarden/AppRouter.swift').write_text(stubs + router)
    (package / 'Tests/OwnerTests').mkdir(parents=True)
    (package / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OwnerReservationRegression", platforms: [.macOS(.v14)], targets: [.target(name: "Dog_kindergarden"), .testTarget(name: "OwnerTests", dependencies: ["Dog_kindergarden"])])
''')
    dto = declaration((app / 'APIClient.swift').read_text(), 'struct PendingReservation:')
    (package / 'Sources/Dog_kindergarden/DTO.swift').write_text('import Foundation\n' + dto + '\n' + declaration((app / 'APIClient.swift').read_text(), 'enum APIError:'))
    model = app / 'Views/Owner/OwnerReservationState.swift'
    if model.exists():
        (package / 'Sources/Dog_kindergarden/OwnerReservationState.swift').write_text(model.read_text())
    calendar = app / 'Views/Owner/OwnerReservationCalendar.swift'
    if calendar.exists():
        (package / 'Sources/Dog_kindergarden/OwnerReservationCalendar.swift').write_text(calendar.read_text())
    (package / 'Tests/OwnerTests/OwnerCalendarTests.swift').write_text((root / 'Dog_kindergarden/Dog_kindergardenTests/OwnerCalendarTests.swift').read_text())
    (package / 'Tests/OwnerTests/OwnerReservationTests.swift').write_text((root / 'Dog_kindergarden/Dog_kindergardenTests/OwnerReservationTests.swift').read_text())
    subprocess.run(['swift', 'test', '--disable-sandbox', '--package-path', tmp, '--scratch-path', str(package / '.build')], check=True, env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(package / 'module-cache'), 'SWIFTPM_MODULECACHE_OVERRIDE': str(package / 'module-cache')})
