import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("사장님 이용일 달력")
@MainActor
struct OwnerCalendarTests {
    private let calendar = OwnerReservationCalendar.self
    private func day(_ value: String) -> Date { calendar.day(from: value)! }
    private func reservation(_ id: Int, _ start: String?, _ end: String?) throws -> PendingReservation {
        var fields: [String: Any] = ["reservation_id": id, "status": "CONFIRMED"]
        if let start { fields["start_date"] = start }
        if let end { fields["end_date"] = end }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PendingReservation.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    @Test("한국 자정과 월요일 시작 주간은 월말과 연말을 넘어간다")
    func koreanDaysAndWeeks() {
        let utc = ISO8601DateFormatter().date(from: "2026-10-27T15:00:00Z")!
        #expect(calendar.today(now: utc) == day("2026-10-28"))
        #expect(calendar.week(containing: day("2027-01-01")) == (28...31).map { day("2026-12-\($0)") } + (1...3).map { day("2027-01-0\($0)") })
        #expect(calendar.week(containing: day("2026-11-01")).first == day("2026-10-26"))
        #expect(calendar.monthDays(containing: day("2024-02-01")).compactMap { $0 }.count == 29)
        #expect(calendar.monthDays(containing: day("2026-02-01")).compactMap { $0 }.count == 28)
    }

    @Test("날짜는 형식과 실제 연월일을 검증한다")
    func strictDates() {
        #expect(calendar.day(from: "2026-10-28 (수) 09:00") == day("2026-10-28"))
        #expect(calendar.day(from: "2026-10-28T09:00:00+09:00") == day("2026-10-28"))
        for value in ["2026-02-29", "2024-02-30", "2026-13-01", "2026-00-01", "2026-1-01", "2026-10-28bad", "", "unknown"] {
            #expect(calendar.day(from: value) == nil)
        }
        #expect(calendar.day(from: "2024-02-29") != nil)
    }

    @Test("기간 양끝을 포함하고 누락 종료일만 시작일로 대체하며 미확인 예약도 접근 가능하다")
    func reservationDays() throws {
        let items = try [reservation(1, "2026-10-28", "2026-10-30"), reservation(2, "2026-10-28", nil),
                         reservation(3, "2026-10-28", ""), reservation(4, "2026-10-30", "2026-10-28"),
                         reservation(5, "bad", nil), reservation(6, "2026-10-28", "2026-02-30")]
        #expect(calendar.reservations(items, on: day("2026-10-28")).map(\.id) == [1, 2])
        #expect(calendar.reservations(items, on: day("2026-10-29")).map(\.id) == [1])
        #expect(calendar.reservations(items, on: day("2026-10-30")).map(\.id) == [1])
        #expect(calendar.reservations(items, on: day("2026-10-31")).isEmpty)
        #expect(calendar.unknownDateReservations(items).map(\.id) == [3, 4, 5, 6])
    }

    @Test("일반 상세 왕복과 새 목록은 선택일을 유지하고 알림의 시작일 포커스는 한 번만 적용한다")
    func navigation() {
        let router = AppRouter()
        router.reset(to: .home)
        router.ownerCalendarState.select(day("2026-11-05"))
        router.openOwnerReservation(id: 19)
        router.focusOwnerReservationStartDate("2026-10-28", expectedReservationId: 19)
        #expect(router.ownerCalendarState.selectedDate == day("2026-11-05"))
        router.back()
        #expect(router.ownerCalendarState.selectedDate == day("2026-11-05"))
        router.openOwnerReservation(id: 19, tab: .diary, focusOnStartDate: true)
        router.focusOwnerReservationStartDate("2026-10-28", expectedReservationId: 19)
        #expect(router.ownerCalendarState.selectedDate == day("2026-10-28"))
        router.ownerCalendarState.select(day("2026-11-05"))
        router.focusOwnerReservationStartDate("2026-10-28", expectedReservationId: 19)
        #expect(router.ownerCalendarState.selectedDate == day("2026-11-05"))
        // 같은 상세가 열린 채 동일 예약 알림을 다시 받아도 새 진입의 포커스만 한 번 소비한다.
        router.openOwnerReservation(id: 19, tab: .diary, focusOnStartDate: true)
        router.focusOwnerReservationStartDate("2026-10-28", expectedReservationId: 19)
        #expect(router.ownerCalendarState.selectedDate == day("2026-10-28"))
        router.ownerCalendarState.select(day("2026-11-06"))
        router.focusOwnerReservationStartDate("2026-10-28", expectedReservationId: 19)
        #expect(router.ownerCalendarState.selectedDate == day("2026-11-06"))
        router.reset(to: .start)
        #expect(router.ownerCalendarState.selectedDate == calendar.today())
        #expect(router.ownerReservationContext == nil)
    }

    @Test("확정 후 상세 재조회 실패여도 사전에 보관한 시작일을 선택한다")
    func confirmationFocus() async throws {
        let state = OwnerReservationDetailState()
        let request = try reservation(19, "2026-10-28", nil)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let item = try decoder.decode(PendingReservation.self, from: Data(#"{"reservation_id":19,"status":"REQUEST","start_date":"2026-10-28"}"#.utf8))
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { item })
        let capturedStart = state.reservation?.startDate
        await state.confirm(ownerId: 1, currentUserId: { 1 }, action: {}, fetch: { throw CalendarTestError.failed })
        let router = AppRouter()
        router.ownerCalendarState.select(day("2026-11-05"))
        if state.didConfirm { router.ownerCalendarState.focus(startDate: capturedStart) }
        #expect(state.reservation == nil)
        #expect(router.ownerCalendarState.selectedDate == calendar.day(from: request.startDate))
    }

    @Test("취소된 이전 상세 응답은 다른 예약 알림의 포커스를 소비하지 않는다")
    func staleDetailCannotConsumeNotificationFocus() async throws {
        let oldReservation = try reservation(19, "2026-10-28", nil)
        let newReservation = try reservation(20, "2026-11-05", nil)
        let state = OwnerReservationDetailState()
        let router = AppRouter()
        router.ownerCalendarState.select(day("2026-12-01"))
        router.openOwnerReservation(id: 19)
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { oldReservation })
        var response: CheckedContinuation<PendingReservation, Never>?
        let refresh = Task { @MainActor in
            await state.load(ownerId: 1, currentUserId: { 1 }, fetch: {
                await withCheckedContinuation { response = $0 }
            })
            // 취소 시 모델이 유지한 A 상세를 B 알림의 포커스로 오인하면 안 된다.
            if let loaded = state.reservation {
                router.focusOwnerReservationStartDate(loaded.startDate, expectedReservationId: oldReservation.id)
            }
        }
        while response == nil { await Task.yield() }
        router.openOwnerReservation(id: 20, tab: .diary, focusOnStartDate: true)
        refresh.cancel()
        response?.resume(returning: oldReservation)
        await refresh.value
        #expect(state.reservation?.id == 19)
        #expect(router.ownerReservationContext?.reservationId == 20)
        #expect(router.ownerReservationContext?.focusOnStartDate == true)
        #expect(router.ownerCalendarState.selectedDate == day("2026-12-01"))
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { newReservation })
        router.focusOwnerReservationStartDate(state.reservation?.startDate, expectedReservationId: newReservation.id)
        #expect(router.ownerCalendarState.selectedDate == day("2026-11-05"))
        #expect(router.ownerReservationContext?.focusOnStartDate == false)
    }

    @Test("목록으로 돌아간 뒤 늦은 재시도 응답은 사용자가 선택한 날짜를 바꾸지 않는다")
    func lateRetryAfterBack() {
        let router = AppRouter()
        router.reset(to: .home)
        router.openOwnerReservation(id: 19, tab: .diary, focusOnStartDate: true)
        router.back()
        router.ownerCalendarState.select(day("2026-12-01"))
        router.focusOwnerReservationStartDate("2026-10-28", expectedReservationId: 19)
        #expect(router.current == .ownerMode)
        #expect(router.ownerCalendarState.selectedDate == day("2026-12-01"))
        #expect(router.ownerReservationContext?.focusOnStartDate == true)
    }

    private enum CalendarTestError: Error { case failed }
}
