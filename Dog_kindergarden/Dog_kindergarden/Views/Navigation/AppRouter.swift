import SwiftUI
import Observation

enum AppScreen {
    case start
    case home
    case cityMap
    case kakaoMap
    case dogProfile
    case chatList
    case chatRoom
    case storeDetail
    case booking
    case bookingDone
    case myPage
    case myStoreApplication
    case favorites
    case reservationList
    case ownerMode
    case ownerDiaryList
    case ownerReservationDetail
    case myDiaryList
    case diary
    case noticeList
    case noticeDetail
    case attributions
    case ownerApplications
    case supportConversationList
    case supportConversation
    case notificationInbox
}

// 알림장 화면 전달 컨텍스트 — 어느 예약의 알림장인지 + 작성 권한(사장님) 여부
struct DiaryContext {
    let reservationId: Int
    let petName: String
    let storeName: String
    let canWrite: Bool
    let petImageUrl: String?

    init(reservationId: Int, petName: String, storeName: String, canWrite: Bool, petImageUrl: String? = nil) {
        self.reservationId = reservationId
        self.petName = petName
        self.storeName = storeName
        self.canWrite = canWrite
        self.petImageUrl = petImageUrl
    }
}

enum UserRole {
    case user
    case owner
}

// 예약 성공 결과 — 완료화면 표시 + 이후 채팅방(room_id) 연결용
struct BookingResult {
    let reservationId: Int
    let roomId: Int
    let storeName: String
    let dogName: String
    let dogBreed: String
    let schedule: String
    let price: String
    let isAllDay: Bool
    let durationHours: Int
    let dogImageURL: String?

    init(reservationId: Int, roomId: Int, storeName: String, dogName: String, dogBreed: String,
         schedule: String, price: String, isAllDay: Bool, durationHours: Int, dogImageURL: String? = nil) {
        self.reservationId = reservationId
        self.roomId = roomId
        self.storeName = storeName
        self.dogName = dogName
        self.dogBreed = dogBreed
        self.schedule = schedule
        self.price = price
        self.isAllDay = isAllDay
        self.durationHours = durationHours
        self.dogImageURL = dogImageURL
    }
}

// 홈이 상세 화면으로 전환되어 재생성돼도 유지할 세션 단위 탐색 상태.
struct HomeMapState {
    var searchText = ""
    var activeFilters: Set<ReviewTag> = []
    var activeType: String? = nil
    var bounds: MapBounds? = nil
    var camera: MapCameraState? = nil
}

// 정수 줌 레벨 대신 높이를 저장해 핀치 확대의 중간 배율까지 복원한다.
struct MapCameraState: Equatable {
    let latitude: Double
    let longitude: Double
    let height: Double
    let rotation: Double
    let tilt: Double
}

@Observable
final class AppRouter {
    var homeMapState = HomeMapState()
    var stack: [AppScreen] = [.start]
    var selectedProvince: String = "서울"          // 첫 화면 서울 기준
    var selectedCity: String = "성남시"
    var selectedStore: String = "멍멍이 호텔"
    var selectedPin: MapPin? = nil                 // 핀 탭으로 선택된 실제 가게
    var selectedChat: String = "멍멍이 호텔"
    var selectedRoomId: Int? = nil                 // 현재 채팅방 room_id (nil이면 작성 모드)
    var chatRoomAsOwner: Bool = false              // 사장님 시점('받은 문의')으로 연 방인지 — 자동메시지 말풍선 방향 결정
    var chatRoomAvatar: String = "🐾"              // 채팅방 상단·상대 말풍선 프로필 — 가게면 🏠/🏨, 사장님이 보는 보호자면 img:dog_b/c (진입점마다 설정)
    var recentPins: [MapPin] = []                  // 최근 본 가게 — 계정별 UserDefaults 영속, 최대 6개
    private var activeUserId: Int? = nil           // recentPins 저장 키에 쓰는 현재 계정
    var lastBooking: BookingResult? = nil          // 방금 신청한 예약 (완료화면/채팅방 연결)
    var ownerCalendarState = OwnerReservationCalendarState()
    var ownerReservationTab: OwnerReservationTab = .requests
    var ownerReservationContext: OwnerReservationContext? = nil
    var diaryContext: DiaryContext? = nil          // 알림장 화면 진입 컨텍스트 (예약·작성 권한)
    var selectedNotice: Notice? = nil      // 공지사항 목록에서 탭한 항목 — 상세 화면에 전달
    var selectedSupportConversationId: Int? = nil
    var selectedSupportConversationTitle: String = "1:1 문의"

    // 프로필 미설정 시 사용할 사용자 강아지 아바타 (dog_c 고정)
    let userDogAvatar: String = "dog_c"

    var current: AppScreen { stack.last ?? .start }

    func go(_ screen: AppScreen) {
        if screen == .ownerDiaryList {
            openOwnerReservations(tab: .confirmed)
            return
        }
        stack.append(screen)
    }

    func openOwnerReservations(tab: OwnerReservationTab) {
        ownerReservationTab = tab
        ownerReservationContext = nil
        if let index = stack.firstIndex(of: .ownerMode) {
            stack = Array(stack.prefix(through: index))
        } else {
            stack.append(.ownerMode)
        }
    }

    func openOwnerReservation(id: Int, tab: OwnerReservationDetailTab = .information, focusOnStartDate: Bool = false) {
        let selectedTab: OwnerReservationTab = tab == .diary ? .confirmed : ownerReservationTab
        openOwnerReservations(tab: selectedTab)
        ownerReservationContext = OwnerReservationContext(reservationId: id, initialTab: tab, focusOnStartDate: focusOnStartDate)
        stack.append(.ownerReservationDetail)
    }

    // 알림으로 직접 연 상세의 첫 성공 응답에서만 적용한다. 실시간 재조회는 선택일을 바꾸지 않는다.
    func focusOwnerReservationStartDate(_ startDate: String?, expectedReservationId: Int) {
        guard current == .ownerReservationDetail,
              ownerReservationContext?.reservationId == expectedReservationId,
              ownerReservationContext?.focusOnStartDate == true else { return }
        ownerReservationContext?.focusOnStartDate = false
        ownerCalendarState.focus(startDate: startDate)
    }

    func back() {
        guard stack.count > 1 else { return }
        stack.removeLast()
    }

    // 스택을 통째로 교체 — 로그아웃처럼 이전 화면으로 되돌아가면 안 되는 경우에 사용
    // 계정 전환 시 이전 계정의 흔적(최근 본 가게·선택 상태)이 남지 않도록 세션 데이터도 함께 비운다
    func reset(to screen: AppScreen) {
        stack = [screen]
        homeMapState = HomeMapState()
        selectedPin = nil
        selectedRoomId = nil
        chatRoomAsOwner = false
        recentPins = []
        lastBooking = nil
        diaryContext = nil
        ownerReservationContext = nil
        ownerReservationTab = .requests
        ownerCalendarState = OwnerReservationCalendarState()
        selectedSupportConversationId = nil
        selectedSupportConversationTitle = "1:1 문의"
    }

    // MARK: - 최근 본 가게 (계정별 영속)

    // 로그인/로그아웃/세션 복원 시 호출 — 해당 계정의 최근 본 가게를 불러온다
    func setActiveUser(_ userId: Int?) {
        activeUserId = userId
        guard let userId,
              let data = UserDefaults.standard.data(forKey: "recent_pins_\(userId)"),
              let pins = try? JSONDecoder().decode([MapPin].self, from: data) else {
            recentPins = []
            return
        }
        recentPins = pins
    }

    // 최신순 앞에 추가, 같은 가게는 중복 제거, 최대 6개(오래된 것부터 삭제) 후 저장
    func addRecentPin(_ pin: MapPin) {
        recentPins.removeAll { $0.storeKey == pin.storeKey }
        recentPins.insert(pin, at: 0)
        if recentPins.count > 6 { recentPins.removeLast() }
        guard let activeUserId, let data = try? JSONEncoder().encode(recentPins) else { return }
        UserDefaults.standard.set(data, forKey: "recent_pins_\(activeUserId)")
    }

    func clearAccountData(userId: Int) {
        UserDefaults.standard.removeObject(forKey: "recent_pins_\(userId)")
        if activeUserId == userId { activeUserId = nil }
        reset(to: .start)
    }
}
