import Foundation
import Observation

enum OwnerReservationTab: String, CaseIterable {
    case requests, confirmed
    var title: String { self == .requests ? "예약 요청" : "확정 예약" }
}

enum OwnerReservationDetailTab: String, CaseIterable {
    case information, diary
    var title: String { self == .information ? "예약 정보" : "알림장" }
}

struct OwnerReservationContext {
    let reservationId: Int
    let initialTab: OwnerReservationDetailTab
    var focusOnStartDate: Bool

    init(reservationId: Int, initialTab: OwnerReservationDetailTab, focusOnStartDate: Bool = false) {
        self.reservationId = reservationId
        self.initialTab = initialTab
        self.focusOnStartDate = focusOnStartDate
    }
}

enum OwnerReservationPresentation {
    static func value(_ text: String?) -> String {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "미입력" }
        return text
    }

    static func schedule(_ reservation: PendingReservation) -> String {
        let start = value(reservation.startDate)
        guard let end = reservation.endDate, !end.isEmpty, end != reservation.startDate else { return start }
        return "\(start) ~ \(end)"
    }
}

// '/'가 메모 값에도 들어갈 수 있으므로 알려진 라벨 경계만 분리한다. 원문도 함께 보존한다.
struct OwnerReservationNote {
    let original: String
    let sociability: String
    let allergy: String
    let special: String

    init(_ raw: String?) {
        original = OwnerReservationPresentation.value(raw)
        let text = raw ?? ""
        let pattern = #"(?:^| / )(사회성|알레르기|특이사항):\s*"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var fields: [String: String] = [:]
        for (index, match) in matches.enumerated() {
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let value = ns.substring(with: NSRange(location: NSMaxRange(match.range), length: end - NSMaxRange(match.range)))
            fields[ns.substring(with: match.range(at: 1))] = OwnerReservationPresentation.value(value)
        }
        sociability = fields["사회성"] ?? "미입력"
        allergy = fields["알레르기"] ?? "미입력"
        special = fields["특이사항"] ?? (matches.isEmpty ? OwnerReservationPresentation.value(raw) : "미입력")
    }
}

extension PendingReservation {
    var ownerInformationSourceLabel: String {
        informationSource == "BOOKING_SNAPSHOT" ? "신청 당시 정보" : "신청 당시 정보 미보관 · 현재 정보 기준"
    }
}

@MainActor
@Observable
final class OwnerReservationDetailState {
    var selectedTab: OwnerReservationDetailTab = .information
    private(set) var reservation: PendingReservation?
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var errorMessage: String?
    private(set) var actionError: String?
    private(set) var didCancel = false
    private(set) var didConfirm = false
    private var generation = 0
    private var loadedOwnerId: Int?

    func load(ownerId: Int, currentUserId: () -> Int?, fetch: () async throws -> PendingReservation) async {
        generation += 1
        let request = generation
        if loadedOwnerId != ownerId { reservation = nil }
        loadedOwnerId = ownerId
        errorMessage = nil
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let item = try await fetch()
            guard !Task.isCancelled, generation == request else { return }
            guard currentUserId() == ownerId else { reservation = nil; return }
            guard item.status == "REQUEST" || item.status == "CONFIRMED" else {
                reservation = nil
                errorMessage = "더 이상 확인할 수 없는 예약이에요. 예약 관리에서 다시 확인해 주세요."
                return
            }
            reservation = item
            if item.status == "REQUEST" { selectedTab = .information }
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            guard currentUserId() == ownerId else { reservation = nil; return }
            if error is CancellationError { return }
            reservation = nil
            errorMessage = "예약 정보를 불러오지 못했어요. 권한이나 예약 상태가 변경되었을 수 있어요."
        }
    }

    func confirm(ownerId: Int, currentUserId: () -> Int?, action: () async throws -> Void,
                 fetch: () async throws -> PendingReservation) async {
        guard !isMutating, reservation?.status == "REQUEST", currentUserId() == ownerId else { return }
        isMutating = true
        actionError = nil
        defer { isMutating = false }
        do {
            try await action()
            guard !Task.isCancelled, currentUserId() == ownerId else { reservation = nil; return }
            didConfirm = true
            await load(ownerId: ownerId, currentUserId: currentUserId, fetch: fetch)
        } catch {
            guard !Task.isCancelled, currentUserId() == ownerId else { reservation = nil; return }
            if error is CancellationError { return }
            if invalidateUnavailableReservation(error) { return }
            actionError = "예약을 확정하지 못했어요. 요청은 그대로 유지했어요."
        }
    }

    func cancel(ownerId: Int, currentUserId: () -> Int?, action: () async throws -> Void) async {
        guard !isMutating, reservation?.status == "REQUEST", currentUserId() == ownerId else { return }
        isMutating = true
        actionError = nil
        defer { isMutating = false }
        do {
            try await action()
            guard !Task.isCancelled, currentUserId() == ownerId else { reservation = nil; return }
            reservation = nil
            didCancel = true
        } catch {
            guard !Task.isCancelled, currentUserId() == ownerId else { reservation = nil; return }
            if error is CancellationError { return }
            if invalidateUnavailableReservation(error) { return }
            actionError = "예약 취소를 완료하지 못했어요. 요청은 그대로 유지했어요."
        }
    }

    private func invalidateUnavailableReservation(_ error: Error) -> Bool {
        let status: Int
        switch error {
        case APIError.httpStatus(let value): status = value
        case APIError.server(let value, _, _): status = value
        default: return false
        }
        guard [401, 403, 404, 409].contains(status) else { return false }
        reservation = nil
        errorMessage = "예약 상태나 사장님 권한이 변경되었어요. 다시 확인해 주세요."
        return true
    }

}
