import SwiftUI

// 이전 진입점 호환. 실제 화면과 카드는 예약 관리에서 공용으로 사용한다.
struct OwnerDiaryListView: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        OwnerModeView()
            .onAppear { router.ownerReservationTab = .confirmed }
    }
}

struct OwnerReservationCard: View {
    @Environment(AppRouter.self) private var router
    let reservation: PendingReservation
    let isConfirmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                open(.information)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    AuthenticatedPetImage(value: reservation.petImageUrl)
                        .frame(width: 56, height: 56)
                        .background(Color.brandGreenLight)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(OwnerReservationPresentation.value(reservation.petName))
                            .font(.system(size: 16, weight: .bold))
                        Text("보호자: \(OwnerReservationPresentation.value(reservation.userName))")
                        Text(OwnerReservationPresentation.value(reservation.storeName))
                        Text(OwnerReservationPresentation.schedule(reservation))
                        Text(OwnerReservationPresentation.value(reservation.reservationType))
                    }
                    .font(.system(size: 12)).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isConfirmed {
                Button("알림장 작성") { open(.diary) }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.brandOrange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .foregroundStyle(Color.brandBrown)
        .padding(16).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    private func open(_ tab: OwnerReservationDetailTab) {
        guard let rid = reservation.reservationId else { return }
        router.diaryContext = DiaryContext(reservationId: rid,
            petName: reservation.petName ?? "우리 아이", storeName: reservation.storeName ?? "가게",
            canWrite: true, petImageUrl: reservation.petImageUrl)
        router.openOwnerReservation(id: rid, tab: tab)
    }
}
