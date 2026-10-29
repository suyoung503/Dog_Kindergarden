#!/usr/bin/env python3
"""Booking calendar/state regressions without starting Xcode or a simulator."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'Dog_kindergarden/Dog_kindergarden'
VIEW = APP / 'Views/Booking/BookingView.swift'
CALENDAR = APP / 'Views/Booking/BookingCalendar.swift'
TESTS = ROOT / 'Dog_kindergarden/Dog_kindergardenTests/BookingCalendarTests.swift'

class BookingWiringTests(unittest.TestCase):
    def test_outer_dog_card_has_selection_outline(self):
        section = VIEW.read_text().split('private var dogSection: some View {', 1)[1].split('// MARK: - Guardian', 1)[0]
        card = section.split('.frame(width: 100)', 1)[1].split('if let pet = vm.selectedPet', 1)[0]
        self.assertIn('.overlay(', card, '100pt dog card has no outer selection outline')
        self.assertIn('RoundedRectangle(cornerRadius: Radius.xl)', card)
        self.assertIn('.strokeBorder(vm.selectedPetId == pet.pet_id ? Color.brandOrange : Color.brandBeigeBorder, lineWidth: 2)', card)

    def test_dynamic_confirmation_panel_reserves_actual_scroll_height(self):
        body = VIEW.read_text().split('struct BookingView: View {', 1)[1].split('// MARK: - Nav', 1)[0]
        self.assertIn('.safeAreaInset(edge: .bottom', body, 'Fixed overlay still obscures the final price guidance')
        self.assertNotIn('ZStack(alignment: .bottom)', body)
        self.assertNotIn('.padding(.bottom, 80)', body)
        self.assertNotIn('.ignoresSafeArea(.keyboard', body)
        self.assertIn('guardianSection', body)
        self.assertIn('requestSection', body)

    def test_native_calendar_not_wrapped_in_dismiss_tap(self):
        source = VIEW.read_text()
        body = source.split('struct BookingView: View {', 1)[1].split('// MARK: - Nav', 1)[0]
        self.assertNotRegex(body, r'dateTimeSection\s*\.simultaneousGesture')
        self.assertIn('BookingCalendar(selection: $vm.selectedDate)', source)
        self.assertNotIn('in: Date()...', source)
        section = source.split('private var dateTimeSection: some View {', 1)[1].split('// MARK: - Service', 1)[0]
        self.assertIn('.environment(\\.timeZone, BookingCalendarState.calendar.timeZone)', section)

    def test_submit_normalizes_stale_day_before_starting_async_work(self):
        submit = VIEW.read_text().split('private func submitBooking() {', 1)[1].split('// MARK: - Helpers', 1)[0]
        normalization = 'vm.selectedDate = BookingCalendarState(selection: vm.selectedDate).selectedDate'
        self.assertIn(normalization, submit, 'A tap immediately after midnight can submit yesterday before deferred UIKit normalization runs')
        self.assertLess(submit.index(normalization), submit.index('Task {'))

    def test_native_delegate_separates_navigation_and_selection(self):
        self.assertTrue(CALENDAR.exists(), 'Calendar has no separate selected-day / visible-month state')
        source = CALENDAR.read_text()
        self.assertIn('UICalendarSelectionSingleDate', source)
        self.assertIn('calendarView.tintColor = .black', source)
        self.assertIn('didChangeVisibleDateComponentsFrom', source)
        browse = source.split('didChangeVisibleDateComponentsFrom', 1)[1].split('\n        }', 1)[0]
        self.assertNotIn('parent.selection =', browse)
        self.assertIn('state.browse', browse)
        self.assertIn('sizeThatFits', source)

    def test_actual_calendar_state(self):
        self.assertTrue(CALENDAR.exists(), 'Calendar state feature is missing')
        with tempfile.TemporaryDirectory(prefix='booking-calendar-') as tmp:
            package = Path(tmp)
            (package / 'Sources/BookingCalendarRegression').mkdir(parents=True)
            (package / 'Tests/BookingCalendarRegressionTests').mkdir(parents=True)
            (package / 'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "BookingCalendarRegression", products: [.library(name: "BookingCalendarRegression", targets: ["BookingCalendarRegression"])], targets: [.target(name: "BookingCalendarRegression"), .testTarget(name: "BookingCalendarRegressionTests", dependencies: ["BookingCalendarRegression"])])\n')
            shutil.copyfile(CALENDAR, package / 'Sources/BookingCalendarRegression/BookingCalendar.swift')
            (package / 'Tests/BookingCalendarRegressionTests/BookingCalendarTests.swift').write_text(TESTS.read_text().replace('@testable import Dog_kindergarden', '@testable import BookingCalendarRegression'))
            subprocess.run(['swift', 'test', '--build-system', 'native', '--disable-sandbox', '--cache-path', str(package / 'cache'), '--config-path', str(package / 'config'), '--security-path', str(package / 'security'), '--package-path', str(package), '--scratch-path', str(package / 'build')], env={**os.environ, 'CLANG_MODULE_CACHE_PATH': str(package / 'module-cache'), 'SWIFTPM_MODULECACHE_OVERRIDE': str(package / 'module-cache')}, check=True)

if __name__ == '__main__':
    unittest.main()
