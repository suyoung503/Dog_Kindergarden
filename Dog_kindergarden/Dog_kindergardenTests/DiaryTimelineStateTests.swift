import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("알림장 비동기 컨텍스트 경계")
@MainActor
struct DiaryTimelineStateTests {
    private func identity(_ rid: Int = 10, user: Int = 1, token: String = "session-a", base: String = "https://a.invalid/api") -> DiaryTimelineIdentity {
        DiaryTimelineIdentity(userId: user, token: token, baseURL: URL(string: base)!, reservationId: rid, canWrite: true)
    }

    private func entry(_ id: Int) -> DiaryEntry {
        DiaryEntry(diaryId: id, content: "기록 \(id)", createdAt: nil, photos: nil)
    }

    @Test("예약 A 조회가 늦게 끝나도 예약 B 결과를 덮지 않는다")
    func reservationSwitch() async {
        let state = DiaryTimelineState()
        let a = identity(), b = identity(20)
        var current = a
        state.activate(a)
        let gate = DiaryResultGate<[DiaryEntry]>()
        let task = Task { await state.load(for: a, currentIdentity: { current }, fetch: { _ in try await gate.wait() }) }
        await gate.waitUntilStarted()
        current = b
        state.activate(b)
        await state.load(for: b, currentIdentity: { current }, fetch: { _ in [entry(20)] })
        gate.finish(.success([entry(10)]))
        await task.value
        #expect(state.entries.map(\.id) == [20])
        #expect(state.loadPhase == .loaded)
    }

    @Test("같은 UID에서도 토큰 또는 API 주소가 바뀐 응답은 폐기하고 이전 기록을 지운다")
    func credentialSwitch() async {
        for replacement in [identity(token: "session-b"), identity(base: "https://b.invalid/api"), identity(user: 2)] {
            let state = DiaryTimelineState()
            let a = identity()
            var current = a
            state.activate(a)
            await state.load(for: a, currentIdentity: { current }, fetch: { _ in [entry(1)] })
            let gate = DiaryResultGate<[DiaryEntry]>()
            let task = Task { await state.load(for: a, currentIdentity: { current }, fetch: { _ in try await gate.wait() }) }
            await gate.waitUntilStarted()
            current = replacement
            gate.finish(.success([entry(99)]))
            await task.value
            #expect(state.entries.isEmpty)
        }
    }

    @Test("취소를 무시한 조회가 완료되어도 화면 상태를 바꾸지 않는다")
    func cancelledLoad() async {
        let state = DiaryTimelineState(), a = identity()
        state.activate(a)
        let gate = DiaryResultGate<[DiaryEntry]>()
        let task = Task { await state.load(for: a, currentIdentity: { a }, fetch: { _ in try await gate.wait() }) }
        await gate.waitUntilStarted()
        task.cancel()
        gate.finish(.success([entry(99)]))
        await task.value
        #expect(state.entries.isEmpty)
        #expect(state.loadPhase != .loaded)
    }

    @Test("화면이 사라지거나 같은 예약을 다시 열면 옛 작업은 새 활성화에 영향을 주지 않는다")
    func invalidationAndReappearance() async {
        let state = DiaryTimelineState(), a = identity()
        let lease = state.activate(a)
        let gate = DiaryResultGate<[DiaryEntry]>()
        let task = Task { await state.load(for: a, currentIdentity: { a }, fetch: { _ in try await gate.wait() }) }
        await gate.waitUntilStarted()
        state.invalidate()
        state.activate(a)
        await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(2)] })
        state.invalidate(lease: lease)
        gate.finish(.success([entry(99)]))
        await task.value
        #expect(state.entries.map(\.id) == [2])
    }

    @Test("먼저 시작한 갱신이 늦게 끝나도 최신 갱신을 덮지 않는다")
    func newestRefreshWins() async {
        let state = DiaryTimelineState(), a = identity()
        state.activate(a)
        let gate = DiaryResultGate<[DiaryEntry]>()
        let task = Task { await state.load(for: a, currentIdentity: { a }, fetch: { _ in try await gate.wait() }) }
        await gate.waitUntilStarted()
        await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(2)] })
        gate.finish(.success([entry(1)]))
        await task.value
        #expect(state.entries.map(\.id) == [2])
    }

    @Test("일반 갱신 중 기록을 유지하고 실패 후 재시도로 회복한다")
    func refreshAndRetry() async {
        let state = DiaryTimelineState(), a = identity()
        state.activate(a)
        await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(1)] })
        let gate = DiaryResultGate<[DiaryEntry]>()
        let task = Task { await state.load(for: a, currentIdentity: { a }, fetch: { _ in try await gate.wait() }) }
        await gate.waitUntilStarted()
        #expect(state.entries.map(\.id) == [1])
        #expect(state.loadPhase == .loading)
        gate.finish(.failure(URLError(.notConnectedToInternet)))
        await task.value
        #expect(state.entries.map(\.id) == [1])
        #expect(state.accessFailureRevision == 0)
        if case .failed = state.loadPhase {} else { Issue.record("네트워크 실패는 재시도 상태여야 한다") }
        await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(2)] })
        #expect(state.entries.map(\.id) == [2])
        #expect(state.loadPhase == .loaded)
    }

    @Test("현재 예약 401·403·404 조회 실패는 기존 민감 기록을 숨기고 재시도할 수 있다")
    func accessFailureClearsEntries() async {
        for error in [APIError.httpStatus(401), .httpStatus(403), .httpStatus(404), .server(status: 403, code: nil, message: nil)] {
            let state = DiaryTimelineState(), a = identity()
            state.activate(a)
            await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(1)] })
            await state.load(for: a, currentIdentity: { a }, fetch: { _ in throw error })
            #expect(state.entries.isEmpty)
            #expect(state.accessFailureRevision == 1)
            if case .failed = state.loadPhase {} else { Issue.record("권한 실패는 재시도 상태여야 한다") }
            await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(2)] })
            #expect(state.entries.map(\.id) == [2])
        }
    }

    @Test("삭제 실패가 늦게 와도 이후 갱신 결과나 오류 상태를 되돌리지 않는다")
    func failedDeleteAfterRefresh() async {
        let state = DiaryTimelineState(), a = identity()
        state.activate(a)
        await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(1), entry(2)] })
        let gate = DiaryResultGate<Void>()
        let task = Task { await state.delete(diaryId: 1, for: a, currentIdentity: { a }, remove: { _ in try await gate.wait() }) }
        await gate.waitUntilStarted()
        await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(3)] })
        gate.finish(.failure(URLError(.timedOut)))
        await task.value
        #expect(state.entries.map(\.id) == [3])
        #expect(state.loadPhase == .loaded)
    }

    @Test("A의 삭제 성공과 실패는 B의 목록이나 진행 상태에 영향을 주지 않는다")
    func staleDeletion() async {
        for succeeds in [true, false] {
            let state = DiaryTimelineState(), a = identity(), b = identity(20)
            var current = a
            state.activate(a)
            await state.load(for: a, currentIdentity: { current }, fetch: { _ in [entry(1)] })
            let gate = DiaryResultGate<Void>()
            let task = Task { await state.delete(diaryId: 1, for: a, currentIdentity: { current }, remove: { _ in try await gate.wait() }) }
            await gate.waitUntilStarted()
            current = b
            state.activate(b)
            await state.load(for: b, currentIdentity: { current }, fetch: { _ in [entry(1), entry(20)] })
            gate.finish(succeeds ? .success(()) : .failure(APIError.httpStatus(403)))
            await task.value
            #expect(state.entries.map(\.id) == [1, 20])
            #expect(state.loadPhase == .loaded)
            #expect(state.accessFailureRevision == 0)
        }
    }

    @Test("삭제 성공 전 시작한 조회가 옛 목록을 반환해도 확정 삭제한 글은 살아나지 않는다")
    func refreshCannotResurrectDeletedEntry() async {
        let state = DiaryTimelineState(), a = identity()
        state.activate(a)
        await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(1), entry(2)] })
        let gate = DiaryResultGate<[DiaryEntry]>()
        let task = Task { await state.load(for: a, currentIdentity: { a }, fetch: { _ in try await gate.wait() }) }
        await gate.waitUntilStarted()
        await state.delete(diaryId: 1, for: a, currentIdentity: { a }, remove: { _ in })
        #expect(state.entries.map(\.id) == [2])
        #expect(state.loadPhase == .loading)
        gate.finish(.success([entry(1), entry(2), entry(3)]))
        await task.value
        #expect(state.entries.map(\.id) == [2, 3])
    }

    @Test("동시 두 삭제 중 한 건이 실패해도 성공한 다른 글을 복원하지 않는다")
    func overlappingDeletes() async {
        let state = DiaryTimelineState(), a = identity()
        state.activate(a)
        await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(1), entry(2)] })
        let gate = DiaryResultGate<Void>()
        let task = Task { await state.delete(diaryId: 1, for: a, currentIdentity: { a }, remove: { _ in try await gate.wait() }) }
        await gate.waitUntilStarted()
        #expect(state.deletingIDs.contains(1))
        await state.delete(diaryId: 1, for: a, currentIdentity: { a }, remove: { _ in Issue.record("같은 글 중복 삭제 요청") })
        await state.delete(diaryId: 2, for: a, currentIdentity: { a }, remove: { _ in })
        gate.finish(.failure(URLError(.timedOut)))
        await task.value
        #expect(state.entries.map(\.id) == [1])
        #expect(state.deletingIDs.isEmpty)
    }

    @Test("권한이 사라진 삭제 실패 뒤 진행 중인 조회도 이전 기록을 다시 표시하지 않는다")
    func forbiddenDeleteInvalidatesRefresh() async {
        let state = DiaryTimelineState(), a = identity()
        state.activate(a)
        await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(1)] })
        let gate = DiaryResultGate<[DiaryEntry]>()
        let task = Task { await state.load(for: a, currentIdentity: { a }, fetch: { _ in try await gate.wait() }) }
        await gate.waitUntilStarted()
        await state.delete(diaryId: 1, for: a, currentIdentity: { a }, remove: { _ in throw APIError.httpStatus(403) })
        gate.finish(.success([entry(1)]))
        await task.value
        #expect(state.entries.isEmpty)
        #expect(state.accessFailureRevision == 1)
        if case .failed = state.loadPhase {} else { Issue.record("권한 실패가 옛 조회로 덮이면 안 된다") }
    }

    @Test("같은 예약을 다시 열어도 이전 활성화의 큐에 있던 재시도는 실행하지 않는다")
    func staleLeaseDoesNotStartRequest() async {
        let state = DiaryTimelineState(), a = identity()
        let oldLease = state.activate(a)
        state.invalidate()
        state.activate(a)
        await state.load(for: a, lease: oldLease, currentIdentity: { a }, fetch: { _ in
            Issue.record("종료된 화면의 재시도가 요청됨")
            return [entry(1)]
        })
        #expect(state.entries.isEmpty)
        #expect(state.loadPhase == .idle)
    }

    @Test("취소된 삭제 완료나 화면 종료 후 실패는 남아 있는 기록을 변경하지 않는다")
    func cancelledDeleteAndDisappearance() async {
        for disappears in [true, false] {
            let state = DiaryTimelineState(), a = identity()
            state.activate(a)
            await state.load(for: a, currentIdentity: { a }, fetch: { _ in [entry(1)] })
            let gate = DiaryResultGate<Void>()
            let task = Task { await state.delete(diaryId: 1, for: a, currentIdentity: { a }, remove: { _ in try await gate.wait() }) }
            await gate.waitUntilStarted()
            if disappears { state.invalidate() } else { task.cancel() }
            gate.finish(disappears ? .failure(URLError(.timedOut)) : .success(()))
            await task.value
            #expect(state.entries.map(\.id) == (disappears ? [] : [1]))
            #expect(state.loadPhase == (disappears ? .idle : .loaded))
        }
    }

    @Test("로그인·예약 정보 누락은 요청하지 않고 재시도 상태를 표시한다")
    func missingContext() async {
        let invalid = [
            DiaryTimelineIdentity(userId: nil, token: "session", baseURL: identity().baseURL, reservationId: 10, canWrite: false),
            DiaryTimelineIdentity(userId: 1, token: nil, baseURL: identity().baseURL, reservationId: 10, canWrite: false),
            DiaryTimelineIdentity(userId: 1, token: "session", baseURL: identity().baseURL, reservationId: nil, canWrite: false)
        ]
        for value in invalid {
            let state = DiaryTimelineState()
            state.activate(value)
            await state.load(for: value, currentIdentity: { value }, fetch: { _ in
                Issue.record("유효하지 않은 컨텍스트로 요청됨")
                return [entry(1)]
            })
            #expect(state.entries.isEmpty)
            if case .failed = state.loadPhase {} else { Issue.record("컨텍스트 실패는 재시도 가능해야 한다") }
        }
    }

    @Test("보호자 읽기 전용 컨텍스트에서는 삭제 요청을 보내지 않는다")
    func guardianCannotDelete() async {
        let writable = identity()
        let guardian = DiaryTimelineIdentity(userId: writable.userId, token: writable.token, baseURL: writable.baseURL, reservationId: writable.reservationId, canWrite: false)
        let state = DiaryTimelineState()
        state.activate(guardian)
        await state.load(for: guardian, currentIdentity: { guardian }, fetch: { _ in [entry(1)] })
        await state.delete(diaryId: 1, for: guardian, currentIdentity: { guardian }, remove: { _ in
            Issue.record("보호자 삭제 요청")
        })
        #expect(state.entries.map(\.id) == [1])
    }

    @Test("이미 큐에 있던 이전 컨텍스트 재시도는 새 예약 요청을 보내지 않는다")
    func staleRetryDoesNotStartRequest() async {
        let state = DiaryTimelineState(), a = identity(), b = identity(20)
        state.activate(a)
        state.activate(b)
        await state.load(for: a, currentIdentity: { b }, fetch: { _ in Issue.record("옛 예약 재시도가 요청됨"); return [entry(1)] })
        #expect(state.entries.isEmpty)
        #expect(state.loadPhase == .idle)
    }
}

@MainActor
private final class DiaryResultGate<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var started: CheckedContinuation<Void, Never>?

    func wait() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ result: Result<Value, Error>) {
        continuation!.resume(with: result)
        continuation = nil
    }
}
