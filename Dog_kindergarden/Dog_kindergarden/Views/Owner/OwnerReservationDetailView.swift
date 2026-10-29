import SwiftUI

struct OwnerReservationDetailView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession
    @Environment(AppNotificationService.self) private var notificationService
    @State private var state = OwnerReservationDetailState()
    @State private var showCancelConfirmation = false

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: router.back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36).background(.white).clipShape(Circle())
                }
                Text("예약 상세").font(.system(size: 17, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 20).safeAreaTopPadding().padding(.bottom, 12)
            if let reservation = state.reservation {
                header(reservation)
                if reservation.status == "CONFIRMED" {
                    Picker("상세 탭", selection: $state.selectedTab) {
                        ForEach(OwnerReservationDetailTab.allCases, id: \.self) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)
                }
                if state.selectedTab == .diary && reservation.status == "CONFIRMED" {
                    DiaryTimelineView(embedded: true, embeddedContext: diaryContext(reservation))
                } else {
                    information(reservation)
                }
                if let error = state.actionError {
                    Text(error).font(.system(size: 12)).foregroundStyle(Color.brandOrange).padding(12)
                }
                if reservation.status == "REQUEST" { requestActions }
            } else if state.isLoading {
                AsyncLoadingStateView(message: "예약 정보를 불러오는 중이에요")
                Spacer()
            } else {
                AsyncLoadFailureView(message: state.errorMessage ?? "예약 정보를 확인할 수 없어요.") {
                    Task { await load() }
                }
                Spacer()
            }
        }
        .foregroundStyle(Color.brandBrown)
        .background(Color.brandCream.ignoresSafeArea())
        .task(id: authSession.userId) {
            state.selectedTab = router.ownerReservationContext?.initialTab ?? .information
            let updates = notificationService.updates()
            await load()
            for await _ in updates {
                guard !Task.isCancelled else { return }
                guard !state.isMutating else { continue }
                await load()
            }
        }
        .onChange(of: router.ownerReservationContext?.initialTab) { _, tab in
            if let tab { state.selectedTab = tab }
        }
        .onChange(of: router.ownerReservationContext?.focusOnStartDate) { _, shouldFocus in
            if shouldFocus == true, let reservation = state.reservation,
               reservation.id == router.ownerReservationContext?.reservationId {
                router.focusOwnerReservationStartDate(reservation.startDate, expectedReservationId: reservation.id)
            }
        }
        .alert("예약 요청을 취소할까요?", isPresented: $showCancelConfirmation) {
            Button("닫기", role: .cancel) {}
            Button("예약 취소", role: .destructive) { Task { await cancel() } }
        } message: {
            Text("보호자에게 예약 취소로 표시돼요. 이 작업은 되돌릴 수 없어요.")
        }
    }

    private func header(_ reservation: PendingReservation) -> some View {
        HStack(spacing: 12) {
            AuthenticatedPetImage(value: reservation.petImageUrl)
                .frame(width: 60, height: 60).background(Color.brandGreenLight).clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(OwnerReservationPresentation.value(reservation.petName)).font(.system(size: 18, weight: .bold))
                Text(OwnerReservationPresentation.schedule(reservation)).font(.system(size: 12))
                Text(reservation.status == "CONFIRMED" ? "확정 예약" : "예약 요청")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.brandOrange)
            }
            Spacer(minLength: 0)
        }
        .padding(16).background(.white)
    }

    private func information(_ reservation: PendingReservation) -> some View {
        let note = OwnerReservationNote(reservation.petNote)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(reservation.ownerInformationSourceLabel)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.brandBrownMid)
                section("주의사항") {
                    row("사회성", note.sociability)
                    row("알레르기", note.allergy)
                    row("특이사항", note.special)
                }
                section("강아지 정보") {
                    row("이름", reservation.petName)
                    row("견종", reservation.petBreed)
                    row("나이", reservation.petAge.map { "\($0)살" })
                    row("몸무게", reservation.petWeight.map { "\($0)kg" })
                    row("성별", reservation.petGender)
                }
                section("보호자 정보") {
                    row("이름", reservation.userName)
                    row("전화번호", reservation.userPhone)
                    row("주소", reservation.userAddress)
                }
                section("예약 정보") {
                    row("가게", reservation.storeName)
                    row("서비스", reservation.reservationType)
                    row("시작", ReservationSchedule.startLabel(rawStart: reservation.startDate, service: reservation.reservationType))
                    row("종료", ReservationSchedule.endLabel(rawStart: reservation.startDate, rawEnd: reservation.endDate, service: reservation.reservationType))
                    row("요청사항", reservation.requestMessage)
                }
            }
            .padding(20)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .bold))
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title).foregroundStyle(Color.brandBrownMid).frame(width: 65, alignment: .leading)
            Text(OwnerReservationPresentation.value(value)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12)).textSelection(.enabled)
    }

    private var requestActions: some View {
        HStack(spacing: 12) {
            Button("예약 취소", role: .destructive) { showCancelConfirmation = true }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(.white).clipShape(Capsule())
            Button { Task { await confirm() } } label: {
                Group {
                    if state.isMutating { ProgressView().tint(.white) }
                    else { Text("확정하기") }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(.white).background(Color.brandOrange).clipShape(Capsule())
            }
        }
        .font(.system(size: 14, weight: .bold)).padding(20)
        .disabled(state.isMutating)
    }

    private func diaryContext(_ reservation: PendingReservation) -> DiaryContext {
        DiaryContext(reservationId: reservation.id, petName: reservation.petName ?? "우리 아이",
                     storeName: reservation.storeName ?? "가게", canWrite: true, petImageUrl: reservation.petImageUrl)
    }

    private func load() async {
        guard let uid = authSession.userId, let rid = router.ownerReservationContext?.reservationId else { return }
        await state.load(ownerId: uid, currentUserId: { authSession.userId }) {
            try await APIClient.shared.fetchOwnerReservationDetail(reservationId: rid)
        }
        guard !Task.isCancelled, authSession.userId == uid,
              router.current == .ownerReservationDetail,
              router.ownerReservationContext?.reservationId == rid,
              let reservation = state.reservation, reservation.id == rid else { return }
        router.focusOwnerReservationStartDate(reservation.startDate, expectedReservationId: rid)
        if reservation.status == "CONFIRMED" { router.ownerReservationTab = .confirmed }
        else if reservation.status == "REQUEST" { state.selectedTab = .information }
    }

    private func confirm() async {
        guard let uid = authSession.userId, let rid = state.reservation?.reservationId else { return }
        let confirmedStartDate = state.reservation?.startDate
        await state.confirm(ownerId: uid, currentUserId: { authSession.userId }, action: {
            try await APIClient.shared.confirmReservation(reservationId: rid)
        }, fetch: {
            try await APIClient.shared.fetchOwnerReservationDetail(reservationId: rid)
        })
        guard router.current == .ownerReservationDetail,
              router.ownerReservationContext?.reservationId == rid else { return }
        if state.didConfirm {
            router.ownerCalendarState.focus(startDate: confirmedStartDate)
            router.ownerReservationTab = .confirmed
            state.selectedTab = .information
        }
    }

    private func cancel() async {
        guard let uid = authSession.userId, let rid = state.reservation?.reservationId else { return }
        await state.cancel(ownerId: uid, currentUserId: { authSession.userId }) {
            try await APIClient.shared.cancelReservation(reservationId: rid, byOwner: true)
        }
        if state.didCancel, router.current == .ownerReservationDetail,
           router.ownerReservationContext?.reservationId == rid { router.back() }
    }
}
