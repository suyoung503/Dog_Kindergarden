import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("기기 캘린더에 전달할 예약 날짜")
@MainActor
struct CalendarScheduleTests {
    @Test("시간권은 한국 시각의 절대 시점을 사용한다")
    func hourlyUsesKoreanTime() {
        let expected = ISO8601DateFormatter().date(from: "2026-11-05T05:30:00Z")
        #expect(CalendarService.parseSchedule("2026-11-05 (목) 14:30") == expected)
        #expect(CalendarService.parseSchedule("2024-02-29 (목) 00:00") ==
                ISO8601DateFormatter().date(from: "2024-02-28T15:00:00Z"))
    }

    @Test("종일 일정은 기기 시간대의 같은 그레고리 날짜로 유지한다")
    func dateOnlyFloatsLocally() throws {
        let date = try #require(CalendarService.parseSchedule("2026-11-05 (목)"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 5)
        #expect(parts.hour == 0 && parts.minute == 0)
        // 일부 지역은 이 날짜의 자정을 DST로 건너뛴다. 종일 일정은 시각이 아니라 날짜를 지킨다.
        let dstDate = try #require(CalendarService.parseSchedule("2026-09-06 (일)"))
        let dstParts = calendar.dateComponents([.year, .month, .day], from: dstDate)
        #expect(dstParts.year == 2026 && dstParts.month == 9 && dstParts.day == 6)
    }

    @Test("존재하지 않는 날짜·시각과 추가 토큰을 다른 날짜로 보정하지 않는다")
    func invalidDatesDoNotNormalize() {
        for raw in ["", "2026-02-29 (일)", "2024-02-30 (금)", "2026-13-05 (목)",
                    "2026-11-00 (목)", "2026-11-05 (목) 24:00", "2026-11-05 (목) 14:60",
                    "2026-11-05 (목) -1:30", "0000-11-05 (목)", "2026-11-05 (목) 14:30 trailing"] {
            #expect(CalendarService.parseSchedule(raw) == nil)
        }
    }
}
