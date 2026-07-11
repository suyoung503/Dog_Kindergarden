import SwiftUI

// 예약 내역 목록 — 지금까지 신청한 예약을 서버(reservations)에서 불러와 표시
struct ReservationListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession

    @State private var reservations: [ReservationSummary] = []
    @State private var isLoading = true
    @State private var pendingCancel: ReservationSummary?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navBar
                if isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if reservations.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(reservations.enumerated()), id: \.offset) { _, reservation in
                            reservationCard(reservation)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task { await load() }
        .alert("예약을 취소할까요?", isPresented: Binding(get: { pendingCancel != nil }, set: { if !$0 { pendingCancel = nil } })) {
            Button("닫기", role: .cancel) {}
            Button("취소하기", role: .destructive) {
                if let target = pendingCancel { cancel(target) }
            }
        } message: {
            Text((pendingCancel?.storeName ?? "가게") + " 예약을 취소합니다. 되돌릴 수 없어요.")
        }
    }

    // MARK: - Nav

    private var navBar: some View {
        HStack(spacing: 12) {
            Button(action: router.back) {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                    .overlay(Image(systemName: "chevron.left").font(.system(size: 15)).foregroundStyle(Color.brandBrown))
            }
            Text("예약 내역")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "📅", size: 48)
            Text("아직 예약 내역이 없어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text("가게 상세에서 예약을 신청하면 여기에 모여요")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
        }
        .padding(.top, 100)
    }

    // MARK: - Card

    private func reservationCard(_ reservation: ReservationSummary) -> some View {
        let isHotel = (reservation.storeType ?? "") == "호텔"
        let isCancelable = reservation.status == "REQUEST" || reservation.status == "CONFIRMED"
        return VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isHotel ? Color(hex: "#FFE6CC") : Color.brandGreenLight)
                        .frame(width: 56, height: 56)
                    EmojiIcon(emoji: isHotel ? "🏨" : "🏠", size: 28)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.storeName ?? "가게 정보 없음")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                    if let schedule = reservation.startDate, !schedule.isEmpty {
                        Text(schedule)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.brandBrownMid)
                    }
                    HStack(spacing: 6) {
                        if let type = reservation.reservationType, !type.isEmpty {
                            Text(type)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.brandBrown)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(hex: "#FFE6CC"))
                                .clipShape(Capsule())
                        }
                        Text(statusLabel(reservation.status))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.brandOrange)
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
            if isCancelable {
                Button(action: { pendingCancel = reservation }) {
                    Text("예약 취소")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.brandOrange)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.brandOrange.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    private func statusLabel(_ status: String?) -> String {
        switch status {
        case "REQUEST": return "예약 요청됨"
        case "CONFIRMED": return "예약 확정"
        case "CANCELED": return "예약 취소됨"
        default: return status ?? "상태 정보 없음"
        }
    }

    // MARK: - Actions

    private func load() async {
        defer { isLoading = false }
        guard let uid = authSession.userId else { return }
        reservations = (try? await APIClient.shared.fetchReservations(userId: uid)) ?? []
        // 사장님이 취소한 예약의 일정을 내 기기 캘린더에서 제거
        await CalendarService.syncReservationEvents(reservations)
    }

    // 낙관적 취소 — 실패 시 원래 상태로 복원
    private func cancel(_ reservation: ReservationSummary) {
        guard let rid = reservation.reservationId,
              let index = reservations.firstIndex(where: { $0.reservationId == rid }) else { return }
        let previous = reservations[index]
        reservations[index] = ReservationSummary(
            reservationId: previous.reservationId,
            storeId: previous.storeId,
            storeName: previous.storeName,
            storeType: previous.storeType,
            startDate: previous.startDate,
            endDate: previous.endDate,
            reservationType: previous.reservationType,
            status: "CANCELED"
        )
        Task {
            do {
                try await APIClient.shared.cancelReservation(reservationId: rid)
                await CalendarService.removeReservationEvent(reservationId: rid)
            } catch {
                reservations[index] = previous
            }
        }
    }
}
