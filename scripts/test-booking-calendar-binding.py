#!/usr/bin/env python3
"""Run the production coordinator against tiny UIKit surfaces; not a rendered UI test."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Dog_kindergarden/Dog_kindergarden/Views/Booking/BookingCalendar.swift').read_text()
state = source.split('#if canImport(UIKit)', 1)[0]
start = source.index('    final class Coordinator:')
opening = source.index('{', start)
depth, end = 1, opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
coordinator = source[start:end]
shim = '''
@MainActor protocol UICalendarViewDelegate {}
@MainActor protocol UICalendarSelectionSingleDateDelegate {}
@MainActor final class UICalendarSelectionSingleDate {
    var selectedDate: DateComponents?
    func setSelected(_ date: DateComponents?, animated: Bool) { selectedDate = date }
}
@MainActor final class UICalendarView {
    var selectionBehavior: AnyObject? = UICalendarSelectionSingleDate()
    var visibleDateComponents = DateComponents()
    func setVisibleDateComponents(_ date: DateComponents, animated: Bool) { visibleDateComponents = date }
}
@MainActor final class BoundDate { var value: Date; init(_ value: Date) { self.value = value } }
@MainActor struct BookingCalendar {
    var bound: BoundDate
    var onSelect: () -> Void = {}
    var selection: Date { get { bound.value } nonmutating set { bound.value = newValue } }
'''
harness = '''
}
@main struct Regression {
    @MainActor static func settle() async { for _ in 0..<100 { await Task.yield() } }
    @MainActor static func check(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: " + message); exit(1) }
    }
    @MainActor static func view(for coordinator: BookingCalendar.Coordinator) -> UICalendarView {
        let view = UICalendarView()
        (view.selectionBehavior as! UICalendarSelectionSingleDate).setSelected(BookingCalendarState.calendar.dateComponents([.year, .month, .day], from: coordinator.state.selectedDate), animated: false)
        view.setVisibleDateComponents(coordinator.state.visibleMonth, animated: false)
        return view
    }
    @MainActor static func main() async {
        let calendar = BookingCalendarState.calendar
        func day(_ value: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: value))! }
        var now = day(28)
        let bound = BoundDate(day(27))
        let coordinator = BookingCalendar.Coordinator(parent: BookingCalendar(bound: bound), now: { now })
        let view = view(for: coordinator)
        let behavior = view.selectionBehavior as! UICalendarSelectionSingleDate
        coordinator.synchronizeSelection(in: view)
        check(bound.value == day(27), "binding must not be written during UIViewRepresentable updates")
        await settle()
        check(bound.value == day(28), "native/state clamp to today but submitted parent binding remains in the past")
        check(calendar.date(from: behavior.selectedDate!) == bound.value && coordinator.state.selectedDate == bound.value, "native/state/binding must agree")
        view.setVisibleDateComponents(DateComponents(year: 2027, month: 2), animated: false)
        coordinator.calendarView(view, didChangeVisibleDateComponentsFrom: DateComponents(year: 2026, month: 10))
        coordinator.synchronizeSelection(in: view)
        check(view.visibleDateComponents.month == 2 && bound.value == day(28), "normal browsing must not select another day or reset the month")
        now = day(29)
        coordinator.synchronizeSelection(in: view)
        check(bound.value == day(28), "midnight binding correction must also be deferred")
        await settle()
        check(bound.value == day(29) && coordinator.state.selectedDate == bound.value && calendar.date(from: behavior.selectedDate!) == bound.value, "midnight rollover must normalize all three selections")
        bound.value = day(27)
        coordinator.synchronizeSelection(in: view)
        let future = DateComponents(year: 2026, month: 10, day: 31)
        behavior.setSelected(future, animated: false)
        coordinator.dateSelection(behavior, didSelectDate: future)
        await settle()
        check(bound.value == day(31) && coordinator.state.selectedDate == day(31) && calendar.date(from: behavior.selectedDate!) == day(31), "queued stale normalization must not overwrite a newer user selection")
        bound.value = day(27)
        coordinator.synchronizeSelection(in: view)
        bound.value = day(30)
        await settle()
        check(bound.value == day(30), "queued stale normalization must not overwrite an external binding update")
        coordinator.synchronizeSelection(in: view)
        check(coordinator.state.selectedDate == day(30) && calendar.date(from: behavior.selectedDate!) == day(30), "external update must reach native/state")
        bound.value = day(27)
        coordinator.synchronizeSelection(in: view)
        now = day(31)
        await settle()
        check(bound.value == day(31) && coordinator.state.selectedDate == day(31) && calendar.date(from: behavior.selectedDate!) == day(31), "a second midnight before deferred execution must use the latest clock")
        print("PASS: production coordinator past binding / midnight rollover / native-state-binding equality / browse preservation / stale deferred races")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='booking-binding-') as tmp:
    path = Path(tmp)
    (path / 'Regression.swift').write_text(state + shim + coordinator + harness)
    subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(path / 'cache'), str(path / 'Regression.swift'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)
