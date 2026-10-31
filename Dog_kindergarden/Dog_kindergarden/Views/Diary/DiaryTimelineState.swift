import Foundation
import Observation

/// 토큰은 요청 경계 비교에만 쓰며 표시하거나 로그로 남기지 않는다.
struct DiaryTimelineIdentity: Hashable {
    let userId: Int?
    let token: String?
    let baseURL: URL
    let reservationId: Int?
    let canWrite: Bool
}

@Observable
@MainActor
final class DiaryTimelineState {
    private(set) var entries: [DiaryEntry] = []
    private(set) var loadPhase: AsyncLoadPhase = .idle
    private(set) var deletingIDs: Set<Int> = []
    private(set) var identity: DiaryTimelineIdentity?
    private(set) var lease: UInt = 0
    private(set) var accessFailureRevision: UInt = 0
    private var loadGeneration: UInt = 0
    private var deletedIDs: Set<Int> = []

    @discardableResult
    func activate(_ identity: DiaryTimelineIdentity) -> UInt {
        lease &+= 1
        loadGeneration &+= 1
        if self.identity != identity {
            entries = []
            deletedIDs = []
            loadPhase = .idle
        }
        self.identity = identity
        deletingIDs = []
        return lease
    }

    func invalidate(lease expectedLease: UInt? = nil) {
        if let expectedLease, expectedLease != lease { return }
        lease &+= 1
        loadGeneration &+= 1
        identity = nil
        entries = []
        deletingIDs = []
        deletedIDs = []
        loadPhase = .idle
    }

    func load(
        for identity: DiaryTimelineIdentity,
        lease expectedLease: UInt? = nil,
        currentIdentity: () -> DiaryTimelineIdentity,
        fetch: (Int) async throws -> [DiaryEntry]
    ) async {
        let requestLease = expectedLease ?? lease
        guard isCurrent(identity, lease: requestLease, currentIdentity: currentIdentity) else { return }
        guard let rid = identity.reservationId, rid > 0,
              identity.userId != nil, let token = identity.token, !token.isEmpty else {
            entries = []
            loadPhase = .failed("예약 또는 로그인 정보를 확인하지 못했어요. 다시 시도해 주세요.")
            return
        }
        loadGeneration &+= 1
        let generation = loadGeneration
        loadPhase = .loading
        do {
            let loaded = try await fetch(rid)
            guard isCurrent(identity, lease: requestLease, currentIdentity: currentIdentity),
                  generation == loadGeneration else { return }
            // 삭제 직전에 시작된 조회가 늦게 끝나도 확정 삭제한 글을 되살리지 않는다.
            entries = loaded.filter { !deletedIDs.contains($0.id) }
            loadPhase = .loaded
        } catch {
            guard isCurrent(identity, lease: requestLease, currentIdentity: currentIdentity),
                  generation == loadGeneration else { return }
            if Self.isCancellation(error) {
                loadPhase = entries.isEmpty ? .idle : .loaded
                return
            }
            if Self.isAccessFailure(error) {
                entries = []
                accessFailureRevision &+= 1
            }
            loadPhase = .failed("알림장을 불러오지 못했어요. 연결 또는 예약 접근 권한을 확인하고 다시 시도해 주세요.")
        }
    }

    func delete(
        diaryId: Int,
        for identity: DiaryTimelineIdentity,
        lease expectedLease: UInt? = nil,
        currentIdentity: () -> DiaryTimelineIdentity,
        remove: (Int) async throws -> Void
    ) async {
        let requestLease = expectedLease ?? lease
        guard isCurrent(identity, lease: requestLease, currentIdentity: currentIdentity),
              identity.canWrite, !deletingIDs.contains(diaryId),
              entries.contains(where: { $0.diaryId == diaryId }) else { return }
        let generation = loadGeneration
        deletingIDs.insert(diaryId)
        defer {
            if self.lease == requestLease { deletingIDs.remove(diaryId) }
        }
        do {
            try await remove(diaryId)
            guard isCurrent(identity, lease: requestLease, currentIdentity: currentIdentity) else { return }
            deletedIDs.insert(diaryId)
            // 성공한 글만 제거한다. 전체 배열 백업/복원은 동시 삭제나 새 조회를 되돌릴 수 있다.
            entries.removeAll { $0.diaryId == diaryId }
        } catch {
            guard isCurrent(identity, lease: requestLease, currentIdentity: currentIdentity),
                  !Self.isCancellation(error) else { return }
            if Self.isAccessFailure(error) {
                loadGeneration &+= 1
                entries = []
                accessFailureRevision &+= 1
            } else if generation != loadGeneration {
                return
            }
            loadPhase = .failed("알림장을 삭제하지 못했어요. 연결 또는 예약 접근 권한을 확인하고 다시 시도해 주세요.")
        }
    }

    private func isCurrent(
        _ identity: DiaryTimelineIdentity,
        lease expectedLease: UInt,
        currentIdentity: () -> DiaryTimelineIdentity
    ) -> Bool {
        guard !Task.isCancelled, lease == expectedLease, self.identity == identity else { return false }
        guard currentIdentity() == identity else {
            invalidate(lease: expectedLease)
            return false
        }
        return true
    }

    private static func isAccessFailure(_ error: Error) -> Bool {
        guard let error = error as? APIError else { return false }
        switch error {
        case .httpStatus(let status), .server(let status, _, _):
            return [401, 403, 404].contains(status)
        case .badStatus:
            return false
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
