import SwiftUI

// 사장님 홈 FAB '알림장' 진입 — 내 가게(owner_id)로 온 확정(CONFIRMED) 예약(맡은 아이들) 목록.
// 예약을 누르면 그 예약의 알림장 타임라인으로 이동(작성 가능).
struct OwnerDiaryListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession

    @State private var reservations: [PendingReservation] = []
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
            Text("알림장")
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
            EmojiIcon(emoji: "📔", size: 48)
            Text("맡은 아이가 없어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text("예약을 확정하면 그 아이의 알림장을\n여기서 남길 수 있어요")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.top, 100)
    }

    // MARK: - Card

    private func reservationCard(_ reservation: PendingReservation) -> some View {
        let isHotel = (reservation.storeType ?? "") == "호텔"
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isHotel ? Color(hex: "#FFE6CC") : Color.brandGreenLight)
                    .frame(width: 56, height: 56)
                EmojiIcon(emoji: "img:\(dogAvatarName(reservation.reservationId ?? 0))", size: 30)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(reservation.petName ?? "미상")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Text("보호자 : \(reservation.userName ?? "미상")")
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

    // 예약 id 기준 고정 순환 아바타 (받은 문의와 동일 규칙)
    private func dogAvatarName(_ id: Int) -> String {
        id % 2 == 0 ? "dog_b" : "dog_c"
    }

    // MARK: - Actions

    private func load() async {
        defer { isLoading = false }
        guard let uid = authSession.userId else { return }
        reservations = (try? await APIClient.shared.fetchConfirmedReservations(ownerId: uid)) ?? []
    }

    private func open(_ reservation: PendingReservation) {
        guard let rid = reservation.reservationId else { return }
        router.diaryContext = DiaryContext(
            reservationId: rid,
            petName: reservation.petName ?? "우리 아이",
            storeName: reservation.storeName ?? "가게",
            canWrite: true
        )
        router.go(.diary)
    }
}
