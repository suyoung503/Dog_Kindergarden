import SwiftUI

// 사장님 예약 관리 — 요청과 확정 예약의 단일 진입점.
struct OwnerModeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppNotificationService.self) private var notificationService
    @Environment(AuthSession.self) private var authSession
    @State private var requests: [PendingReservation] = []
    @State private var confirmed: [PendingReservation] = []
    @State private var loadPhase: AsyncLoadPhase = .idle
    @State private var loadedOwnerId: Int?
    @State private var loadGeneration = 0
    @State private var showsUnknownDates = false

    private var reservations: [PendingReservation] {
        router.ownerReservationTab == .requests ? requests : OwnerReservationCalendar.reservations(confirmed, on: router.ownerCalendarState.selectedDate)
    }

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: router.back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36).background(.white).clipShape(Circle())
                }
                Text("예약 관리").font(.system(size: 17, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 20).safeAreaTopPadding()
            Picker("예약 상태", selection: $router.ownerReservationTab) {
                Text("예약 요청 \(requests.count)").tag(OwnerReservationTab.requests)
                Text(confirmedCountLabel).tag(OwnerReservationTab.confirmed)
            }
            .pickerStyle(.segmented).padding(20)
            if case .loaded = loadPhase, router.ownerReservationTab == .confirmed {
                OwnerReservationCalendarView(selectedDate: Binding(
                    get: { router.ownerCalendarState.selectedDate },
                    set: { router.ownerCalendarState.select($0) }
                ), reservations: confirmed)
            }
            ScrollView {
                VStack(spacing: 12) {
                    switch loadPhase {
                    case .idle, .loading:
                        AsyncLoadingStateView(message: "예약을 불러오는 중이에요")
                    case .failed(let message):
                        AsyncLoadFailureView(message: message) { Task { await load() } }
                    case .loaded:
                        if router.ownerReservationTab == .confirmed {
                            confirmedDateHeading
                        }
                        if reservations.isEmpty {
                            Text(router.ownerReservationTab == .requests ? "받은 예약 요청이 없어요" : "이 날짜에 이용하는 확정 예약이 없어요")
                                .font(.system(size: 15, weight: .semibold)).padding(.top, 100)
                        } else {
                            ForEach(reservations) { reservation in
                                OwnerReservationCard(reservation: reservation,
                                                     isConfirmed: router.ownerReservationTab == .confirmed)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .foregroundStyle(Color.brandBrown)
        .background(Color.brandCream.ignoresSafeArea())
        .task(id: authSession.userId) {
            let updates = notificationService.updates()
            await load()
            for await _ in updates {
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    private var confirmedCountLabel: String {
        if case .loaded = loadPhase { return "확정 예약 \(confirmed.count)" }
        return "확정 예약 —"
    }

    private var confirmedDateHeading: some View {
        let unknownCount = OwnerReservationCalendar.unknownDateReservations(confirmed).count
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(OwnerReservationCalendar.label(router.ownerCalendarState.selectedDate, format: "M월 d일")) · 확정 예약 \(reservations.count)건")
                .font(.system(size: 16, weight: .bold))
            if unknownCount > 0 {
                DisclosureGroup(isExpanded: $showsUnknownDates) {
                    VStack(spacing: 12) {
                        Text("이용일을 확인할 수 없는 예약이에요. 예약 정보에서 원래 일정을 확인해 주세요.")
                            .font(.system(size: 12))
                        ForEach(OwnerReservationCalendar.unknownDateReservations(confirmed)) { reservation in
                            OwnerReservationCard(reservation: reservation, isConfirmed: true)
                        }
                    }
                } label: {
                    Text("날짜 확인 필요 \(unknownCount)건")
                        .font(.system(size: 13, weight: .semibold)).frame(minHeight: 44)
                }
                .tint(Color.brandOrange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        guard let uid = authSession.userId else {
            requests = []; confirmed = []
            loadPhase = .failed("로그인 정보를 확인하지 못했어요.")
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        if loadedOwnerId != uid {
            requests = []; confirmed = []
            loadPhase = .idle
            loadedOwnerId = uid
        }
        // 갱신 중에는 기존 카드와 선택일을 유지하고, 실패하면 민감 정보를 제거한다.
        if case .loaded = loadPhase {} else { loadPhase = .loading }
        do {
            async let pending = APIClient.shared.fetchPendingReservations(ownerId: uid)
            async let accepted = APIClient.shared.fetchConfirmedReservations(ownerId: uid)
            let (newRequests, newConfirmed) = try await (pending, accepted)
            guard !Task.isCancelled, authSession.userId == uid, loadGeneration == generation else { return }
            requests = newRequests; confirmed = newConfirmed
            loadPhase = .loaded
        } catch {
            guard !Task.isCancelled, authSession.userId == uid, loadGeneration == generation else { return }
            requests = []; confirmed = []
            loadPhase = .failed("예약 목록을 불러오지 못했어요. 연결과 사장님 권한을 확인한 뒤 다시 시도해 주세요.")
        }
    }
}
