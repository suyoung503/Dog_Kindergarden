import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("예약 일정의 한국 시각 및 요청한 이용 시간")
@MainActor
struct ReservationScheduleTests {
    private func instant(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw)! }

    @Test("시간권은 선택한 날짜와 오후 30분 시각을 합치고 요청한 시간을 더한다", arguments: [1, 3, 6])
    func hourly(hours: Int) {
        let schedule = ReservationSchedule.booking(date: instant("2026-10-28T09:00:00+09:00"),
                                                   time: instant("2001-01-01T14:30:00+09:00"), service: "시간권", hours: hours)
        #expect(schedule.start == "2026-10-28 (수) 14:30")
        let expected = [1: "2026-10-28 (수) 15:30", 3: "2026-10-28 (수) 17:30", 6: "2026-10-28 (수) 20:30"]
        #expect(schedule.end == expected[hours])
    }

    @Test("23시30분의 3시간 예약은 자정·연말·윤년 경계를 올바르게 넘긴다")
    func rollover() {
        for (date, expectedStart, expectedEnd) in [
            ("2026-10-28", "2026-10-28 (수) 23:30", "2026-10-29 (목) 02:30"),
            ("2026-12-31", "2026-12-31 (목) 23:30", "2027-01-01 (금) 02:30"),
            ("2024-02-28", "2024-02-28 (수) 23:30", "2024-02-29 (목) 02:30"),
            ("2024-02-29", "2024-02-29 (목) 23:30", "2024-03-01 (금) 02:30")
        ] {
            let schedule = ReservationSchedule.booking(date: instant(date + "T09:00:00+09:00"),
                                                       time: instant("2001-01-01T23:30:00+09:00"), service: "시간권", hours: 3)
            #expect(schedule.start == expectedStart)
            #expect(schedule.end == expectedEnd)
        }
    }

    @Test("종일·숙박은 선택 시간·hours와 무관하게 기존 날짜만 저장한다", arguments: ["종일권", "하루 숙박권"])
    func dateOnly(service: String) {
        let schedule = ReservationSchedule.booking(date: instant("2026-10-28T23:30:00+09:00"),
                                                   time: instant("2001-01-01T14:30:00+09:00"), service: service, hours: 3)
        #expect(schedule.start == "2026-10-28 (수)")
        #expect(schedule.end == "2026-10-28 (수)")
        #expect(ReservationSchedule.startLabel(rawStart: "2026-10-28", service: service) == "2026-10-28")
        #expect(ReservationSchedule.endLabel(rawStart: "2026-10-28", rawEnd: "2026-10-29", service: service) == "2026-10-29")
    }

    @Test("구 예약의 같은 시작·종료는 요청한 3시간으로 보정하며 DB 종료시각과 달라도 요청 시간을 우선한다")
    func legacyDuration() {
        let rawStart = "2026-12-31 (목) 23:30"
        for rawEnd in [rawStart, "2027-01-01 (금) 04:30", nil] {
            #expect(ReservationSchedule.startLabel(rawStart: rawStart, service: "시간권 3시간") == rawStart)
            #expect(ReservationSchedule.endLabel(rawStart: rawStart, rawEnd: rawEnd, service: "시간권 3시간") == "2027-01-01 (금) 02:30")
        }
    }

    @Test("시간 수를 모르거나 잘못되었으면 임의로 한 시간을 만들지 않는다")
    func unknownDuration() {
        for service in ["시간권", "시간권 0시간", "시간권 -3시간", "시간권 1.5시간", "시간권 세시간", "시간권 999999999999999999999999시간"] {
            #expect(ReservationSchedule.endLabel(rawStart: "2026-10-28 (수) 14:30", rawEnd: nil, service: service) == "미확인")
            #expect(ReservationSchedule.endLabel(rawStart: "2026-10-28 (수) 14:30", rawEnd: "2026-10-28 (수) 14:30", service: service) == "미확인")
            #expect(ReservationSchedule.endLabel(rawStart: "2026-10-28 (수) 14:30", rawEnd: "2026-10-28 (수) 17:30", service: service) == "2026-10-28 (수) 17:30")
        }
    }

    @Test("과거 행의 정수 overflow와 표시 가능한 날짜 범위 밖 이용 시간은 미확인이다")
    func unrepresentableDuration() {
        for hours in [Int.max, Int.max - 1, 100_000_000] {
            #expect(ReservationSchedule.endLabel(rawStart: "2026-10-28 (수) 14:30", rawEnd: nil,
                                                  service: "시간권 \(hours)시간") == "미확인")
        }
        // 현재 UI의 6시간 상한을 과거 예약에 임의 적용하지 않는다.
        #expect(ReservationSchedule.endLabel(rawStart: "2026-10-28 (수) 14:30", rawEnd: nil,
                                              service: "시간권 12시간") == "2026-10-29 (목) 02:30")
    }

    @Test("ISO offset의 시와 분 범위를 벗어난 원시 시각은 보정하지 않는다")
    func invalidISOOffset() {
        for offset in ["+25:00", "+09:99", "-24:00", "-09:60"] {
            let raw = "2026-10-28T14:30:00" + offset
            #expect(ReservationSchedule.startLabel(rawStart: raw, service: "시간권 3시간") == "미확인")
            #expect(ReservationSchedule.endLabel(rawStart: raw, rawEnd: nil, service: "시간권 3시간") == "미확인")
            #expect(ReservationSchedule.endLabel(rawStart: nil, rawEnd: raw, service: "시간권") == "미확인")
        }
    }

    @Test("ISO 시각은 한국 시각으로 안내하며 분과 날짜를 보존한다")
    func isoDates() {
        #expect(ReservationSchedule.startLabel(rawStart: "2026-10-28T14:30:00Z", service: "시간권 3시간") == "2026-10-28 (수) 23:30")
        #expect(ReservationSchedule.endLabel(rawStart: "2026-10-28T14:30:00Z", rawEnd: nil, service: "시간권 3시간") == "2026-10-29 (목) 02:30")
        #expect(ReservationSchedule.endLabel(rawStart: "2026-10-28 14:30:00", rawEnd: nil, service: "시간권 3시간") == "2026-10-28 (수) 17:30")
    }

    @Test("시간권 날짜만 있거나 유효하지 않은 시각은 실제 시간이 미확인임을 표시한다")
    func missingTime() {
        for raw in [nil, "", "2026-10-28", "2026-02-30 (월) 14:30", "2026-10-28 (수) 25:30", "2026-02-30T14:30:00+09:00", "2026-10-28T14:30:00Zjunk", "unknown"] {
            #expect(ReservationSchedule.startLabel(rawStart: raw, service: "시간권 3시간") == "미확인")
            #expect(ReservationSchedule.endLabel(rawStart: raw, rawEnd: nil, service: "시간권 3시간") == "미확인")
        }
    }
}
