import Foundation
import Testing
@testable import Dog_kindergarden

// 같은 UserDefaults를 다루는 기존 이메일 테스트와 직렬로 실행한다.
extension ProfileEmailTests {
    @Test("Cold session refresh restores all four server fields and persists them")
    func coldProfileRefresh() async throws {
        let fixture = ProfileSyncFixture { request, complete in
            #expect(request.url?.path == "/api/auth/me")
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            complete(200, Self.serverProfile())
        }
        defer { fixture.close() }
        await fixture.auth.refreshProfile(profile: fixture.profile)
        #expect(fixture.profile.name == "서버 이름")
        #expect(fixture.profile.phone == "010-0000-1234")
        #expect(fixture.profile.address == "테스트 주소")
        #expect(fixture.profile.email == "sync@example.com")
        #expect(fixture.auth.nickname == "서버 이름")
        let restored = UserProfile()
        #expect([restored.name, restored.phone, restored.address, restored.email] ==
                [fixture.profile.name, fixture.profile.phone, fixture.profile.address, fixture.profile.email])
    }

    @Test("Null server fields clear stale local optional fields")
    func nullProfileRefresh() async {
        let fixture = ProfileSyncFixture { _, complete in
            complete(200, Data(#"{"user_id":910001,"nickname":"서버 이름","phone":null,"address":null,"email":null}"#.utf8))
        }
        defer { fixture.close() }
        await fixture.auth.refreshProfile(profile: fixture.profile)
        #expect(fixture.profile.name == "서버 이름")
        #expect([fixture.profile.phone, fixture.profile.address, fixture.profile.email] == ["", "", ""])
    }

    @Test("Another app account and temporary failures preserve cached profile", arguments: [200, 500, 404])
    func rejectedProfileResponse(status: Int) async {
        let fixture = ProfileSyncFixture { _, complete in
            complete(status, Data(#"{"user_id":910002,"nickname":"다른 계정","email":"other@example.com"}"#.utf8))
        }
        defer { fixture.close() }
        await fixture.auth.refreshProfile(profile: fixture.profile)
        #expect(fixture.profile.name == "캐시 이름")
        #expect(fixture.profile.email == "cached@example.com")
        #expect(fixture.auth.userId == 910001)
    }

    @Test("Malformed or incomplete profile responses cannot erase cached fields", arguments: ["not-json", #"{"user_id":910001,"nickname":123}"#, #"{"user_id":910001}"#])
    func malformedProfileResponse(body: String) async {
        let fixture = ProfileSyncFixture { _, complete in complete(200, Data(body.utf8)) }
        defer { fixture.close() }
        await fixture.auth.refreshProfile(profile: fixture.profile)
        #expect(fixture.profile.name == "캐시 이름")
        #expect(fixture.profile.email == "cached@example.com")
    }

    @Test("Delayed old responses cannot overwrite or invalidate a switched account or API server", arguments: [200, 401])
    func staleProfileResponse(status: Int) async throws {
        for change in ["logout", "account", "token", "server"] {
            let pending = DeferredProfileResponse()
            let fixture = ProfileSyncFixture { _, complete in pending.store(complete) }
            defer { fixture.close() }
            let refresh = Task { await fixture.auth.refreshProfile(profile: fixture.profile) }
            try await pending.waitUntilReady()
            let token = "replacement-profile-session"
            switch change {
            case "logout": fixture.auth.userId = nil; AuthTokenStore.clear()
            case "account": fixture.auth.userId = 910002; AuthTokenStore.save(token)
            case "token": AuthTokenStore.save(token)
            default: UserDefaults.standard.set("http://127.0.0.1:2/api", forKey: "API_BASE_URL")
            }
            let expectedToken = AuthTokenStore.load()
            pending.finish(status: status, data: Self.serverProfile())
            await refresh.value
            #expect(AuthTokenStore.load() == expectedToken, "Old \(status) must not invalidate \(change)")
            #expect(fixture.profile.name == "캐시 이름", "Old response must not overwrite \(change)")
            #expect(fixture.auth.userId == (change == "logout" ? nil : change == "account" ? 910002 : 910001))
        }
    }

    @Test("An in-flight refresh never rolls back a local edit or a successful save")
    func profileRevisionProtectsNewerValues() async throws {
        for savingWithoutValueChange in [false, true] {
            let pending = DeferredProfileResponse()
            let fixture = ProfileSyncFixture { _, complete in pending.store(complete) }
            defer { fixture.close() }
            let refresh = Task { await fixture.auth.refreshProfile(profile: fixture.profile) }
            try await pending.waitUntilReady()
            if savingWithoutValueChange {
                fixture.profile.invalidatePendingRefresh()
            } else {
                fixture.profile.name = "방금 저장한 이름"
                fixture.profile.email = "new@example.com"
            }
            pending.finish(status: 200, data: Self.serverProfile())
            await refresh.value
            #expect(fixture.profile.name == (savingWithoutValueChange ? "캐시 이름" : "방금 저장한 이름"))
            #expect(fixture.profile.email == (savingWithoutValueChange ? "cached@example.com" : "new@example.com"))
        }
    }

    @Test("Only the latest profile refresh may apply its response")
    func overlappingProfileRefreshes() async throws {
        let firstResponse = DeferredProfileResponse()
        let secondResponse = DeferredProfileResponse()
        let fixture = ProfileSyncFixture { _, complete in
            if firstResponse.isReady { secondResponse.store(complete) }
            else { firstResponse.store(complete) }
        }
        defer { fixture.close() }
        let first = Task { await fixture.auth.refreshProfile(profile: fixture.profile) }
        try await firstResponse.waitUntilReady()
        let second = Task { await fixture.auth.refreshProfile(profile: fixture.profile) }
        try await secondResponse.waitUntilReady()
        firstResponse.finish(status: 401, data: Data())
        await first.value
        #expect(AuthTokenStore.load() != nil)
        secondResponse.finish(status: 200, data: Self.serverProfile())
        await second.value
        #expect(fixture.profile.name == "서버 이름")
    }

    @Test("Current session unauthorized response signs out without replacing the profile")
    func currentUnauthorizedProfileRefresh() async {
        let fixture = ProfileSyncFixture { _, complete in complete(401, Data()) }
        defer { fixture.close() }
        await fixture.auth.refreshProfile(profile: fixture.profile)
        #expect(fixture.auth.userId == nil)
        #expect(AuthTokenStore.load() == nil)
        #expect(fixture.profile.name == "캐시 이름")
        #expect(fixture.auth.errorMessage != nil)
    }

    nonisolated private static func serverProfile() -> Data {
        Data(#"{"user_id":910001,"nickname":"서버 이름","phone":"010-0000-1234","address":"테스트 주소","email":"sync@example.com"}"#.utf8)
    }
}

@MainActor
private final class ProfileSyncFixture {
    let auth: AuthSession
    let profile: UserProfile
    private let session: URLSession
    private let savedToken = AuthTokenStore.load()
    private let keys = ["API_BASE_URL", "auth_user_id", "auth_nickname", "auth_is_owner", "auth_is_admin", "profile_name", "profile_phone", "profile_address", "profile_email"]
    private var savedDefaults: [String: Any] = [:]

    init(handler: @escaping ProfileSyncProtocol.Handler) {
        let defaults = UserDefaults.standard
        for key in keys { savedDefaults[key] = defaults.object(forKey: key) }
        // 요청은 세션 전용 URLProtocol이 가로채며 운영 API로는 절대 향하지 않는다.
        defaults.set("http://127.0.0.1:1/api", forKey: "API_BASE_URL")
        defaults.set(910001, forKey: "auth_user_id")
        defaults.set("캐시 이름", forKey: "auth_nickname")
        let token = "profile-fixture-\(UUID().uuidString)"
        AuthTokenStore.save(token)
        #expect(AuthTokenStore.load() == token, "A signed simulator test host is required")
        ProfileSyncProtocol.setHandler(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProfileSyncProtocol.self]
        session = URLSession(configuration: config)
        auth = AuthSession(session: session)
        profile = UserProfile()
        profile.name = "캐시 이름"
        profile.phone = "이전 연락처"
        profile.address = "이전 주소"
        profile.email = "cached@example.com"
    }

    func close() {
        session.invalidateAndCancel()
        ProfileSyncProtocol.setHandler(nil)
        if let savedToken { AuthTokenStore.save(savedToken) } else { AuthTokenStore.clear() }
        for key in keys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}

private final class DeferredProfileResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var complete: ((Int, Data) -> Void)?
    var isReady: Bool { lock.lock(); defer { lock.unlock() }; return complete != nil }
    func store(_ complete: @escaping (Int, Data) -> Void) { lock.lock(); self.complete = complete; lock.unlock() }
    func finish(status: Int, data: Data) {
        lock.lock(); let response = complete; complete = nil; lock.unlock()
        response?(status, data)
    }
    @MainActor func waitUntilReady() async throws {
        for _ in 0..<200 {
            if isReady { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw URLError(.timedOut)
    }
}

private final class ProfileSyncProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest, @escaping (Int, Data) -> Void) -> Void
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    private let stateLock = NSLock()
    private var stopped = false
    static func setHandler(_ value: Handler?) { lock.lock(); handler = value; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let handler = Self.handler; Self.lock.unlock()
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
