import Foundation
import Testing
@testable import Dog_kindergarden

// Keychain과 standard defaults를 쓰는 기존 프로필 테스트와 같은 직렬 suite다.
extension AuthStateTests.ProfileEmailTests {
    @Test("Delayed transport 401 cannot invalidate a replacement token or API server", arguments: ["transport", "update", "delete"])
    func staleTransportUnauthorized(route: String) async throws {
        for change in ["token", "server"] {
            let pending = DeferredAuthResponse()
            let fixture = AuthTransportFixture { request, complete in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer transport-fixture-old")
                #expect(request.url?.host == "127.0.0.1")
                pending.store(complete)
            }
            defer { fixture.close() }
            await Task.yield()
            let operation = Task { await fixture.send(route: route) }
            try await pending.waitUntilReady()
            if change == "token" {
                // 같은 숫자 userId로 재로그인해도 이전 token의 401은 오래된 응답이다.
                AuthTokenStore.save("transport-fixture-replacement")
            } else {
                UserDefaults.standard.set("http://127.0.0.1:2/api", forKey: "API_BASE_URL")
            }
            let expectedToken = AuthTokenStore.load()
            pending.finish(status: 401)
            await operation.value
            await fixture.drainInvalidations()
            #expect(AuthTokenStore.load() == expectedToken, "Old \(route) 401 must preserve \(change)")
            #expect(fixture.auth.userId == 920001)
            #expect(fixture.auth.errorMessage == nil)
        }
    }

    @Test("Current transport 401 clears credentials and observable login state", arguments: ["transport", "update", "delete"])
    func currentTransportUnauthorized(route: String) async throws {
        let fixture = AuthTransportFixture { _, complete in complete(401) }
        defer { fixture.close() }
        await Task.yield()
        await fixture.send(route: route)
        #expect(AuthTokenStore.load() == nil)
        await fixture.drainInvalidations()
        #expect(fixture.auth.userId == nil)
        #expect(fixture.auth.errorMessage != nil)
    }

    @Test("Non-auth errors and tokenless requests cannot clear a later login")
    func unrelatedTransportFailure() async throws {
        for status in [401, 500] {
            let pending = DeferredAuthResponse()
            let fixture = AuthTransportFixture { request, complete in
                if status == 401 { #expect(request.value(forHTTPHeaderField: "Authorization") == nil) }
                pending.store(complete)
            }
            defer { fixture.close() }
            if status == 401 { AuthTokenStore.clear() }
            let operation = Task { await fixture.send(route: "transport") }
            try await pending.waitUntilReady()
            AuthTokenStore.save("transport-fixture-later-login")
            pending.finish(status: status)
            await operation.value
            await fixture.drainInvalidations()
            #expect(AuthTokenStore.load() == "transport-fixture-later-login")
            #expect(fixture.auth.userId == 920001)
        }
    }

    @Test("A current authenticated 500 preserves login")
    func currentTransportServerFailure() async {
        let fixture = AuthTransportFixture { _, complete in complete(500) }
        defer { fixture.close() }
        await fixture.send(route: "transport")
        await fixture.drainInvalidations()
        #expect(AuthTokenStore.load() == "transport-fixture-old")
        #expect(fixture.auth.userId == 920001)
        #expect(fixture.auth.errorMessage == nil)
    }

    @Test("Only the current API origin and path may invalidate the matching bearer")
    func unauthorizedRequestScope() async {
        for (url, bearer) in [
            ("http://127.0.0.1:2/api/auth/me", "Bearer transport-fixture-old"),
            ("https://127.0.0.1:1/api/auth/me", "Bearer transport-fixture-old"),
            ("http://localhost:1/api/auth/me", "Bearer transport-fixture-old"),
            ("http://127.0.0.1:1/api-other/auth/me", "Bearer transport-fixture-old"),
            ("http://127.0.0.1:1/public", "Bearer transport-fixture-old"),
            ("http://127.0.0.1:1/api/auth/me", "Bearer previous-request-token"),
            ("http://127.0.0.1:1/api/auth/me", ""),
        ] {
            let fixture = AuthTransportFixture { _, complete in complete(401) }
            defer { fixture.close() }
            var request = URLRequest(url: URL(string: url)!)
            if !bearer.isEmpty { request.setValue(bearer, forHTTPHeaderField: "Authorization") }
            APITransport.handleUnauthorized(401, request: request)
            await fixture.drainInvalidations()
            #expect(AuthTokenStore.load() == "transport-fixture-old", "Unrelated request: \(url)")
            #expect(fixture.auth.userId == 920001)
        }
    }

    @Test("Current WebSocket credentials invalidate only their matching HTTP API origin", arguments: ["http", "https"])
    func websocketUnauthorizedScope(scheme: String) async {
        let fixture = AuthTransportFixture { _, complete in complete(401) }
        defer { fixture.close() }
        UserDefaults.standard.set("\(scheme)://127.0.0.1:1/api", forKey: "API_BASE_URL")
        let socketScheme = scheme == "http" ? "ws" : "wss"
        var request = URLRequest(url: URL(string: "\(socketScheme)://127.0.0.1:1/api/realtime")!)
        request.setValue("Bearer transport-fixture-old", forHTTPHeaderField: "Authorization")
        await Task.yield()
        APITransport.handleUnauthorized(401, request: request)
        await fixture.drainInvalidations()
        #expect(AuthTokenStore.load() == nil)
        #expect(fixture.auth.userId == nil)
    }

    @Test("A queued session invalidation cannot clear a new login")
    func queuedInvalidationPreservesLogin() async {
        let fixture = AuthTransportFixture { _, complete in complete(200) }
        defer { fixture.close() }
        await Task.yield()
        // transport가 A를 지운 직후 MainActor observer가 소비하기 전에 B가 로그인한다.
        AuthTokenStore.clear()
        NotificationCenter.default.post(name: .apiSessionInvalidated, object: nil)
        AuthTokenStore.save("transport-fixture-new-login")
        fixture.auth.userId = 920002
        fixture.auth.nickname = "새 로그인"
        UserDefaults.standard.set(920002, forKey: "auth_user_id")
        await fixture.drainInvalidations()
        #expect(AuthTokenStore.load() == "transport-fixture-new-login")
        #expect(fixture.auth.userId == 920002)
        #expect(fixture.auth.nickname == "새 로그인")
        #expect(fixture.auth.errorMessage == nil)
        #expect(UserDefaults.standard.integer(forKey: "auth_user_id") == 920002)
    }
}

@MainActor
private final class AuthTransportFixture {
    let auth: AuthSession
    let session: URLSession
    let client: APIClient
    private let savedToken = AuthTokenStore.load()
    private let keys = ["API_BASE_URL", "auth_user_id", "auth_nickname", "auth_is_owner", "auth_is_admin", "profile_email"]
    private var savedDefaults: [String: Any] = [:]

    init(handler: @escaping AuthTransportProtocol.Handler) {
        for key in keys { savedDefaults[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults.standard.set("http://127.0.0.1:1/api", forKey: "API_BASE_URL")
        UserDefaults.standard.set(920001, forKey: "auth_user_id")
        UserDefaults.standard.set("테스트 로그인", forKey: "auth_nickname")
        AuthTokenStore.save("transport-fixture-old")
        #expect(AuthTokenStore.load() == "transport-fixture-old", "A signed simulator test host is required")
        AuthTransportProtocol.setHandler(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AuthTransportProtocol.self]
        session = URLSession(configuration: config)
        client = APIClient(session: session)
        auth = AuthSession(session: session)
    }

    func send(route: String) async {
        do {
            switch route {
            case "update":
                _ = try await client.updateUser(userId: 920001, nickname: "이름", phone: "", address: "", email: "")
            case "delete":
                _ = try await client.deleteAccount(userId: 920001)
            default:
                let request = URLRequest(url: APIEnvironment.apiBaseURL.appendingPathComponent("auth/me"))
                _ = try await APITransport.data(for: request, session: session)
            }
            Issue.record("Expected an HTTP failure")
        } catch {
            // 이 테스트의 관찰 대상은 서버 오류 자체가 아닌 현재 로그인 보존 여부다.
        }
    }

    func drainInvalidations() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    func close() {
        session.invalidateAndCancel()
        AuthTransportProtocol.setHandler(nil)
        if let savedToken { AuthTokenStore.save(savedToken) } else { AuthTokenStore.clear() }
        for key in keys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}

private final class DeferredAuthResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var complete: ((Int) -> Void)?
    var isReady: Bool { lock.lock(); defer { lock.unlock() }; return complete != nil }
    func store(_ complete: @escaping (Int) -> Void) { lock.lock(); self.complete = complete; lock.unlock() }
    func finish(status: Int) {
        lock.lock(); let response = complete; complete = nil; lock.unlock()
        response?(status)
    }
    @MainActor func waitUntilReady() async throws {
        for _ in 0..<200 {
            if isReady { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw URLError(.timedOut)
    }
}

private final class AuthTransportProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest, @escaping (Int) -> Void) -> Void
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    private let stateLock = NSLock()
    private var stopped = false
    static func setHandler(_ value: Handler?) { lock.lock(); handler = value; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let handler = Self.handler; Self.lock.unlock()
        handler?(request) { [weak self] status in
            guard let self else { return }
            self.stateLock.lock(); let stopped = self.stopped; self.stateLock.unlock()
            guard !stopped, let url = self.request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data())
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}
