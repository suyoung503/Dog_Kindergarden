#!/usr/bin/env python3
"""Focused production view wiring checks for the approved booking appearance."""
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'Dog_kindergarden/Dog_kindergarden/Views/Booking'
source = (root / 'BookingDoneView.swift').read_text()
card = source.split('private var summaryCard: some View {', 1)[1].split('private func summaryRow', 1)[0]
assert 'RoundedRectangle(cornerRadius: Radius.pill)' not in card, 'Completion summary still has pill-shaped corners'
assert card.count('RoundedRectangle(cornerRadius: Radius.xl)') == 2, 'Fill clipping and outline must both use existing 14pt Radius.xl'
for title in ['가게', '강아지', '일정', '가격 안내']:
    assert title in card
assert 'ScrollView {' in source and '.padding(.top, 96)' in source
print('PASS: completion summary 14pt corners; rows, scrolling and top spacing preserved')

booking = (root / 'BookingView.swift').read_text()
panel = booking.split('private var confirmButton: some View {', 1)[1].split('private func submitBooking', 1)[0]
assert '.padding(.bottom, max(20, bottomPanelInset / 2 + 12))' in panel, 'Use the midpoint between original and raised bottom spacing'
assert '.padding(.top, 12)' in panel, 'Panel top spacing should remain 12pt'
assert '.onAppear { bottomPanelInset = UIApplication.safeAreaBottom }' in booking, 'Read window inset after layout, not during body evaluation'
assert '.safeAreaInset(edge: .bottom, spacing: 0)' in booking, 'Price guidance must still scroll above the measured panel'
assert '.ignoresSafeArea(.keyboard' not in booking
# Execute the exact production bottom-padding expression for flat and home-indicator screens.
import subprocess, tempfile
expression = 'max(20, bottomPanelInset / 2 + 12)'
assert expression in panel
swift = 'import Foundation\nfor (bottomPanelInset, expected) in [(0.0, 20.0), (21.0, 22.5), (34.0, 29.0)] { precondition(' + expression + ' == expected) }\nprint("PASS: bottom spacing 20/22.5/29pt is halfway between original and raised panel positions")\n'
with tempfile.TemporaryDirectory(prefix='booking-panel-') as tmp:
    path = Path(tmp)
    (path / 'Panel.swift').write_text(swift)
    subprocess.run(['swiftc', '-module-cache-path', str(path / 'cache'), str(path / 'Panel.swift'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)
print('PASS: raised confirmation panel retains measured scroll inset and keyboard behavior')
