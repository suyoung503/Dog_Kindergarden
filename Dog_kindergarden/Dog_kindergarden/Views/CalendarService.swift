import EventKit
import Foundation

// 사용자가 예약 완료 화면에서 명시적으로 선택했을 때 기기 캘린더에 일정을 추가/삭제한다.
enum CalendarService {
    private static let store = EKEventStore()
    private static let mappingKey = "reservation_calendar_events"

    // "2026-07-12 (일) 14:00"(시간권) 또는 "2026-07-12 (일)"(종일권·숙박권, 시간 없음) → Date.
    // 연도가 포함된 형식이라 추정 없이 정확한 날짜로 해석
    static func parseSchedule(_ raw: String) -> Date? {
        let parts = raw.split(separator: " ")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let dateParts = parts[0].split(separator: "-")
        guard dateParts.count == 3,
              let year = Int(dateParts[0]), let month = Int(dateParts[1]), let day = Int(dateParts[2]),
              (1...9999).contains(year) else { return nil }

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        if parts.count == 3 {
            let timeParts = parts[2].split(separator: ":")
            guard timeParts.count == 2,
                  let hour = Int(timeParts[0]), let minute = Int(timeParts[1]),
                  (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            comps.hour = hour
            comps.minute = minute
        }
        var calendar = ReservationSchedule.calendar
        // 시간권은 한국 시각, 종일 일정은 기기 시간대의 같은 날짜를 유지한다.
        if parts.count == 2 { calendar.timeZone = .current }
        guard let date = calendar.date(from: comps) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else { return nil }
        // 종일 일정은 DST로 자정이 없어도 같은 날짜의 첫 유효 시각을 허용한다.
        if parts.count == 3, actual.hour != comps.hour || actual.minute != comps.minute { return nil }
        return date
    }

    @discardableResult
    static func addReservationEvent(reservationId: Int, title: String, notes: String?, date: Date,
                                    isAllDay: Bool = false, durationHours: Int = 1) async -> Bool {
        if hasReservationEvent(reservationId: reservationId) { return true }
        guard await requestAccess() else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.startDate = date
        event.endDate = isAllDay ? date : date.addingTimeInterval(TimeInterval(durationHours) * 60 * 60)
        event.isAllDay = isAllDay
        event.timeZone = isAllDay ? nil : ReservationSchedule.calendar.timeZone
        event.calendar = store.defaultCalendarForNewEvents
        guard (try? store.save(event, span: .thisEvent)) != nil else { return false }
        setEventIdentifier(event.eventIdentifier, for: reservationId)
        return true
    }

    // 고객 기기 캘린더 동기화 — 사용자가 직접 추가한 일정 중 취소된 예약만 삭제한다.
    static func syncReservationEvents(_ reservations: [ReservationSummary]) async {
        for reservation in reservations {
            guard let rid = reservation.reservationId,
                  reservation.status == "CANCELED",
                  eventIdentifier(for: rid) != nil else { continue }
            await removeReservationEvent(reservationId: rid)
        }
    }

    static func removeReservationEvent(reservationId: Int) async {
        guard let identifier = eventIdentifier(for: reservationId) else { return }
        guard await requestAccess() else { return }
        guard let event = store.event(withIdentifier: identifier),
              (try? store.remove(event, span: .thisEvent)) != nil else { return }
        setEventIdentifier(nil, for: reservationId)
    }

    static func clearLocalMappings() {
        UserDefaults.standard.removeObject(forKey: mappingKey)
    }

    // 사용자가 캘린더 권한을 거부해 둔 상태인지 — iOS는 한 번 거부하면 시스템 알림을 다시 띄우지 않으므로
    // 이때는 앱이 직접 '설정 열기'로 안내해야 한다
    static var isAccessDenied: Bool {
        EKEventStore.authorizationStatus(for: .event) == .denied
    }

    static func hasReservationEvent(reservationId: Int) -> Bool {
        guard let identifier = eventIdentifier(for: reservationId) else { return false }
        return store.event(withIdentifier: identifier) != nil
    }

    private static func requestAccess() async -> Bool {
        // 최소 지원 버전이 iOS 17이고, 취소 일정 조회·삭제가 필요하므로 전체 접근을 요청한다.
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    private static func eventIdentifier(for reservationId: Int) -> String? {
        let map = UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        return map[String(reservationId)]
    }

    private static func setEventIdentifier(_ identifier: String?, for reservationId: Int) {
        var map = UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        map[String(reservationId)] = identifier
        UserDefaults.standard.set(map, forKey: mappingKey)
    }
}
