#!/usr/bin/env python3
"""Run unchanged CalendarService logic against isolated EventKit/preferences boundaries.

No real calendar, permission prompt, account, network, or UserDefaults domain is
accessed. Foundation date calculations and ReservationSchedule are production code.
Each executable run gets its own time zone without changing macOS settings.
"""
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


boundaries = '''
import Foundation

// Only external side effects are replaced. Failed EventKit removes leave their
// event intact; persisted mappings still flow through the production helpers.
enum EKSpan { case thisEvent }
enum EKEntityType { case event }
enum EKAuthorizationStatus { case denied, fullAccess }
final class EKCalendar {}
final class EKEvent {
    var title: String?
    var notes: String?
    var startDate: Date!
    var endDate: Date!
    var isAllDay = false
    var timeZone: TimeZone?
    var calendar: EKCalendar?
    var eventIdentifier: String!
    init(eventStore: EKEventStore) {}
}
final class EKEventStore {
    static var accessAllowed = true
    static var accessRequests = 0
    static var removes: [String] = []
    static var events: [String: EKEvent] = [:]
    static var failRemove = false
    static var failSave = false
    static var saves = 0
    var defaultCalendarForNewEvents: EKCalendar? = EKCalendar()
    static func authorizationStatus(for entity: EKEntityType) -> EKAuthorizationStatus {
        accessAllowed ? .fullAccess : .denied
    }
    func requestFullAccessToEvents() async throws -> Bool {
        Self.accessRequests += 1
        return Self.accessAllowed
    }
    func event(withIdentifier id: String) -> EKEvent? {
        Self.accessAllowed ? Self.events[id] : nil
    }
    func save(_ event: EKEvent, span: EKSpan) throws {
        if Self.failSave { throw URLError(.cannotWriteToFile) }
        Self.saves += 1
        event.eventIdentifier = "event-\\(Self.saves)"
        Self.events[event.eventIdentifier] = event
    }
    func remove(_ event: EKEvent, span: EKSpan) throws {
        Self.removes.append(event.eventIdentifier)
        if Self.failRemove { throw URLError(.cannotWriteToFile) }
        Self.events[event.eventIdentifier] = nil
    }
}
final class UserDefaults {
    static let standard = UserDefaults()
    private var values: [String: Any] = [:]
    func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}
'''

tests = r'''
@main struct Regression {
    @MainActor static var failures = 0
    @MainActor static var assertions = 0
    @MainActor static func check(_ condition: Bool, _ message: String) {
        assertions += 1
        if !condition { failures += 1; print("FAIL: " + message) }
    }
    static func instant(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw)! }
    static func reservation(_ id: Int, _ status: String) -> ReservationSummary {
        ReservationSummary(reservationId: id, storeId: 9, storeName: "가게", storeType: "호텔",
            petName: "초코", petImageUrl: nil, startDate: "2026-11-05", endDate: "2026-11-05",
            reservationType: "시간권 3시간", status: status)
    }
    static func mapping(_ id: Int) -> String? {
        UserDefaults.standard.dictionary(forKey: "reservation_calendar_events")?[String(id)] as? String
    }
    @MainActor static func reset() {
        CalendarService.clearLocalMappings()
        EKEventStore.events = [:]; EKEventStore.removes = []
        EKEventStore.accessRequests = 0; EKEventStore.accessAllowed = true
        EKEventStore.failRemove = false; EKEventStore.failSave = false; EKEventStore.saves = 0
    }
    @MainActor static func add(_ id: Int) async -> Bool {
        await CalendarService.addReservationEvent(reservationId: id, title: "가게 예약 신청", notes: "초코 맡김",
            date: instant("2026-11-05T14:30:00+09:00"), durationHours: 3)
    }
    @MainActor static func main() async {
        print("Time zone: " + TimeZone.current.identifier)

        // 1. Never ask for calendar access for an unlinked reservation.
        reset()
        await CalendarService.removeReservationEvent(reservationId: 99)
        check(EKEventStore.accessRequests == 0, "unlinked cancellation must not request calendar access")
        check(EKEventStore.removes.isEmpty, "unlinked cancellation must not delete any event")

        // 2. Hourly events carry the reservation's absolute time and time zone.
        reset()
        check(await add(1), "initial calendar add must succeed")
        if let identifier = mapping(1), let event = EKEventStore.events[identifier] {
            check(event.startDate == instant("2026-11-05T05:30:00Z"), "hourly event instant must match reservation")
            check(event.endDate == instant("2026-11-05T08:30:00Z"), "end must preserve requested 3 hours")
            check(event.timeZone?.identifier == "Asia/Seoul", "hourly events must not float with device time zone")
            check(event.title == "가게 예약 신청" && event.notes == "초코 맡김", "event details must be preserved")
        } else { check(false, "successful add must persist its event and reservation mapping") }

        // 3. A failed remove preserves the link so canceled-state sync retries it.
        let identifier = mapping(1)
        EKEventStore.failRemove = true
        await CalendarService.removeReservationEvent(reservationId: 1)
        check(mapping(1) == identifier, "failed calendar remove must preserve mapping")
        check(CalendarService.hasReservationEvent(reservationId: 1), "failed remove must remain retryable")
        EKEventStore.failRemove = false
        await CalendarService.syncReservationEvents([reservation(1, "CANCELED")])
        check(EKEventStore.removes.count == 2, "canceled-state sync must retry failed removal")
        check(mapping(1) == nil && EKEventStore.events.isEmpty, "successful retry must remove event and mapping")

        // 4. Denying/revoking permission does not lose the link.
        reset(); check(await add(2), "permission fixture add")
        let deniedIdentifier = mapping(2)
        EKEventStore.accessAllowed = false
        await CalendarService.removeReservationEvent(reservationId: 2)
        check(mapping(2) == deniedIdentifier && EKEventStore.removes.isEmpty, "permission denial must preserve pending link")
        EKEventStore.accessAllowed = true
        await CalendarService.syncReservationEvents([reservation(2, "CANCELED")])
        check(mapping(2) == nil && EKEventStore.events.isEmpty, "restored permission must allow sync retry")

        // 5. A missing lookup can be transient; do not erase its retry link.
        reset(); check(await add(3), "lookup fixture add")
        let missingIdentifier = mapping(3)!
        let missingEvent = EKEventStore.events.removeValue(forKey: missingIdentifier)!
        await CalendarService.removeReservationEvent(reservationId: 3)
        check(mapping(3) == missingIdentifier, "missing lookup must not erase mapping")
        EKEventStore.events[missingIdentifier] = missingEvent
        await CalendarService.syncReservationEvents([reservation(3, "CANCELED")])
        check(mapping(3) == nil && EKEventStore.events.isEmpty, "transiently missing event must be retried")

        // 6. Sync touches only tracked canceled bookings, not another event.
        reset(); check(await add(4), "active fixture add"); check(await add(5), "canceled fixture add")
        let activeIdentifier = mapping(4)
        await CalendarService.syncReservationEvents([reservation(4, "REQUEST"), reservation(5, "CANCELED"), reservation(6, "CANCELED")])
        check(mapping(4) == activeIdentifier && EKEventStore.events.count == 1, "sync must preserve active reservation event")
        check(mapping(5) == nil && EKEventStore.removes.count == 1, "sync must delete only tracked canceled event")

        // 7. Failed addition never leaves a fake mapping.
        reset(); EKEventStore.accessAllowed = false
        check(!(await add(7)), "denied add must return failure")
        check(mapping(7) == nil && EKEventStore.events.isEmpty, "denied add must not persist event or mapping")

        // 8. Existing linked events are not saved a second time.
        reset(); check(await add(8), "existing fixture add")
        check(await add(8), "existing add must report success")
        check(EKEventStore.saves == 1 && EKEventStore.events.count == 1, "duplicate add must reuse linked event")

        // 9. A save error has no mapping; an explicit retry succeeds.
        reset(); EKEventStore.failSave = true
        check(!(await add(9)), "failed save must return failure")
        check(mapping(9) == nil, "failed save must not write mapping")
        EKEventStore.failSave = false
        check(await add(9), "save retry must succeed")

        // 10. Hourly labels always denote Korean instants, including boundaries.
        for (raw, expected) in [
            ("2026-11-05 (목) 14:30", "2026-11-05T05:30:00Z"),
            ("2026-12-31 (목) 23:30", "2026-12-31T14:30:00Z"),
            ("2024-02-29 (목) 00:00", "2024-02-28T15:00:00Z"),
        ] {
            check(CalendarService.parseSchedule(raw) == instant(expected), "hourly label must denote Korean time: " + raw)
        }

        // 11. All-day dates float on the same Gregorian day in the device zone.
        if let day = CalendarService.parseSchedule("2026-11-05 (목)") {
            var local = Calendar(identifier: .gregorian); local.timeZone = .current
            let parts = local.dateComponents([.year, .month, .day, .hour, .minute], from: day)
            check(parts.year == 2026 && parts.month == 11 && parts.day == 5 && parts.hour == 0 && parts.minute == 0,
                  "date-only booking must retain the local floating calendar date")
            reset()
            check(await CalendarService.addReservationEvent(reservationId: 10, title: "종일권", notes: nil,
                date: day, isAllDay: true), "date-only add must succeed")
            let event = mapping(10).flatMap { EKEventStore.events[$0] }
            check(event?.isAllDay == true && event?.timeZone == nil, "all-day event must remain floating")
        } else { check(false, "date-only booking must parse") }

        // 12. Calendar normalization must not invent a different booking day.
        for raw in ["", "unknown", "2026-02-29 (일)", "2024-02-30 (금)", "2026-13-05 (목)",
                    "2026-11-00 (목)", "2026-11-05 (목) 24:00", "2026-11-05 (목) 14:60",
                    "2026-11-05 (목) -1:30", "0000-11-05 (목)", "2026-11-05 (목) 14:30 trailing"] {
            check(CalendarService.parseSchedule(raw) == nil, "invalid schedule must not normalize into another date: " + raw)
        }

        // 13. A local day can start at 01:00 when DST skips midnight. All-day
        // parsing must preserve the date, not require a nonexistent 00:00.
        if let day = CalendarService.parseSchedule("2026-09-06 (일)") {
            var local = Calendar(identifier: .gregorian); local.timeZone = .current
            let parts = local.dateComponents([.year, .month, .day], from: day)
            check(parts.year == 2026 && parts.month == 9 && parts.day == 6,
                  "valid all-day date must survive a skipped local midnight")
        } else { check(false, "valid all-day date must not be rejected at a DST midnight transition") }

        if failures > 0 { print("\(failures)/\(assertions) calendar assertions failed"); exit(1) }
        print("PASS: 13 calendar scenarios, \(assertions) assertions")
    }
}
'''

service = (app / 'Views/CalendarService.swift').read_text().replace('import EventKit\n', '')
schedule = (app / 'ReservationSchedule.swift').read_text()
dto = declaration((app / 'APIClient.swift').read_text(), 'struct ReservationSummary:')

with tempfile.TemporaryDirectory(prefix='calendar-service-') as tmp:
    path = Path(tmp)
    source = path / 'Regression.swift'
    source.write_text(boundaries + service + schedule + dto + tests)
    binary = path / 'regression'
    subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(path / 'module-cache'),
                    str(source), '-o', str(binary)], check=True, timeout=120)
    failures = 0
    timezones = ['Asia/Seoul', 'UTC', 'America/Los_Angeles', 'America/Santiago']
    for timezone in timezones:
        result = subprocess.run([str(binary)], env={**os.environ, 'TZ': timezone}, timeout=30)
        failures += result.returncode != 0
    if failures:
        raise SystemExit(f'{failures}/{len(timezones)} time-zone runs failed')
