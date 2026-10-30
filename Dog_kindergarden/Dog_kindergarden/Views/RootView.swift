import SwiftUI
import UIKit
import UserNotifications

struct RootView: View {
    @State private var router = AppRouter()
    @State private var boarding = BoardingStore()
    @State private var tagStore = TagStore()
    @State private var userProfile = UserProfile()
    @State private var authSession = AuthSession()
    @State private var notificationService = AppNotificationService.shared
    @State private var storeShareInbox = StoreShareInbox.shared
    @State private var didLoadSharedStores = false
    @State private var storeShareError: String?

    private var storeShareTaskID: String {
        "\(authSession.userId ?? 0)|\(storeShareInbox.pending?.id.uuidString ?? "")|\(didLoadSharedStores)"
    }

    var body: some View {
        currentScreen
            .environment(router)
            .environment(boarding)
            .environment(tagStore)
            .environment(userProfile)
            .environment(authSession)
            .environment(notificationService)
            // .container만 무시(노치·상태바·홈 인디케이터 edge-to-edge 유지) — .keyboard는 무시하지 않아
            // 전 화면에서 텍스트 입력 시 SwiftUI 기본 키보드 세이프에어리어 회피가 정상 동작한다
            .ignoresSafeArea(.container)
            .animation(.easeInOut(duration: 0.2), value: router.current)
            .task {
                await boarding.loadIfNeeded()
                didLoadSharedStores = true
                await tagStore.load()
            }
            .task(id: storeShareTaskID) {
                await openPendingStoreShare()
            }
            .alert("가게를 열 수 없어요", isPresented: Binding(
                get: { storeShareError != nil },
                set: { if !$0 { storeShareError = nil } }
            )) {
                Button("확인", role: .cancel) { storeShareError = nil }
            } message: {
                Text(storeShareError ?? "잠시 후 링크를 다시 열어주세요.")
            }
            // 로그인/로그아웃/콜드 런치 세션 복원 시 계정별 상태 복원 + 알림 폴링 시작
            .task(id: authSession.userId) {
                router.setActiveUser(authSession.userId)
                notificationService.configure(userId: authSession.userId)
                notificationService.setForegroundActive(UIApplication.shared.applicationState == .active)
                // 계정 전환 시 이전 계정 알림 잔존 방지
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                guard authSession.userId != nil else { return }
                await authSession.refreshProfile(profile: userProfile)
                await notificationService.refreshAuthorizationStatus()
            }
            // 알림 탭 딥링크 — 로그인 상태면 즉시, 콜드 스타트면 세션 복원 후 소비
            .onChange(of: notificationService.pendingDeepLink) { _, link in
                if let link, authSession.userId != nil { consumeDeepLink(link) }
            }
            .onChange(of: authSession.userId) { _, uid in
                if uid == nil {
                    router.reset(to: .start)
                    return
                }
                if let link = notificationService.pendingDeepLink, uid != nil { consumeDeepLink(link) }
            }
    }

    private func openPendingStoreShare() async {
        // 초기 공개 목록 로드와 경쟁하지 않고, 로그인 전에는 링크를 소비하지 않는다.
        guard didLoadSharedStores, let uid = authSession.userId,
              let request = storeShareInbox.pending else { return }
        await boarding.loadIfNeeded()
        guard !Task.isCancelled, authSession.userId == uid,
              storeShareInbox.pending == request else { return }
        storeShareInbox.consume(request)
        guard boarding.isLoaded else {
            storeShareError = "가게 목록을 불러오지 못했어요. 인터넷 연결을 확인한 뒤 공유 링크를 다시 열어주세요."
            return
        }
        guard let pin = boarding.pins.first(where: { $0.storeKey == request.storeKey }) else {
            storeShareError = "공유된 가게를 찾을 수 없어요. 삭제되었거나 더 이상 공개되지 않는 가게일 수 있어요."
            return
        }
        router.selectedPin = pin
        router.selectedStore = pin.name
        router.addRecentPin(pin)
        if router.current == .start { router.go(.home) }
        if router.current != .storeDetail { router.go(.storeDetail) }
    }

    private func consumeDeepLink(_ link: NotificationDeepLink) {
        notificationService.pendingDeepLink = nil
        switch link {
        case .chat(let roomId, let title, let asOwner, let storeType):
            // 채팅 목록의 방 진입 패턴과 동일하게 라우터 세팅 (chatRoomAsOwner 필수)
            router.selectedChat = title
            router.selectedRoomId = roomId
            router.chatRoomAsOwner = asOwner
            router.chatRoomAvatar = asOwner
                ? "img:\(dogAvatarName(roomId))"
                : storeTypeEmoji(storeType)
            router.go(.chatRoom)
        case .diary(let reservationId, _, let petName, let storeName, let canWrite):
            if canWrite {
                router.openOwnerReservation(id: reservationId, tab: .diary, focusOnStartDate: true)
            } else {
                router.diaryContext = DiaryContext(reservationId: reservationId, petName: petName,
                                                   storeName: storeName, canWrite: false,
                                                   petImageUrl: "/api/reservations/\(reservationId)/pet-photo")
                router.go(.diary)
            }
        case .reservationList:
            router.go(.reservationList)
        case .ownerMode:
            router.openOwnerReservations(tab: .requests)
        case .support(let conversationId, let title):
            router.selectedSupportConversationId = conversationId
            router.selectedSupportConversationTitle = title
            router.go(.supportConversation)
        case .myStoreApplication:
            router.go(.myStoreApplication)
        case .ownerApplications:
            router.go(.ownerApplications)
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch router.current {
        case .start:       StartView()
        case .home:        HomeView()
        case .cityMap:     CityMapPlaceholderView()
        case .kakaoMap:    KakaoMapView()
        case .dogProfile:  DogProfileView()
        case .chatList:    ChatListView()
        case .chatRoom:    ChatRoomView().id(router.selectedRoomId)
        case .storeDetail: StoreDetailView()
        case .booking:     BookingView()
        case .bookingDone: BookingDoneView()
        case .myPage:      MyPageView()
        case .myStoreApplication: MyPageView(openStoreApplicationOnAppear: true)
        case .favorites:   FavoritesView()
        case .reservationList: ReservationListView()
        case .ownerMode:   OwnerModeView()
        case .ownerDiaryList: OwnerDiaryListView()
        case .ownerReservationDetail: OwnerReservationDetailView().id(router.ownerReservationContext?.reservationId)
        case .myDiaryList: MyDiaryListView()
        case .diary:       DiaryTimelineView().id(router.diaryContext?.reservationId)
        case .noticeList:  NoticeListView()
        case .noticeDetail: NoticeDetailView()
        case .attributions: AttributionView()
        case .ownerApplications: OwnerApplicationAdminView()
        case .supportConversationList: SupportConversationListView()
        case .supportConversation: SupportConversationView()
        case .notificationInbox: NotificationInboxView()
        }
    }
}

private struct CityMapPlaceholderView: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        VStack(spacing: 16) {
            Button(action: router.back) {
                Image(systemName: "chevron.left")
            }
            Text("도시 선택 화면").font(.title2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandCream)
    }
}
