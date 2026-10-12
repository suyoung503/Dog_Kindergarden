import Foundation
import UserNotifications
import BackgroundTasks
import Observation

// 알림 피드 항목 — 서버 snake_case 그대로 (ChatService 패턴)
struct NotificationItemDTO: Decodable {
    let event_id: String?
    let type: String
    let title: String
    let body: String
    let room_id: Int?
    let reservation_id: Int?
    let conversation_id: Int?
    let application_id: Int?
    let as_owner: Bool?
    let store_type: String?
}

struct AppInboxItem: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let title: String
    let body: String
    let roomId: Int?
    let reservationId: Int?
    let conversationId: Int?
    let applicationId: Int?
    let asOwner: Bool
    let storeType: String?
    let receivedAt: Date
    var isRead: Bool

    var deepLink: NotificationDeepLink? {
        switch type {
        case "chat":
            guard let roomId else { return nil }
            return .chat(roomId: roomId, title: title, asOwner: asOwner, storeType: storeType)
        case "reservation_confirmed":
            return .reservationList
        case "reservation_request", "reservation_canceled":
            return .ownerMode
        case "support":
            guard let conversationId else { return nil }
            return .support(conversationId: conversationId, title: title)
        case "owner_application":
            return .ownerApplications
        default:
            return nil
        }
    }
}

// 알림 탭 딥링크 — RootView가 소비해 AppRouter로 이동
enum NotificationDeepLink: Equatable {
    case chat(roomId: Int, title: String, asOwner: Bool, storeType: String?)
    case reservationList
    case ownerMode
    case support(conversationId: Int, title: String)
    case ownerApplications
}

// 서버 이벤트 피드 폴링 → 로컬 알림 발행 (원격 푸시 불가 제약 우회 — 설계 문서 참고)
@Observable
@MainActor
final class AppNotificationService: NSObject {
    static let shared = AppNotificationService()

    var pendingDeepLink: NotificationDeepLink? = nil
    var activeRoomId: Int? = nil   // 열려 있는 채팅방 — 그 방의 chat 알림은 배너 생략
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var inboxItems: [AppInboxItem] = []
    private var userId: Int? = nil

    var unreadInboxCount: Int { inboxItems.lazy.filter { !$0.isRead }.count }

    func configure(userId: Int?) {
        guard self.userId != userId else { return }
        self.userId = userId
        loadInbox()
    }

    func clearAfterAccountDeletion(userId: Int) {
        if self.userId == userId { self.userId = nil }
        pendingDeepLink = nil
        activeRoomId = nil
        inboxItems = []
        UserDefaults.standard.removeObject(forKey: "notification_cursor_\(userId)")
        UserDefaults.standard.removeObject(forKey: inboxKey(userId: userId))
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorizationStatus()
        return granted
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
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
        var comps = URLComponents(
            url: APIEnvironment.apiBaseURL.appendingPathComponent("users/\(userId)/notifications"),
            resolvingAgainstBaseURL: false
        )!
        let cursorKey = "notification_cursor_\(userId)"
        if let cursor = UserDefaults.standard.string(forKey: cursorKey) {
            comps.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        }
        guard let url = comps.url,
              let (data, _) = try? await APITransport.data(for: APITransport.request(url: url)),
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
        appendToInbox(items)
        for item in items { publish(item) }
    }

    func markAllInboxRead() {
        guard inboxItems.contains(where: { !$0.isRead }) else { return }
        for index in inboxItems.indices { inboxItems[index].isRead = true }
        saveInbox()
    }

    func markInboxRead(id: String) {
        guard let index = inboxItems.firstIndex(where: { $0.id == id }),
              !inboxItems[index].isRead else { return }
        inboxItems[index].isRead = true
        saveInbox()
    }

    func clearInbox() {
        inboxItems = []
        guard let userId else { return }
        UserDefaults.standard.removeObject(forKey: inboxKey(userId: userId))
    }

    private func appendToInbox(_ items: [NotificationItemDTO]) {
        guard !items.isEmpty, userId != nil else { return }
        var knownIds = Set(inboxItems.map(\.id))
        let receivedAt = Date()
        var additions: [AppInboxItem] = []
        for item in items {
            let id = item.event_id ?? fallbackId(for: item)
            guard knownIds.insert(id).inserted else { continue }
            additions.append(AppInboxItem(
                id: id,
                type: item.type,
                title: item.title,
                body: item.body,
                roomId: item.room_id,
                reservationId: item.reservation_id,
                conversationId: item.conversation_id,
                applicationId: item.application_id,
                asOwner: item.as_owner ?? false,
                storeType: item.store_type,
                receivedAt: receivedAt,
                isRead: item.type == "chat" && item.room_id == activeRoomId
            ))
        }
        guard !additions.isEmpty else { return }
        inboxItems.insert(contentsOf: additions.reversed(), at: 0)
        if inboxItems.count > 100 { inboxItems = Array(inboxItems.prefix(100)) }
        saveInbox()
    }

    private func fallbackId(for item: NotificationItemDTO) -> String {
        [
            item.type,
            String(item.room_id ?? 0),
            String(item.reservation_id ?? 0),
            String(item.conversation_id ?? 0),
            String(item.application_id ?? 0),
            item.title,
            item.body,
        ].joined(separator: "|")
    }

    private func loadInbox() {
        guard let userId,
              let data = UserDefaults.standard.data(forKey: inboxKey(userId: userId)),
              let items = try? JSONDecoder().decode([AppInboxItem].self, from: data) else {
            inboxItems = []
            return
        }
        inboxItems = items
    }

    private func saveInbox() {
        guard let userId,
              let data = try? JSONEncoder().encode(inboxItems) else { return }
        UserDefaults.standard.set(data, forKey: inboxKey(userId: userId))
    }

    private func inboxKey(userId: Int) -> String { "notification_inbox_\(userId)" }

    private func publish(_ item: NotificationItemDTO) {
        if item.type == "chat", let roomId = item.room_id, roomId == activeRoomId { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.userInfo = [
            "type": item.type,
            "event_id": item.event_id ?? fallbackId(for: item),
            "room_id": item.room_id ?? 0,
            "reservation_id": item.reservation_id ?? 0,
            "conversation_id": item.conversation_id ?? 0,
            "application_id": item.application_id ?? 0,
            "as_owner": item.as_owner ?? false,
            "title": item.title,
            "store_type": item.store_type ?? "",
        ]
        // 매번 고유 identifier — 같은 방으로 여러 번 알림이 와도 알림 센터에 각각 쌓인다
        // (예전엔 방 기준 고정 id라 나중 알림이 이전 알림을 덮어써 히스토리가 사라졌음)
        let request = UNNotificationRequest(
            identifier: item.event_id ?? "\(item.type)-\(UUID().uuidString)",
            content: content,
            trigger: nil
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
            shared.restoreUserForBackgroundIfNeeded()
            await shared.pollOnce()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            poll.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private func restoreUserForBackgroundIfNeeded() {
        guard userId == nil,
              AuthTokenStore.load() != nil,
              let storedUserId = UserDefaults.standard.value(forKey: "auth_user_id") as? Int else { return }
        userId = storedUserId
        loadInbox()
    }
}

// 포그라운드 배너 표시 + 알림 탭 딥링크
extension AppNotificationService: UNUserNotificationCenterDelegate {
    // async 버전 델리게이트 메서드는 ObjC completion-handler 브리징 스텁이
    // 메인 스레드 콜백을 강제하는데 await로 스레드를 넘나들면 깨진다
    // (NSInternalInconsistencyException: Call must be made on main thread) —
    // 그래서 전통적인 completion-handler 형태를 쓴다.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let eventId = info["event_id"] as? String
        let type = info["type"] as? String ?? ""
        let roomId = info["room_id"] as? Int ?? 0
        let conversationId = info["conversation_id"] as? Int ?? 0
        let asOwner = info["as_owner"] as? Bool ?? false
        let title = info["title"] as? String ?? "채팅"
        let storeType = info["store_type"] as? String ?? ""

        let link: NotificationDeepLink?
        switch type {
        case "chat" where roomId > 0:
            link = .chat(roomId: roomId, title: title, asOwner: asOwner,
                         storeType: storeType.isEmpty ? nil : storeType)
        case "reservation_request", "reservation_canceled":
            link = .ownerMode
        case "support" where conversationId > 0:
            link = .support(conversationId: conversationId, title: title)
        case "owner_application":
            link = .ownerApplications
        default:
            link = nil
        }
        if let link {
            Task { @MainActor in
                if let eventId { AppNotificationService.shared.markInboxRead(id: eventId) }
                AppNotificationService.shared.pendingDeepLink = link
            }
        }
        completionHandler()
    }
}
