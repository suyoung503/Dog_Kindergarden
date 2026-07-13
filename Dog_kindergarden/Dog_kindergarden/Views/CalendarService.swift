import EventKit
import Foundation

// 예약 확정 시 기기 캘린더에 일정을 추가/삭제하는 EventKit 연결
enum CalendarService {
    private static let store = EKEventStore()
    private static let mappingKey = "reservation_calendar_events"

    // "2026-07-12 (일) 14:00"(시간권) 또는 "2026-07-12 (일)"(종일권·숙박권, 시간 없음) → Date.
    // 연도가 포함된 형식이라 추정 없이 정확한 날짜로 해석
    static func parseSchedule(_ raw: String) -> Date? {
        let parts = raw.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let dateParts = parts[0].split(separator: "-")
        guard dateParts.count == 3,
              let year = Int(dateParts[0]), let month = Int(dateParts[1]), let day = Int(dateParts[2]) else { return nil }

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        if parts.count >= 3 {
            let timeParts = parts[2].split(separator: ":")
            guard timeParts.count == 2,
                  let hour = Int(timeParts[0]), let minute = Int(timeParts[1]) else { return nil }
            comps.hour = hour
            comps.minute = minute
        }
        return Calendar.current.date(from: comps)
    }

    @discardableResult
    static func addReservationEvent(reservationId: Int, title: String, notes: String?, date: Date,
                                    isAllDay: Bool = false, durationHours: Int = 1) async -> Bool {
        guard await requestAccess() else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.startDate = date
        event.endDate = isAllDay ? date : date.addingTimeInterval(TimeInterval(durationHours) * 60 * 60)
        event.isAllDay = isAllDay
        event.calendar = store.defaultCalendarForNewEvents
        guard (try? store.save(event, span: .thisEvent)) != nil else { return false }
        setEventIdentifier(event.eventIdentifier, for: reservationId)
        return true
    }

    // 고객 기기 캘린더 동기화 — 예약 내역을 불러올 때 호출.
    // 일정 추가는 예약 요청 시점(BookingView)에 이미 했으므로, 여기서는 사장님이 취소한 경우처럼
    // 이 기기 밖에서 CANCELED가 된 예약의 일정만 삭제한다 (서버 푸시가 없어 관찰 방식).
    static func syncReservationEvents(_ reservations: [ReservationSummary]) async {
        for reservation in reservations {
            guard let rid = reservation.reservationId,
                  reservation.status == "CANCELED",
                  eventIdentifier(for: rid) != nil else { continue }
            await removeReservationEvent(reservationId: rid)
        }
    }

    static func removeReservationEvent(reservationId: Int) async {
        guard await requestAccess() else { return }
        guard let identifier = eventIdentifier(for: reservationId),
              let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent)
        setEventIdentifier(nil, for: reservationId)
    }

    // 사용자가 캘린더 권한을 거부해 둔 상태인지 — iOS는 한 번 거부하면 시스템 알림을 다시 띄우지 않으므로
    // 이때는 앱이 직접 '설정 열기'로 안내해야 한다
    static var isAccessDenied: Bool {
        EKEventStore.authorizationStatus(for: .event) == .denied
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
