import Foundation
import UIKit
import Testing
@testable import Dog_kindergarden

extension AuthStateTests {
@Suite("Foreground notification catchup", .serialized)
@MainActor
struct RealtimeNotificationTests {
    @Test("Repeated feed delivery keeps one inbox item and its read state")
    func duplicateFeed() async throws {
        let fixture = NotificationFixture { _, complete in
            complete(200, Self.feed(cursor: 9, item: true))
        }
        defer { fixture.close() }
        fixture.service.activeRoomId = 7
        fixture.service.setForegroundActive(true)
        await fixture.service.pollOnce()
        await fixture.service.pollOnce()
        #expect(fixture.service.inboxItems.map(\.id) == ["chat:test-event"])
        #expect(fixture.service.inboxItems.first?.isRead == true)
        #expect(fixture.service.unreadInboxCount == 0)
        let cursor = try #require(UserDefaults.standard.string(forKey: fixture.cursorKey))
        let json = try JSONSerialization.jsonObject(with: Data(cursor.utf8)) as? [String: Int]
        #expect(json?["message_id"] == 9)
    }

    @Test("Bootstrap restores inbox silently and the next live feed publishes a banner")
    func bootstrapThenLiveFeed() async throws {
        let published = PublishedNotificationIDs()
        let fixture = NotificationFixture(publisher: { published.ids.append($0.event_id ?? "") }) { request, complete in
            let hasCursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .contains(where: { $0.name == "cursor" }) == true
            if hasCursor {
                complete(200, Data(#"{"notifications":[{"event_id":"chat:live","type":"reservation_submitted","title":"맡겨멍","body":"새 예약","reservation_id":8}],"cursor":{"message_id":10},"is_bootstrap":false}"#.utf8))
            } else {
                complete(200, Data(#"{"notifications":[{"event_id":"chat:bootstrap","type":"reservation_submitted","title":"맡겨멍","body":"복원 예약","reservation_id":7}],"cursor":{"message_id":9},"is_bootstrap":true}"#.utf8))
            }
        }
        defer { fixture.close() }
        UserDefaults.standard.removeObject(forKey: fixture.cursorKey)
        fixture.service.setForegroundActive(true)
        await fixture.service.pollOnce()
        #expect(fixture.service.inboxItems.contains(where: { $0.id == "chat:bootstrap" }))
        #expect(!published.ids.contains("chat:bootstrap"), "복원한 과거 이력은 OS 배너를 쏟지 않는다")
        await fixture.service.pollOnce()
        #expect(fixture.service.inboxItems.first?.id == "chat:live")
        #expect(published.ids == ["chat:live"], "최초 cursor 뒤의 실시간 이벤트는 배너를 발행한다")
        await fixture.service.pollOnce()
        #expect(fixture.service.inboxItems.count == 2)
        #expect(published.ids == ["chat:live"], "중복 증분은 inbox·배너를 늘리지 않는다")
    }

    @Test("UIKit scene callbacks start catchup and stop it on resign or background")
    func uiKitLifecycleStartsAndStopsCatchup() async throws {
        let requests = NotificationRequestCounter()
        let fixture = NotificationFixture(publisher: { _ in }) { _, complete in
            requests.record()
            complete(200, Self.feed(cursor: 9, item: true))
        }
        defer { fixture.close() }
        let scene = try #require(UIApplication.shared.connectedScenes.first, "A signed simulator app scene is required")
        let delegate = SceneDelegate()
        delegate.notificationService = fixture.service
        await fixture.service.pollOnce()
        #expect(requests.count == 0, "비활성 상태에는 조회하지 않는다")
        delegate.sceneDidBecomeActive(scene)
        await fixture.service.pollOnce()
        #expect(requests.count > 0)
        #expect(fixture.service.inboxItems.map(\.id) == ["chat:test-event"])
        delegate.sceneWillResignActive(scene)
        let pausedCount = requests.count
        await fixture.service.pollOnce()
        #expect(requests.count == pausedCount, "UIKit resign 신호로 연결과 조회가 중지된다")
        delegate.sceneDidBecomeActive(scene)
        await fixture.service.pollOnce()
        #expect(requests.count > pausedCount, "복귀 시 저장한 cursor부터 다시 조회한다")
        delegate.sceneDidEnterBackground(scene)
        let backgroundCount = requests.count
        await fixture.service.pollOnce()
        #expect(requests.count == backgroundCount, "백그라운드 수신/APNs가 구현된 것처럼 조회하지 않는다")
        #expect(fixture.service.inboxItems.count == 1, "복귀 중복 피드는 같은 inbox를 다시 쌓지 않는다")
    }

    @Test("Chat inbox is independent of OS permission and only the actively viewed room suppresses its banner")
    func chatBannerPolicy() async throws {
        let published = PublishedNotificationIDs()
        let fixture = NotificationFixture(publisher: { published.ids.append($0.event_id ?? "") }) { _, complete in
            complete(200, Data(#"{"notifications":[{"event_id":"chat:open-room","type":"chat","title":"열린 유치원","body":"새 채팅이 도착했어요. 열람 중","room_id":7,"as_owner":false},{"event_id":"chat:other-room","type":"chat","title":"다른 유치원","body":"새 채팅이 도착했어요. 다른 방","room_id":8,"as_owner":false}],"cursor":{"message_id":11}}"#.utf8))
        }
        defer { fixture.close() }
        fixture.service.authorizationStatus = .denied
        fixture.service.activeRoomId = 7
        fixture.service.setForegroundActive(true)
        await fixture.service.pollOnce()
        #expect(fixture.service.inboxItems.count == 2, "OS 권한과 무관하게 두 방의 inbox는 보존한다")
        #expect(fixture.service.inboxItems.first(where: { $0.roomId == 7 })?.isRead == true)
        #expect(fixture.service.inboxItems.first(where: { $0.roomId == 8 })?.isRead == false)
        #expect(fixture.service.unreadInboxCount == 1)
        #expect(published.ids == ["chat:other-room"], "열린 방만 배너 생략; 다른 방은 발행 시도")
        let other = try #require(fixture.service.inboxItems.first(where: { $0.roomId == 8 }))
        #expect(other.deepLink == .chat(roomId: 8, title: "다른 유치원", asOwner: false, storeType: nil))
        await fixture.service.pollOnce()
        #expect(published.ids == ["chat:other-room"], "같은 피드 재조회는 중복 배너를 만들지 않는다")
    }

    @Test("An old account response cannot populate or invalidate the new session", arguments: [200, 401])
    func oldAccountResponse(status: Int) async throws {
        let pending = DeferredNotificationResponse()
        let fixture = NotificationFixture { request, complete in
            if request.value(forHTTPHeaderField: "Authorization")?.contains("replacement-session") == true {
                complete(200, Self.feed(cursor: 22, item: false))
            } else {
                pending.store(complete)
            }
        }
        defer { fixture.close() }
        fixture.service.setForegroundActive(true)
        let oldPoll = Task { await fixture.service.pollOnce() }
        for _ in 0..<200 {
            if pending.isReady { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(pending.isReady)
        // 응답을 큐에 넣은 뒤 MainActor가 다시 실행되기 전에 계정을 전환한다.
        pending.finish(status: status, data: Self.feed(cursor: 99, item: true))
        let replacementToken = "replacement-session-\(UUID().uuidString)"
        AuthTokenStore.save(replacementToken)
        fixture.service.configure(userId: fixture.otherUserID)
        await oldPoll.value
        await fixture.service.pollOnce()
        #expect(AuthTokenStore.load() == replacementToken)
        #expect(fixture.service.inboxItems.isEmpty)
        #expect(UserDefaults.standard.string(forKey: fixture.cursorKey) == fixture.initialCursor)
        let otherCursor = try #require(UserDefaults.standard.string(forKey: "notification_cursor_\(fixture.otherUserID)"))
        let json = try JSONSerialization.jsonObject(with: Data(otherCursor.utf8)) as? [String: Int]
        #expect(json?["message_id"] == 22)
    }

    @Test("Malformed feed items do not advance the opaque cursor")
    func malformedFeed() async {
        let fixture = NotificationFixture { _, complete in
            complete(200, Data(#"{"notifications":[{"event_id":"broken","type":"chat","title":7,"body":"invalid"}],"cursor":{"message_id":99}}"#.utf8))
        }
        defer { fixture.close() }
        fixture.service.setForegroundActive(true)
        await fixture.service.pollOnce()
        #expect(fixture.service.inboxItems.isEmpty)
        #expect(UserDefaults.standard.string(forKey: fixture.cursorKey) == fixture.initialCursor)
    }

    @Test("REST catchup refreshes open screens when WebSocket is unavailable")
    func unavailableSocketRefreshesScreens() async throws {
        let fixture = NotificationFixture { _, complete in
            complete(200, Self.feed(cursor: 9, item: true))
        }
        defer { fixture.close() }
        let updates = fixture.service.updates()
        var receivedUpdate = false
        let observer = Task { @MainActor in
            for await _ in updates {
                receivedUpdate = true
                break
            }
        }
        defer { observer.cancel() }
        // 이 fixture의 WebSocket 주소는 연결을 거부하는 localhost:1이다.
        fixture.service.setForegroundActive(true)
        for _ in 0..<300 {
            if receivedUpdate { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(receivedUpdate)
        #expect(fixture.service.inboxItems.map(\.id) == ["chat:test-event"])
    }

    nonisolated private static func feed(cursor: Int, item: Bool) -> Data {
        let notifications = item ? #"[{"event_id":"chat:test-event","type":"chat","title":"채팅","body":"내용","room_id":7}]"# : "[]"
        return Data("{\"notifications\":\(notifications),\"cursor\":{\"message_id\":\(cursor)}}".utf8)
    }
}

}

@MainActor
private final class NotificationFixture {
    let userID = Int.random(in: 900_000_000...950_000_000)
    var otherUserID: Int { userID + 1 }
    var cursorKey: String { "notification_cursor_\(userID)" }
    let initialCursor = #"{"message_id":1}"#
    let service: AppNotificationService
    private let session: URLSession
    private let savedToken = AuthTokenStore.load()
    private let savedBaseURL = UserDefaults.standard.string(forKey: "API_BASE_URL")

    init(publisher: ((NotificationItemDTO) -> Void)? = nil, handler: @escaping NotificationProtocol.Handler) {
        // 프로토콜은 이 session에만 설치한다. WebSocket도 운영 서버로 향하지 않게 한다.
        UserDefaults.standard.set("http://127.0.0.1:1/api", forKey: "API_BASE_URL")
        let fixtureToken = "fixture-session-\(UUID().uuidString)"
        AuthTokenStore.save(fixtureToken)
        #expect(AuthTokenStore.load() == fixtureToken, "Keychain tests require a signed simulator test host")
        NotificationProtocol.setHandler(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NotificationProtocol.self]
        session = URLSession(configuration: config)
        service = AppNotificationService(session: session, notificationPublisher: publisher)
        UserDefaults.standard.set(initialCursor, forKey: cursorKey)
        service.configure(userId: userID)
    }

    func close() {
        service.setForegroundActive(false)
        service.configure(userId: nil)
        session.invalidateAndCancel()
        NotificationProtocol.setHandler(nil)
        for user in [userID, otherUserID] {
            for prefix in ["notification_cursor_", "notification_inbox_", "notification_seen_"] {
                UserDefaults.standard.removeObject(forKey: "\(prefix)\(user)")
            }
        }
        if let savedToken { AuthTokenStore.save(savedToken) } else { AuthTokenStore.clear() }
        if let savedBaseURL { UserDefaults.standard.set(savedBaseURL, forKey: "API_BASE_URL") }
        else { UserDefaults.standard.removeObject(forKey: "API_BASE_URL") }
    }
}

private final class DeferredNotificationResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var complete: ((Int, Data) -> Void)?
    var isReady: Bool { lock.lock(); defer { lock.unlock() }; return complete != nil }
    func store(_ complete: @escaping (Int, Data) -> Void) { lock.lock(); self.complete = complete; lock.unlock() }
    func finish(status: Int, data: Data) {
        lock.lock(); let response = complete; complete = nil; lock.unlock()
        response?(status, data)
    }
}

private final class NotificationProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest, @escaping (Int, Data) -> Void) -> Void
    private static let handlerLock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    private let stateLock = NSLock()
    private var stopped = false

    static func setHandler(_ value: Handler?) { handlerLock.lock(); handler = value; handlerLock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.lastPathComponent == "notifications" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.handlerLock.lock(); let handler = Self.handler; Self.handlerLock.unlock()
        handler?(request) { [weak self] status, data in
            guard let self else { return }
            self.stateLock.lock(); let stopped = self.stopped; self.stateLock.unlock()
            guard !stopped, let url = self.request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}

@MainActor
private final class PublishedNotificationIDs {
    var ids: [String] = []
}

private final class NotificationRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func record() { lock.lock(); value += 1; lock.unlock() }
}
