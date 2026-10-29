import Foundation

// 서버의 예약 전체 목록을 한국 이용일 기준으로만 분류한다. 시간대에 따라 날짜를 이동시키지 않는다.
enum OwnerReservationCalendar {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        value.locale = Locale(identifier: "ko_KR")
        value.firstWeekday = 2
        return value
    }

    static func today(now: Date = Date()) -> Date { calendar.startOfDay(for: now) }

    static func day(from raw: String?) -> Date? {
        guard let raw else { return nil }
        let bytes = Array(raw.utf8)
        guard bytes.count >= 10, bytes[4] == 45, bytes[7] == 45,
              [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy({ (48...57).contains(bytes[$0]) }),
              bytes.count == 10 || bytes[10] == 84 || bytes[10] == 32,
              let year = Int(String(bytes: bytes[0..<4], encoding: .utf8)!), year > 0,
              let month = Int(String(bytes: bytes[5..<7], encoding: .utf8)!),
              let day = Int(String(bytes: bytes[8..<10], encoding: .utf8)!) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return date
    }

    static func addingDays(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date)!
    }

    static func addingMonths(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: count, to: date)!
    }

    static func week(containing date: Date) -> [Date] {
        let offset = (calendar.component(.weekday, from: date) + 5) % 7
        let monday = addingDays(-offset, to: today(now: date))
        return (0..<7).map { addingDays($0, to: monday) }
    }

    static func monthDays(containing date: Date) -> [Date?] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let offset = (calendar.component(.weekday, from: start) + 5) % 7
        let days = calendar.range(of: .day, in: .month, for: start)!
        return Array(repeating: nil, count: offset) + days.map { addingDays($0 - 1, to: start) }
    }

    static func label(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func range(for reservation: PendingReservation) -> ClosedRange<Date>? {
        guard let start = day(from: reservation.startDate) else { return nil }
        let end: Date
        if let rawEnd = reservation.endDate {
            guard let parsedEnd = day(from: rawEnd) else { return nil }
            end = parsedEnd
        } else { end = start }
        guard start <= end else { return nil }
        return start...end
    }

    static func reservations(_ items: [PendingReservation], on date: Date) -> [PendingReservation] {
        let selectedDay = today(now: date)
        return items.filter { range(for: $0)?.contains(selectedDay) == true }
    }

    static func unknownDateReservations(_ items: [PendingReservation]) -> [PendingReservation] {
        items.filter { range(for: $0) == nil }
    }
}

struct OwnerReservationCalendarState {
    private(set) var selectedDate: Date

    init(now: Date = Date()) { selectedDate = OwnerReservationCalendar.today(now: now) }

    mutating func select(_ date: Date) { selectedDate = OwnerReservationCalendar.today(now: date) }

    mutating func focus(startDate: String?) {
        if let date = OwnerReservationCalendar.day(from: startDate) { select(date) }
    }
}
