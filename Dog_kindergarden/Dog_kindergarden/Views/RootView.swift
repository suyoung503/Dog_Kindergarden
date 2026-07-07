import SwiftUI

struct RootView: View {
    @State private var router = AppRouter()
    @State private var boarding = BoardingStore()
    @State private var tagStore = TagStore()
    @State private var userProfile = UserProfile()
    @State private var authSession = AuthSession()

    var body: some View {
        currentScreen
            .environment(router)
            .environment(boarding)
            .environment(tagStore)
            .environment(userProfile)
            .environment(authSession)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: router.current)
            .task {
                await boarding.loadIfNeeded()
                await tagStore.load()
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
