import Foundation

struct DiaryTimelineDay: Identifiable {
    let id: String
    let title: String
    var entries: [DiaryEntry]
}

// 예약 이용일이나 수정 시각이 아닌 서버 최초 게시 시각만 표시 기준으로 사용한다.
enum DiaryTimelineGrouping {
    static func groups(_ entries: [DiaryEntry]) -> [DiaryTimelineDay] {
        let sorted = entries.enumerated().map { (offset: $0.offset, entry: $0.element, date: publishedDate($0.element.createdAt)) }
            .sorted { lhs, rhs in
                switch (lhs.date, rhs.date) {
                case let (left?, right?) where left != right: return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default:
                    let leftID = lhs.entry.diaryId ?? Int.max
                    let rightID = rhs.entry.diaryId ?? Int.max
                    return leftID == rightID ? lhs.offset < rhs.offset : leftID < rightID
                }
            }
        let keyFormatter = displayFormatter("yyyy-MM-dd")
        let titleFormatter = displayFormatter("yyyy년 M월 d일")
        var days: [DiaryTimelineDay] = []
        for item in sorted {
            let key = item.date.map(keyFormatter.string(from:)) ?? "unknown"
            if days.last?.id == key {
                days[days.count - 1].entries.append(item.entry)
            } else {
                days.append(DiaryTimelineDay(
                    id: key,
                    title: item.date.map(titleFormatter.string(from:)) ?? "날짜 확인 필요",
                    entries: [item.entry]
                ))
            }
        }
        return days
    }

    static func timeLabel(_ raw: String?) -> String {
        guard let date = publishedDate(raw) else { return "게시 시간 미확인" }
        return displayFormatter("a h:mm").string(from: date)
    }

    private static func displayFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")!
        formatter.dateFormat = format
        return formatter
    }

    private static func publishedDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        if let date = formatter.date(from: raw), formatter.string(from: date) == raw {
            return date
        }
        // ISO 응답도 명시적인 시간대와 유효한 원래 달력 날짜가 있을 때만 허용한다.
        let isoPattern = #"\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z"#
        guard raw.range(of: isoPattern, options: .regularExpression) != nil else { return nil }
        let wallTime = String(raw.prefix(19)).replacingOccurrences(of: "T", with: " ")
        guard let date = formatter.date(from: wallTime), formatter.string(from: date) == wallTime else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = raw.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return isoFormatter.date(from: raw)
    }
}
