import Foundation

// 예약 저장과 사업자 상세가 같은 한국 시각·요청 이용 시간을 사용한다.
struct ReservationSchedule {
    let start: String
    let end: String

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }

    static func booking(date: Date, time: Date, service: String, hours: Int) -> ReservationSchedule {
        guard service == "시간권" else {
            let day = label(date, format: "yyyy-MM-dd (E)")
            return ReservationSchedule(start: day, end: day)
        }
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        let start = calendar.date(bySettingHour: clock.hour!, minute: clock.minute!, second: 0, of: date)!
        let end = calendar.date(byAdding: .hour, value: hours, to: start)!
        return ReservationSchedule(start: label(start), end: label(end))
    }

    static func startLabel(rawStart: String?, service: String?) -> String {
        guard isHourly(service) else { return rawStart ?? "미확인" }
        return timestamp(rawStart).map { label($0) } ?? "미확인"
    }

    static func endLabel(rawStart: String?, rawEnd: String?, service: String?) -> String {
        guard isHourly(service) else { return rawEnd ?? "미확인" }
        let start = timestamp(rawStart)
        // 과거 start=end 행도 보정한다. 저장된 종료시각보다 고객이 요청한 이용 시간이 우선이다.
        if let start, let hours = requestedHours(service) {
            let seconds = TimeInterval(hours) * 3_600
            guard seconds.isFinite,
                  let end = calendar.date(byAdding: .hour, value: hours, to: start),
                  end.timeIntervalSinceReferenceDate.isFinite, end > start,
                  abs(end.timeIntervalSince(start) - seconds) < 1,
                  (1...9999).contains(calendar.component(.year, from: end)) else { return "미확인" }
            let display = label(end)
            return timestamp(display) != nil ? display : "미확인"
        }
        // 시간이 없는 예약을 한 시간으로 추정하지 않는다. 별도의 유효한 종료시각만 사용할 수 있다.
        guard let end = timestamp(rawEnd), start.map({ end > $0 }) ?? true else { return "미확인" }
        return label(end)
    }

    private static func isHourly(_ service: String?) -> Bool {
        service?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("시간권") == true
    }

    private static func requestedHours(_ service: String?) -> Int? {
        guard let service = service?.trimmingCharacters(in: .whitespacesAndNewlines),
              service.range(of: #"^시간권\s+[0-9]+시간$"#, options: .regularExpression) != nil,
              let hours = Int(service.dropFirst(3).trimmingCharacters(in: .whitespaces).dropLast(2)),
              hours > 0 else { return nil }
        return hours
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let value = DateFormatter()
        value.calendar = calendar
        value.locale = Locale(identifier: "ko_KR")
        value.timeZone = calendar.timeZone
        value.dateFormat = format
        value.isLenient = false
        return value
    }

    private static func label(_ date: Date, format: String = "yyyy-MM-dd (E) HH:mm") -> String {
        formatter(format).string(from: date)
    }

    private static func timestamp(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: #" \([^)]*\)"#, with: "", options: .regularExpression)
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"] {
            let parser = formatter(format)
            if let date = parser.date(from: normalized), parser.string(from: date) == normalized { return date }
        }
        // ISO8601DateFormatter는 2월30일을 보정하거나 뒤의 쓰레기 문자를 무시하므로 먼저 검증한다.
        guard raw.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$"#, options: .regularExpression) != nil else { return nil }
        let clock = String(raw.prefix(19)).replacingOccurrences(of: "T", with: " ")
        let parser = formatter("yyyy-MM-dd HH:mm:ss")
        guard let date = parser.date(from: clock), parser.string(from: date) == clock else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        return iso.date(from: raw)
    }
}
