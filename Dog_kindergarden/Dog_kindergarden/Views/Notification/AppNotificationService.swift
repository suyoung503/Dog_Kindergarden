import Foundation
import UserNotifications
import BackgroundTasks
import Observation

// 알림 피드 항목 — 서버 snake_case 그대로 (ChatService 패턴)
struct NotificationItemDTO: Decodable {
    let type: String
    let title: String
    let body: String
    let room_id: Int?
    let reservation_id: Int?
    let as_owner: Bool?
    let store_type: String?
}

// 알림 탭 딥링크 — RootView가 소비해 AppRouter로 이동
enum NotificationDeepLink: Equatable {
    case chat(roomId: Int, title: String, asOwner: Bool, storeType: String?)
    case reservationList
    case ownerMode
}

// 서버 이벤트 피드 폴링 → 로컬 알림 발행 (원격 푸시 불가 제약 우회 — 설계 문서 참고)
@Observable
@MainActor
final class AppNotificationService: NSObject {
    static let shared = AppNotificationService()

    var pendingDeepLink: NotificationDeepLink? = nil
    var activeRoomId: Int? = nil   // 열려 있는 채팅방 — 그 방의 chat 알림은 배너 생략
    private var userId: Int? = nil

    func configure(userId: Int?) {
        self.userId = userId
    }

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    // 포그라운드 폴링 루프 — 앱이 백그라운드로 가면 프로세스 서스펜드로 자연히 멈춘다
    func pollLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
    }

    func pollOnce() async {
        guard let userId else { return }
        var comps = URLComponents(string: "\(apiBaseURL)/api/users/\(userId)/notifications")!
        let cursorKey = "notification_cursor_\(userId)"
        if let cursor = UserDefaults.standard.string(forKey: cursorKey) {
            comps.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // 커서는 해석하지 않고 문자열 그대로 저장(opaque) — 다음 요청에 그대로 되돌려준다
        if let cursorDict = json["cursor"],
           let cursorData = try? JSONSerialization.data(withJSONObject: cursorDict),
           let cursorString = String(data: cursorData, encoding: .utf8) {
            UserDefaults.standard.set(cursorString, forKey: cursorKey)
        }

        guard let rawItems = json["notifications"],
              let itemsData = try? JSONSerialization.data(withJSONObject: rawItems),
              let items = try? JSONDecoder().decode([NotificationItemDTO].self, from: itemsData) else { return }
        for item in items { publish(item) }
    }

    private func publish(_ item: NotificationItemDTO) {
        if item.type == "chat", let roomId = item.room_id, roomId == activeRoomId { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.userInfo = [
            "type": item.type,
            "room_id": item.room_id ?? 0,
            "reservation_id": item.reservation_id ?? 0,
            "as_owner": item.as_owner ?? false,
            "title": item.title,
            "store_type": item.store_type ?? "",
        ]
        // identifier를 이벤트 대상 기준으로 고정 — 같은 방 재알림은 교체되어 알림 센터에 방당 1개 유지
        let idSeed = item.room_id ?? item.reservation_id ?? 0
        let request = UNNotificationRequest(
            identifier: "\(item.type)-\(idSeed)", content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 백그라운드 갱신 (BGAppRefreshTask — 실행 시점은 iOS 재량, 보장 없음)

    static let backgroundTaskId = "net.suyoung.Dog-kindergarden.refresh"

    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated static func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()   // 다음 실행 재예약
        let poll = Task { @MainActor in
            await shared.pollOnce()   // 콜드 BG 런치로 userId 미설정이면 no-op (한계 수용)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            poll.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

// 포그라운드 배너 표시 + 알림 탭 딥링크
extension AppNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String ?? ""
        let roomId = info["room_id"] as? Int ?? 0
        let asOwner = info["as_owner"] as? Bool ?? false
        let title = info["title"] as? String ?? "채팅"
        let storeType = info["store_type"] as? String ?? ""

        let link: NotificationDeepLink?
        switch type {
        case "chat" where roomId > 0:
            link = .chat(roomId: roomId, title: title, asOwner: asOwner,
                         storeType: storeType.isEmpty ? nil : storeType)
        case "reservation_confirmed":
            link = .reservationList
        case "reservation_request", "reservation_canceled":
            link = .ownerMode
        default:
            link = nil
        }
        guard let link else { return }
        await MainActor.run { AppNotificationService.shared.pendingDeepLink = link }
    }
}
