import EventKit
import Foundation

// 예약 확정 시 기기 캘린더에 일정을 추가/삭제하는 EventKit 연결
enum CalendarService {
    private static let store = EKEventStore()
    private static let mappingKey = "reservation_calendar_events"

    // "토 6/13 14:00" → Date. 연도가 없으므로 오늘 이후 가장 가까운 도래 시점으로 추정
    static func parseSchedule(_ raw: String) -> Date? {
        let parts = raw.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let dateParts = parts[1].split(separator: "/")
        let timeParts = parts[2].split(separator: ":")
        guard dateParts.count == 2, timeParts.count == 2,
              let month = Int(dateParts[0]), let day = Int(dateParts[1]),
              let hour = Int(timeParts[0]), let minute = Int(timeParts[1]) else { return nil }

        let calendar = Calendar.current
        let now = Date()
        var comps = DateComponents()
        comps.year = calendar.component(.year, from: now)
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute

        guard var date = calendar.date(from: comps) else { return nil }
        if date < now {
            comps.year = (comps.year ?? 0) + 1
            date = calendar.date(from: comps) ?? date
        }
        return date
    }

    @discardableResult
    static func addReservationEvent(reservationId: Int, title: String, notes: String?, date: Date) async -> Bool {
        guard await requestAccess() else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.startDate = date
        event.endDate = date.addingTimeInterval(60 * 60)
        event.calendar = store.defaultCalendarForNewEvents
        guard (try? store.save(event, span: .thisEvent)) != nil else { return false }
        setEventIdentifier(event.eventIdentifier, for: reservationId)
        return true
    }

    static func removeReservationEvent(reservationId: Int) async {
        guard await requestAccess() else { return }
        guard let identifier = eventIdentifier(for: reservationId),
              let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent)
        setEventIdentifier(nil, for: reservationId)
    }

    private static func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            // 이벤트 삭제(취소 시)에는 조회가 필요하므로 쓰기 전용이 아닌 전체 접근을 받는다
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
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
