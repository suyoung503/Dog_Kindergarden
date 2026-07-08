import SwiftUI

// 보호자 겸 사장님 계정의 홈 사이드바에서 진입 — 받은 예약 요청(REQUEST) 목록을 확인하고 확정하는 최소 화면
// 업체-가게 소유 관계가 DB에 없어 전체 가게의 요청을 함께 보여준다 (데모 범위)
struct OwnerModeView: View {
    @Environment(AppRouter.self) private var router

    @State private var reservations: [PendingReservation] = []
    @State private var isLoading = true
    @State private var confirmingId: Int?

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
                        ForEach(reservations, id: \.reservationId) { reservation in
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
            Text("받은 예약 요청")
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
            EmojiIcon(emoji: "📭", size: 48)
            Text("받은 예약 요청이 없어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .padding(.top, 100)
    }

    // MARK: - Card

    private func reservationCard(_ reservation: PendingReservation) -> some View {
        let isHotel = (reservation.storeType ?? "") == "호텔"
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
                    Text("\(reservation.petName ?? "강아지") · \(reservation.startDate ?? "")")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.brandBrownMid)
                    if let type = reservation.reservationType, !type.isEmpty {
                        Text(type)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.brandBrown)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(hex: "#FFE6CC"))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
            }
            Button(action: { confirm(reservation) }) {
                if confirmingId == reservation.reservationId {
                    ProgressView().tint(.white)
                        .frame(height: 16)
                } else {
                    Text("확정하기")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.brandOrange)
            .clipShape(Capsule())
            .buttonStyle(.plain)
            .disabled(confirmingId != nil)
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    // MARK: - Actions

    private func load() async {
        defer { isLoading = false }
        reservations = (try? await APIClient.shared.fetchPendingReservations()) ?? []
    }

    private func confirm(_ reservation: PendingReservation) {
        guard let rid = reservation.reservationId else { return }
        confirmingId = rid
        Task {
            defer { confirmingId = nil }
            do {
                try await APIClient.shared.confirmReservation(reservationId: rid)
            } catch {
                return
            }
            if let schedule = reservation.startDate, let date = CalendarService.parseSchedule(schedule) {
                await CalendarService.addReservationEvent(
                    reservationId: rid,
                    title: "\(reservation.storeName ?? "예약") · \(reservation.petName ?? "")",
                    notes: reservation.requestMessage,
                    date: date
                )
            }
            reservations.removeAll { $0.reservationId == rid }
        }
    }
}
