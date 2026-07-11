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
    case favorites
    case reservationList
    case ownerMode
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
}

@Observable
final class AppRouter {
    var stack: [AppScreen] = [.start]
    var selectedProvince: String = "서울"          // 첫 화면 서울 기준
    var selectedCity: String = "성남시"
    var selectedStore: String = "멍멍이 호텔"
    var selectedPin: MapPin? = nil                 // 핀 탭으로 선택된 실제 가게
    var selectedChat: String = "멍멍이 호텔"
    var selectedRoomId: Int? = nil                 // 현재 채팅방 room_id (nil이면 작성 모드)
    var recentPins: [MapPin] = []                  // 최근 본 가게 (뷰 이동 후에도 유지)
    var lastBooking: BookingResult? = nil          // 방금 신청한 예약 (완료화면/채팅방 연결)

    // 프로필 미설정 시 사용할 사용자 강아지 아바타 (dog_c 고정)
    let userDogAvatar: String = "dog_c"

    var current: AppScreen { stack.last ?? .start }

    func go(_ screen: AppScreen) {
        stack.append(screen)
    }

    func back() {
        guard stack.count > 1 else { return }
        stack.removeLast()
    }

    // 스택을 통째로 교체 — 로그아웃처럼 이전 화면으로 되돌아가면 안 되는 경우에 사용
    // 계정 전환 시 이전 계정의 흔적(최근 본 가게·선택 상태)이 남지 않도록 세션 데이터도 함께 비운다
    func reset(to screen: AppScreen) {
        stack = [screen]
        selectedPin = nil
        selectedRoomId = nil
        recentPins = []
        lastBooking = nil
    }
}
