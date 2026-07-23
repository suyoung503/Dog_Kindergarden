import SwiftUI
import UserNotifications

struct RootView: View {
    @State private var router = AppRouter()
    @State private var boarding = BoardingStore()
    @State private var tagStore = TagStore()
    @State private var userProfile = UserProfile()
    @State private var authSession = AuthSession()
    @State private var notificationService = AppNotificationService.shared

    var body: some View {
        currentScreen
            .environment(router)
            .environment(boarding)
            .environment(tagStore)
            .environment(userProfile)
            .environment(authSession)
            .environment(notificationService)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: router.current)
            .task {
                await boarding.loadIfNeeded()
                await tagStore.load()
            }
            // 로그인/로그아웃/콜드 런치 세션 복원 시 계정별 상태 복원 + 알림 폴링 시작
            .task(id: authSession.userId) {
                router.setActiveUser(authSession.userId)
                notificationService.configure(userId: authSession.userId)
                // 계정 전환 시 이전 계정 알림 잔존 방지
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                guard authSession.userId != nil else { return }
                await notificationService.requestPermission()
                await notificationService.pollLoop()   // 로그아웃/계정 전환 시 task 취소로 종료
            }
            // 알림 탭 딥링크 — 로그인 상태면 즉시, 콜드 스타트면 세션 복원 후 소비
            // (주의: iOS 16 타깃 — onChange 클로저는 단일 파라미터(새 값) 형태만 사용 가능)
            .onChange(of: notificationService.pendingDeepLink) { link in
                if let link, authSession.userId != nil { consumeDeepLink(link) }
            }
            .onChange(of: authSession.userId) { uid in
                if let link = notificationService.pendingDeepLink, uid != nil { consumeDeepLink(link) }
            }
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
                : ((storeType == "호텔") ? "🏨" : "🏠")
            router.go(.chatRoom)
        case .reservationList:
            router.go(.reservationList)
        case .ownerMode:
            router.go(.ownerMode)
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
        case .chatRoom:    ChatRoomView()
        case .storeDetail: StoreDetailView()
        case .booking:     BookingView()
        case .bookingDone: BookingDoneView()
        case .myPage:      MyPageView()
        case .favorites:   FavoritesView()
        case .reservationList: ReservationListView()
        case .ownerMode:   OwnerModeView()
        case .ownerDiaryList: OwnerDiaryListView()
        case .diary:       DiaryTimelineView()
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
