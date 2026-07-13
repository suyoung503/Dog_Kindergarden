import SwiftUI

// 사장님 계정의 홈 사이드바에서 진입 — 내 가게(owner_id)로 받은 예약 요청(REQUEST)을 확인하고 확정하는 화면
struct OwnerModeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession

    @State private var reservations: [PendingReservation] = []
    @State private var isLoading = true
    @State private var confirmingId: Int?
    @State private var pendingCancel: PendingReservation?
    @State private var selectedDetail: PendingReservation?   // 카드 탭 → 상세 시트

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
        .alert("예약 요청을 취소할까요?", isPresented: Binding(get: { pendingCancel != nil }, set: { if !$0 { pendingCancel = nil } })) {
            Button("닫기", role: .cancel) {}
            Button("예약 취소", role: .destructive) {
                if let target = pendingCancel { cancel(target) }
            }
        } message: {
            Text("\(pendingCancel?.petName ?? "강아지") 보호자에게 '예약 취소됨'으로 표시됩니다.")
        }
        .sheet(item: $selectedDetail) { reservation in
            PendingDetailSheet(reservation: reservation)
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
            Text("마이페이지에서 내 가게를 등록하면\n그 가게로 온 예약 요청이 보여요")
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
                    // 강아지·예약자를 라벨로 구별해 두 줄로 표시
                    Text("강아지 : \(reservation.petName ?? "미상")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.brandBrown)
                    Text("예약자 : \(reservation.userName ?? "미상")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.brandBrown)
                    Text(reservation.startDate ?? "")
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
            HStack(spacing: 8) {
                Button(action: { pendingCancel = reservation }) {
                    Text("예약 취소")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.brandOrange)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.brandOrange.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(confirmingId != nil)
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
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        // 카드 탭 → 상세 시트 (취소/확정 버튼 터치는 버튼이 우선 처리)
        .contentShape(Rectangle())
        .onTapGesture { selectedDetail = reservation }
    }

    // MARK: - Actions

    private func load() async {
        defer { isLoading = false }
        guard let uid = authSession.userId else { return }
        reservations = (try? await APIClient.shared.fetchPendingReservations(ownerId: uid)) ?? []
    }

    // 확정 — 캘린더 일정은 여기(사장님 기기)가 아니라 고객 기기가 예약 내역을 열 때
    // CalendarService.syncReservationEvents가 CONFIRMED를 감지해 추가한다
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
            reservations.removeAll { $0.reservationId == rid }
        }
    }

    // 예약 취소 — 고객에게는 '예약 취소됨' 상태로 표시된다
    private func cancel(_ reservation: PendingReservation) {
        guard let rid = reservation.reservationId else { return }
        confirmingId = rid
        Task {
            defer { confirmingId = nil }
            do {
                try await APIClient.shared.cancelReservation(reservationId: rid, byOwner: true)
            } catch {
                return
            }
            reservations.removeAll { $0.reservationId == rid }
        }
    }
}

// MARK: - 상세 시트

// 카드 탭 시 화면 이동 없이 뜨는 예약 요청 상세 — 강아지·손님·예약 정보
private struct PendingDetailSheet: View {
    let reservation: PendingReservation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("예약 요청 상세")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                section("강아지 정보") {
                    infoRow("이름",   reservation.petName ?? "미상")
                    infoRow("견종",   reservation.petBreed ?? "미상")
                    infoRow("나이",   reservation.petAge.map { "\($0)살" } ?? "미상")
                    infoRow("몸무게", reservation.petWeight.map { "\($0)kg" } ?? "미상")
                    infoRow("성별",   reservation.petGender ?? "미상")
                    infoRow("메모",   (reservation.petNote?.isEmpty == false ? reservation.petNote! : "없음"))
                }
                section("예약자 정보") {
                    infoRow("이름",   reservation.userName ?? "미상")
                    infoRow("연락처", (reservation.userPhone?.isEmpty == false ? reservation.userPhone! : "미상"))
                    infoRow("주소",   (reservation.userAddress?.isEmpty == false ? reservation.userAddress! : "미상"))
                }
                section("예약 정보") {
                    infoRow("가게",     reservation.storeName ?? "미상")
                    infoRow("일정",     reservation.startDate ?? "미상")
                    infoRow("유형",     reservation.reservationType ?? "미상")
                    infoRow("요청사항", (reservation.requestMessage?.isEmpty == false ? reservation.requestMessage! : "없음"))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.brandCream)
        .presentationDetents([.medium, .large])
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EmojiTitle(title: title)
            VStack(spacing: 6) { content() }
                .padding(12)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
            Spacer()
            Text(v)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#7a5635"))
                .multilineTextAlignment(.trailing)
        }
    }
}
