import SwiftUI

// 보호자 홈 FAB '내 알림장' 진입 — 내가 확정(CONFIRMED)한 예약(맡긴 아이들) 목록.
// 예약을 누르면 그 예약의 알림장 타임라인으로 이동(열람 전용).
struct MyDiaryListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession

    @State private var reservations: [ReservationSummary] = []
    @State private var isLoading = true

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
            VStack(alignment: .leading, spacing: 2) {
                Text("내 알림장")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Text("확정된 예약 기록이에요")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brandBrownMid)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "📔", size: 48)
            Text("확정된 예약이 없어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text("예약이 확정되면 그 아이의 알림장을\n여기서 볼 수 있어요")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 100)
    }

    // MARK: - Card

    private func reservationCard(_ reservation: ReservationSummary) -> some View {
        let isHotel = (reservation.storeType ?? "") == "호텔"
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isHotel ? Color(hex: "#FFE6CC") : Color.brandGreenLight)
                    .frame(width: 56, height: 56)
                EmojiIcon(emoji: isHotel ? "🏨" : "🏠", size: 28)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(reservation.petName ?? "우리 아이")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Text("가게 : \(reservation.storeName ?? "미상")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.brandBrownMid)
                Text(reservation.startDate ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brandBrownMid)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brandBrownLight)
                .padding(.top, 4)
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { open(reservation) }
    }

    // MARK: - Actions

    private func load() async {
        defer { isLoading = false }
        guard let uid = authSession.userId else { return }
        let all = (try? await APIClient.shared.fetchReservations(userId: uid)) ?? []
        reservations = all.filter { $0.status == "CONFIRMED" }
    }

    // 보호자 열람 전용으로 알림장 진입 — 예약에 담긴 실제 강아지 이름 사용
    private func open(_ reservation: ReservationSummary) {
        guard let rid = reservation.reservationId else { return }
        router.diaryContext = DiaryContext(
            reservationId: rid,
            petName: reservation.petName ?? "우리 아이",
            storeName: reservation.storeName ?? "가게",
            canWrite: false
        )
        router.go(.diary)
    }
}
