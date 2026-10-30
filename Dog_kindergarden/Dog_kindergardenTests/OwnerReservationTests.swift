import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("Owner reservation presentation and state")
@MainActor
struct OwnerReservationTests {
    private func reservation(status: String = "REQUEST", source: String? = nil) throws -> PendingReservation {
        let json = """
        {"reservation_id":19,"pet_name":"초코","status":"\(status)"\(source.map { ",\"information_source\":\"\($0)\"" } ?? "")}
        """
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PendingReservation.self, from: Data(json.utf8))
    }

    @Test("Current note format parses multiline values without losing the original")
    func notes() {
        let raw = "사회성: 좋음 / 알레르기: 닭고기 / 특이사항: 산책 / 천천히\n해주세요"
        let note = OwnerReservationNote(raw)
        #expect(note.sociability == "좋음")
        #expect(note.allergy == "닭고기")
        #expect(note.special == "산책 / 천천히\n해주세요")
        #expect(note.original == raw)
        #expect(OwnerReservationNote("예전 자유 메모").original == "예전 자유 메모")
        #expect(OwnerReservationNote("예전 자유 메모\n천천히 돌봐주세요").special == "예전 자유 메모\n천천히 돌봐주세요")
        #expect(OwnerReservationNote("사회성: 좋음 / 알레르기: 닭고기").special == "미입력")
        #expect(OwnerReservationNote("  ").special == "미입력")
        #expect(OwnerReservationNote(nil).allergy == "미입력")
    }

    @Test("Missing snapshot provenance is explicitly current profile")
    func source() throws {
        #expect(try reservation().ownerInformationSourceLabel == "신청 당시 정보 미보관 · 현재 정보 기준")
        #expect(try reservation(source: "BOOKING_SNAPSHOT").ownerInformationSourceLabel == "신청 당시 정보")
        #expect(OwnerReservationPresentation.value("  ") == "미입력")
    }

    @Test("Refresh failure removes stale detail and retry restores it")
    func refreshFailure() async throws {
        let state = OwnerReservationDetailState()
        let item = try reservation()
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { item })
        #expect(state.reservation?.id == 19)
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { throw TestError.failed })
        #expect(state.reservation == nil)
        #expect(state.errorMessage != nil)
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { item })
        #expect(state.reservation?.id == 19)
    }

    @Test("Confirmation failures preserve request and successful confirmation switches the detail")
    func confirmation() async throws {
        let state = OwnerReservationDetailState()
        let request = try reservation(); let confirmed = try reservation(status: "CONFIRMED")
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { request })
        await state.confirm(ownerId: 1, currentUserId: { 1 }, action: { throw TestError.failed }, fetch: { confirmed })
        #expect(state.reservation?.status == "REQUEST")
        #expect(state.actionError != nil)
        await state.confirm(ownerId: 1, currentUserId: { 1 }, action: {}, fetch: { confirmed })
        #expect(state.reservation?.status == "CONFIRMED")
        #expect(state.actionError == nil)
    }

    @Test("Cancellation failure preserves request, success clears private detail")
    func cancellation() async throws {
        let state = OwnerReservationDetailState(); let item = try reservation()
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { item })
        await state.cancel(ownerId: 1, currentUserId: { 1 }, action: { throw TestError.failed })
        #expect(state.reservation?.status == "REQUEST")
        #expect(!state.didCancel)
        await state.cancel(ownerId: 1, currentUserId: { 1 }, action: {})
        #expect(state.didCancel)
        #expect(state.reservation == nil)
    }

    @Test("Cancelled responses and account changes never publish detail")
    func staleResponses() async throws {
        let state = OwnerReservationDetailState(); let item = try reservation()
        var account = 1
        await state.load(ownerId: 1, currentUserId: { account }, fetch: { account = 2; return item })
        #expect(state.reservation == nil)
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { throw CancellationError() })
        #expect(state.reservation == nil)
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { try reservation(status: "CANCELED") })
        #expect(state.reservation == nil)
        #expect(state.errorMessage != nil)
    }

    @Test("Confirmed action is retained for return navigation even when the follow-up detail fetch fails")
    func confirmedRefreshFailure() async throws {
        let state = OwnerReservationDetailState(); let item = try reservation()
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { item })
        await state.confirm(ownerId: 1, currentUserId: { 1 }, action: {}, fetch: { throw TestError.failed })
        #expect(state.didConfirm)
        #expect(state.reservation == nil)
        #expect(state.errorMessage != nil)
    }

    @Test("Diary deep link tab survives confirmed refresh failures and retry, but requests cannot show diary")
    func diaryTab() async throws {
        let state = OwnerReservationDetailState()
        state.selectedTab = .diary
        let confirmed = try reservation(status: "CONFIRMED")
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { confirmed })
        #expect(state.selectedTab == .diary)
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { throw TestError.failed })
        #expect(state.reservation == nil)
        #expect(state.selectedTab == .diary)
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { confirmed })
        #expect(state.selectedTab == .diary)
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { try reservation() })
        #expect(state.selectedTab == .information)
    }

    @Test("Schedule shows same-day values once and preserves differing end dates")
    func schedule() throws {
        var item = try reservation()
        #expect(OwnerReservationPresentation.schedule(item) == "미입력")
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        item = try decoder.decode(PendingReservation.self, from: Data(#"{"start_date":"2026-10-28","end_date":"2026-10-28"}"#.utf8))
        #expect(OwnerReservationPresentation.schedule(item) == "2026-10-28")
        item.endDate = "2026-10-29"
        #expect(OwnerReservationPresentation.schedule(item) == "2026-10-28 ~ 2026-10-29")
    }

    @Test("Refreshing keeps the mounted diary until success or failure, but not across accounts")
    func refreshIdentity() async throws {
        let state = OwnerReservationDetailState(); let item = try reservation(status: "CONFIRMED")
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { item })
        await state.load(ownerId: 1, currentUserId: { 1 }, fetch: {
            #expect(state.reservation?.id == 19)
            return item
        })
        await state.load(ownerId: 2, currentUserId: { 2 }, fetch: {
            #expect(state.reservation == nil)
            throw TestError.failed
        })
        #expect(state.reservation == nil)
    }

    @Test("Permission revocation and status conflicts remove private detail after failed actions")
    func rejectedActions() async throws {
        let state = OwnerReservationDetailState(); let item = try reservation()
        for status in [401, 403, 404, 409] {
            await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { item })
            await state.confirm(ownerId: 1, currentUserId: { 1 }, action: {
                throw APIError.server(status: status, code: nil, message: nil)
            }, fetch: { item })
            #expect(state.reservation == nil)
            #expect(state.errorMessage != nil)
            await state.load(ownerId: 1, currentUserId: { 1 }, fetch: { item })
            await state.cancel(ownerId: 1, currentUserId: { 1 }, action: { throw APIError.httpStatus(status) })
            #expect(state.reservation == nil)
        }
    }

    @Test("Task cancellation cannot publish fetched private detail")
    func cancelledTask() async throws {
        let state = OwnerReservationDetailState(); let item = try reservation()
        let task = Task { @MainActor in
            await state.load(ownerId: 1, currentUserId: { 1 }, fetch: {
                withUnsafeCurrentTask { $0?.cancel() }
                return item
            })
        }
        await task.value
        #expect(state.reservation == nil)
    }

    @Test("Owner navigation reuses management stack and resets account context")
    func navigation() {
        let router = AppRouter()
        router.reset(to: .home)
        router.openOwnerReservations(tab: .requests)
        router.openOwnerReservation(id: 19, tab: .information)
        router.openOwnerReservation(id: 19, tab: .diary)
        #expect(router.stack.count == 3)
        #expect(router.ownerReservationContext?.initialTab == .diary)
        router.ownerReservationTab = .confirmed
        router.back()
        #expect(router.current == .ownerMode)
        #expect(router.ownerReservationTab == .confirmed)
        router.go(.ownerDiaryList)
        #expect(router.current == .ownerMode)
        #expect(router.stack.count == 2)
        router.reset(to: .start)
        #expect(router.ownerReservationContext == nil)
        #expect(router.ownerReservationTab == .requests)
    }

    private enum TestError: Error { case failed }
}
