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
    let diary_id: Int?
    let pet_name: String?
    let store_name: String?
    let can_write: Bool?
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
    let diaryId: Int?
    let petName: String?
    let storeName: String?
    let canWrite: Bool?

    init(id: String, type: String, title: String, body: String, roomId: Int?, reservationId: Int?,
         conversationId: Int?, applicationId: Int?, asOwner: Bool, storeType: String?,
         receivedAt: Date, isRead: Bool, diaryId: Int? = nil, petName: String? = nil,
         storeName: String? = nil, canWrite: Bool? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.roomId = roomId
        self.reservationId = reservationId
        self.conversationId = conversationId
        self.applicationId = applicationId
        self.asOwner = asOwner
        self.storeType = storeType
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.diaryId = diaryId
        self.petName = petName
        self.storeName = storeName
        self.canWrite = canWrite
    }

    var deepLink: NotificationDeepLink? {
        NotificationDeepLink.resolve(type: type, roomId: roomId, conversationId: conversationId,
                                     title: title, asOwner: asOwner, storeType: storeType,
                                     reservationId: reservationId, diaryId: diaryId,
                                     petName: petName, storeName: storeName, canWrite: canWrite)
    }
}

// 알림 탭 딥링크 — RootView가 소비해 AppRouter로 이동
enum NotificationDeepLink: Equatable {
    case chat(roomId: Int, title: String, asOwner: Bool, storeType: String?)
    case diary(reservationId: Int, diaryId: Int?, petName: String, storeName: String, canWrite: Bool)
    case reservationList
    case ownerMode
    case support(conversationId: Int, title: String)
    case ownerApplications
    case myStoreApplication

    // 앱 내부 알림함과 시스템 알림 탭은 동일한 문맥 규칙을 사용한다.
    nonisolated static func resolve(type: String, roomId: Int?, conversationId: Int?, title: String,
                        asOwner: Bool, storeType: String?, reservationId: Int? = nil,
                        diaryId: Int? = nil, petName: String? = nil, storeName: String? = nil,
                        canWrite: Bool? = nil) -> NotificationDeepLink? {
        switch type {
        case "chat":
            guard let roomId, roomId > 0 else { return nil }
            return .chat(roomId: roomId, title: title, asOwner: asOwner, storeType: storeType)
        case "diary":
            guard let reservationId, reservationId > 0 else { return .reservationList }
            return .diary(reservationId: reservationId, diaryId: diaryId.flatMap { $0 > 0 ? $0 : nil },
                          petName: petName.flatMap { $0.isEmpty ? nil : $0 } ?? "우리 아이",
                          storeName: storeName.flatMap { $0.isEmpty ? nil : $0 } ?? "알림장",
                          canWrite: canWrite ?? false)
        case "reservation_confirmed", "reservation_submitted":
            return .reservationList
        case "reservation_request", "reservation_canceled":
            return asOwner ? .ownerMode : .reservationList
        case "support":
            guard let conversationId, conversationId > 0 else { return nil }
            return .support(conversationId: conversationId, title: title)
        case "owner_application_rejected":
            return .myStoreApplication
        case "owner_application":
            return .ownerApplications
        default:
            return nil
        }
    }
}

// 포그라운드 WebSocket invalidation → 영속 알림 피드 조회. APNs/백그라운드 수신은 별도 준비가 필요하다.
@Observable
@MainActor
final class AppNotificationService: NSObject {
    static let shared = AppNotificationService()

    var pendingDeepLink: NotificationDeepLink? = nil
    var activeRoomId: Int? = nil   // 열려 있는 채팅방 — 그 방의 chat 알림은 배너 생략
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var inboxItems: [AppInboxItem] = []
    private var userId: Int? = nil
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let notificationPublisher: ((NotificationItemDTO) -> Void)?
    @ObservationIgnored private var configuredToken: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var isForegroundActive = false
    @ObservationIgnored private var foregroundTask: Task<Void, Never>?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var catchupTask: Task<Void, Never>?
    @ObservationIgnored private var catchupID: UUID?
    @ObservationIgnored private var catchupRequested = false
    @ObservationIgnored private var seenChangeIds: [String] = []
    @ObservationIgnored private var seenNotificationIds: [String] = []
    @ObservationIgnored private var changeObservers: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(session: URLSession = .shared, notificationPublisher: ((NotificationItemDTO) -> Void)? = nil) {
        self.session = session
        self.notificationPublisher = notificationPublisher
        super.init()
    }

    var unreadInboxCount: Int { inboxItems.lazy.filter { !$0.isRead }.count }

    func configure(userId: Int?) {
        let token = AuthTokenStore.load()
        guard self.userId != userId || configuredToken != token else { return }
        stopConnection()
        generation = UUID()
        self.userId = userId
        configuredToken = token
        pendingDeepLink = nil
        activeRoomId = nil
        seenChangeIds = []
        loadInbox()
        startConnectionIfNeeded()
    }

    func setForegroundActive(_ active: Bool) {
        isForegroundActive = active
        if active { startConnectionIfNeeded() }
        else { stopConnection() }
    }

    // 각 화면은 한 작업에서 순서대로 소비한다. 느린 로드 중 변경도 마지막 한 건은 보존한다.
    func updates() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            changeObservers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let service = self else { return }
                Task { @MainActor in service.changeObservers.removeValue(forKey: id) }
            }
        }
    }

    private func notifyDataChanged() {
        for observer in changeObservers.values { observer.yield(()) }
    }

    private func stopConnection() {
        foregroundTask?.cancel()
        foregroundTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        catchupTask?.cancel()
        catchupTask = nil
        catchupID = nil
        catchupRequested = false
    }

    private func startConnectionIfNeeded() {
        guard isForegroundActive, foregroundTask == nil,
              let userId, let token = configuredToken, token == AuthTokenStore.load() else { return }
        let sessionGeneration = generation
        foregroundTask = Task { [weak self] in
            await self?.connectionLoop(userId: userId, token: token, generation: sessionGeneration)
        }
    }

    private func isCurrent(userId: Int, token: String, generation: UUID) -> Bool {
        self.userId == userId && self.generation == generation && configuredToken == token
            && AuthTokenStore.load() == token && isForegroundActive && !Task.isCancelled
    }

    private struct RealtimeEvent: Decodable {
        let type: String
        let event_id: String?
    }

    private func connectionLoop(userId: Int, token: String, generation: UUID) async {
        // 최초 cursor를 먼저 확보하고, 연결의 ready 이후 한 번 더 조회해 연결 전후 공백을 메운다.
        await pollOnce()
        var failures = 0
        while isCurrent(userId: userId, token: token, generation: generation) {
            var components = URLComponents(url: APIEnvironment.apiBaseURL.appendingPathComponent("realtime"), resolvingAgainstBaseURL: false)!
            components.scheme = components.scheme == "http" ? "ws" : "wss"
            guard let url = components.url else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let connection = session.webSocketTask(with: request)
            socket = connection
            connection.resume()
            var lastReceivedAt = Date()
            var lastCatchupAt = Date()
            let heartbeat = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                    guard let self, self.isCurrent(userId: userId, token: token, generation: generation) else { return }
                    // 반쯤 끊긴 연결도 receive를 영원히 기다리지 않고 재연결한다.
                    guard Date().timeIntervalSince(lastReceivedAt) < 60 else {
                        connection.cancel(with: .goingAway, reason: nil)
                        return
                    }
                    do { try await connection.send(.string("ping")) }
                    catch { connection.cancel(with: .goingAway, reason: nil); return }
                    if Date().timeIntervalSince(lastCatchupAt) >= 60 {
                        // 전송 실패로 누락된 알림도 복구하는 포그라운드 안전망.
                        await self.pollOnce()
                        guard self.isCurrent(userId: userId, token: token, generation: generation) else { return }
                        self.notifyDataChanged()
                        lastCatchupAt = Date()
                    }
                }
            }
            do {
                while isCurrent(userId: userId, token: token, generation: generation) {
                    let message = try await connection.receive()
                    guard isCurrent(userId: userId, token: token, generation: generation) else { break }
                    let data: Data
                    switch message {
                    case .string(let value): data = Data(value.utf8)
                    case .data(let value): data = value
                    @unknown default: continue
                    }
                    guard let event = try? JSONDecoder().decode(RealtimeEvent.self, from: data) else { continue }
                    lastReceivedAt = Date()
                    if event.type == "ready" {
                        failures = 0
                        await pollOnce()
                        guard isCurrent(userId: userId, token: token, generation: generation) else { break }
                        notifyDataChanged()   // 재연결·복귀는 현재 화면도 서버에서 다시 읽는다.
                    } else if event.type == "change", let id = event.event_id, !seenChangeIds.contains(id) {
                        seenChangeIds.append(id)
                        if seenChangeIds.count > 256 { seenChangeIds.removeFirst(seenChangeIds.count - 256) }
                        notifyDataChanged()
                        await pollOnce()   // 소켓 payload가 아닌 영속 피드가 알림의 source of truth.
                    }
                }
            } catch {
                if isCurrent(userId: userId, token: token, generation: generation), connection.closeCode.rawValue == 4401 {
                    APITransport.handleUnauthorized(401)
                }
            }
            heartbeat.cancel()
            connection.cancel(with: .goingAway, reason: nil)
            if socket === connection { socket = nil }
            guard isCurrent(userId: userId, token: token, generation: generation) else { return }
            failures = min(failures + 1, 6)
            // 최대 30초 지수 백오프 + jitter. 반복 실패 중에도 피드로 401/누락을 확인한다.
            let delay = min(pow(2, Double(failures - 1)), 30) + Double.random(in: 0...0.5)
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            await pollOnce()
            guard isCurrent(userId: userId, token: token, generation: generation) else { return }
            notifyDataChanged()   // WebSocket만 차단되어도 REST 복구 결과를 열린 화면에 반영한다.
        }
    }

    func clearAfterAccountDeletion(userId: Int) {
        if self.userId == userId { configure(userId: nil) }
        pendingDeepLink = nil
        activeRoomId = nil
        inboxItems = []
        UserDefaults.standard.removeObject(forKey: "notification_cursor_\(userId)")
        UserDefaults.standard.removeObject(forKey: inboxKey(userId: userId))
        UserDefaults.standard.removeObject(forKey: "notification_seen_\(userId)")
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

    // 동시 catchup은 직렬화하고, 진행 중 추가 요청은 현재 응답 뒤 다시 읽는다.
    func pollOnce() async {
        guard let userId, let token = configuredToken,
              isCurrent(userId: userId, token: token, generation: generation) else { return }
        if let catchupTask {
            catchupRequested = true
            await catchupTask.value
            return
        }
        let id = UUID()
        let sessionGeneration = generation
        catchupID = id
        let task = Task { @MainActor [weak self] in
            guard let self, self.isCurrent(userId: userId, token: token, generation: sessionGeneration) else { return }
            repeat {
                self.catchupRequested = false
                await self.fetchFeed(userId: userId, token: token, generation: sessionGeneration)
            } while self.catchupRequested && self.isCurrent(userId: userId, token: token, generation: sessionGeneration)
        }
        catchupTask = task
        await task.value
        if catchupID == id { catchupTask = nil; catchupID = nil }
    }

    private func fetchFeed(userId: Int, token: String, generation: UUID) async {
        var comps = URLComponents(
            url: APIEnvironment.apiBaseURL.appendingPathComponent("users/\(userId)/notifications"),
            resolvingAgainstBaseURL: false
        )!
        let cursorKey = "notification_cursor_\(userId)"
        if let cursor = UserDefaults.standard.string(forKey: cursorKey) {
            comps.queryItems = [URLQueryItem(name: "cursor", value: cursor)]
        } else {
            // 배너 억제를 지원하는 앱만 최근 이력을 복원한다(구버전 서버와도 호환).
            comps.queryItems = [URLQueryItem(name: "bootstrap", value: "1")]
        }
        guard let url = comps.url else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request),
              isCurrent(userId: userId, token: token, generation: generation),
              let http = response as? HTTPURLResponse else { return }
        // 이전 계정의 지연된 401이 새 계정의 토큰을 삭제하지 않게 위 검사 이후 처리한다.
        if http.statusCode == 401 { APITransport.handleUnauthorized(401); stopConnection(); return }
        guard (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = json["notifications"],
              let itemsData = try? JSONSerialization.data(withJSONObject: rawItems),
              let items = try? JSONDecoder().decode([NotificationItemDTO].self, from: itemsData),
              let cursorDict = json["cursor"] as? [String: Any],
              let cursorData = try? JSONSerialization.data(withJSONObject: cursorDict),
              let cursorString = String(data: cursorData, encoding: .utf8) else { return }
        let freshItems = appendToInbox(items)
        if json["is_bootstrap"] as? Bool != true {
            for item in freshItems { publish(item) }
        }
        // decode·계정 확인·inbox 저장이 끝난 뒤에만 opaque cursor를 전진시킨다.
        UserDefaults.standard.set(cursorString, forKey: cursorKey)
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

    private func appendToInbox(_ items: [NotificationItemDTO]) -> [NotificationItemDTO] {
        guard !items.isEmpty, userId != nil else { return [] }
        var knownIds = Set(seenNotificationIds)
        knownIds.formUnion(inboxItems.map(\.id))
        var freshItems: [NotificationItemDTO] = []
        let receivedAt = Date()
        var additions: [AppInboxItem] = []
        for item in items {
            let id = item.event_id ?? fallbackId(for: item)
            guard knownIds.insert(id).inserted else { continue }
            freshItems.append(item)
            seenNotificationIds.append(id)
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
                isRead: item.type == "chat" && item.room_id == activeRoomId,
                diaryId: item.diary_id,
                petName: item.pet_name,
                storeName: item.store_name,
                canWrite: item.can_write
            ))
        }
        guard !additions.isEmpty else { return [] }
        if seenNotificationIds.count > 512 { seenNotificationIds = Array(seenNotificationIds.suffix(512)) }
        inboxItems.insert(contentsOf: additions.reversed(), at: 0)
        if inboxItems.count > 100 { inboxItems = Array(inboxItems.prefix(100)) }
        saveInbox()
        return freshItems
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
        seenNotificationIds = userId.flatMap { UserDefaults.standard.stringArray(forKey: "notification_seen_\($0)") } ?? []
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
        UserDefaults.standard.set(seenNotificationIds, forKey: "notification_seen_\(userId)")
    }

    private func inboxKey(userId: Int) -> String { "notification_inbox_\(userId)" }

    private func publish(_ item: NotificationItemDTO) {
        if item.type == "chat", let roomId = item.room_id, roomId == activeRoomId { return }
        if let notificationPublisher { notificationPublisher(item); return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.userInfo = [
            "type": item.type,
            "event_id": item.event_id ?? fallbackId(for: item),
            "room_id": item.room_id ?? 0,
            "reservation_id": item.reservation_id ?? 0,
            "diary_id": item.diary_id ?? 0,
            "pet_name": item.pet_name ?? "",
            "store_name": item.store_name ?? "",
            "can_write": item.can_write ?? false,
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

    // 기존 AppDelegate/SceneDelegate 호출 호환만 유지한다. 백그라운드 polling을 재예약하지 않는다.
    // 앱 밖의 즉시 알림은 Developer Program/APNs 설정 이후 별도로 구현·검증한다.
    nonisolated static let backgroundTaskId = "net.suyoung.Dog-kindergarden.refresh"

    nonisolated static func scheduleBackgroundRefresh() {}

    nonisolated static func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        task.setTaskCompleted(success: true)
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

        let link = NotificationDeepLink.resolve(
            type: type, roomId: roomId, conversationId: conversationId,
            title: title, asOwner: asOwner, storeType: storeType.isEmpty ? nil : storeType,
            reservationId: info["reservation_id"] as? Int, diaryId: info["diary_id"] as? Int,
            petName: info["pet_name"] as? String, storeName: info["store_name"] as? String,
            canWrite: info["can_write"] as? Bool
        )
        if let link {
            Task { @MainActor in
                if let eventId { AppNotificationService.shared.markInboxRead(id: eventId) }
                AppNotificationService.shared.pendingDeepLink = link
            }
        }
        completionHandler()
    }
}
