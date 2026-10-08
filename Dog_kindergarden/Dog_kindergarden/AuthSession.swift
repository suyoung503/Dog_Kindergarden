import Foundation
import Observation
import KakaoSDKCommon
import KakaoSDKAuth
import KakaoSDKUser

@Observable
@MainActor
final class AuthSession {
    var userId: Int?
    var nickname: String = ""
    var isOwner: Bool = false
    var isAdmin: Bool = false
    var isLoading = false
    var errorMessage: String?
    private var sessionInvalidationTask: Task<Void, Never>?

    var isLoggedIn: Bool { userId != nil && AuthTokenStore.load() != nil }

    init() {
        if AuthTokenStore.load() != nil {
            userId = UserDefaults.standard.value(forKey: "auth_user_id") as? Int
            nickname = UserDefaults.standard.string(forKey: "auth_nickname") ?? ""
            isOwner = UserDefaults.standard.bool(forKey: "auth_is_owner")
            isAdmin = UserDefaults.standard.bool(forKey: "auth_is_admin")
        } else {
            clearLocalSession()
        }

        sessionInvalidationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .apiSessionInvalidated) {
                guard let self else { return }
                self.clearLocalSession()
                self.errorMessage = "로그인이 만료되었어요. 다시 로그인해주세요."
            }
        }
    }

    func loginWithKakao(profile: UserProfile? = nil, asOwner: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let oauthToken: OAuthToken = try await withCheckedThrowingContinuation { continuation in
                if UserApi.isKakaoTalkLoginAvailable() {
                    UserApi.shared.loginWithKakaoTalk { token, error in
                        if let error { continuation.resume(throwing: error); return }
                        guard let token else {
                            continuation.resume(throwing: URLError(.userAuthenticationRequired))
                            return
                        }
                        continuation.resume(returning: token)
                    }
                } else {
                    UserApi.shared.loginWithKakaoAccount { token, error in
                        if let error { continuation.resume(throwing: error); return }
                        guard let token else {
                            continuation.resume(throwing: URLError(.userAuthenticationRequired))
                            return
                        }
                        continuation.resume(returning: token)
                    }
                }
            }

            try await registerWithBackend(
                kakaoAccessToken: oauthToken.accessToken,
                asOwner: asOwner,
                profile: profile
            )
        } catch {
            if case let SdkError.ClientFailed(reason, _) = error, reason == .Cancelled { return }
            errorMessage = "로그인에 실패했어요. 다시 시도해주세요."
        }
    }

    func logout() {
        let sessionToken = AuthTokenStore.load()
        UserApi.shared.logout { _ in }
        clearLocalSession()

        // 로컬 상태를 먼저 지워 즉시 로그아웃하고, 서버 세션 폐기는 best-effort로 처리한다.
        if let sessionToken {
            Task {
                let url = APIEnvironment.apiBaseURL.appendingPathComponent("auth/logout")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }

#if DEBUG
    // 로컬 wrangler에서 ALLOW_DEV_AUTH=true일 때만 사용한다. 운영 Worker에서는 항상 404다.
    func loginAsDeveloper(profile: UserProfile? = nil, asOwner: Bool, asAdmin: Bool = false) async {
        errorMessage = nil
        guard APIEnvironment.isLocalDevelopment else {
            errorMessage = "개발자 진입은 로컬 API에서만 사용할 수 있어요."
            return
        }

        do {
            let url = APIEnvironment.apiBaseURL.appendingPathComponent("auth/dev")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "nickname": asOwner ? "테스트사장님" : "테스트",
                "is_owner": asOwner,
                "is_admin": asAdmin,
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            try applyLoginResponse(
                data: data,
                response: response,
                fallbackNickname: asOwner ? "테스트사장님" : "테스트",
                profile: profile
            )
        } catch {
            errorMessage = "개발자 로그인 실패 — 로컬 서버 설정을 확인해주세요."
        }
    }
#endif

    func updateNickname(_ name: String) {
        nickname = name
        UserDefaults.standard.set(name, forKey: "auth_nickname")
    }

    private func registerWithBackend(
        kakaoAccessToken: String,
        asOwner: Bool,
        profile: UserProfile?
    ) async throws {
        let url = APIEnvironment.apiBaseURL.appendingPathComponent("auth/kakao")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "access_token": kakaoAccessToken,
            "is_owner": asOwner,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try applyLoginResponse(
            data: data,
            response: response,
            fallbackNickname: "보호자",
            profile: profile
        )
    }

    private func applyLoginResponse(
        data: Data,
        response: URLResponse,
        fallbackNickname: String,
        profile: UserProfile?
    ) throws {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus }

        if http.statusCode == 409 {
            let registeredAsOwner = (json?["is_owner"] as? Int) == 1
            errorMessage = "이미 \(registeredAsOwner ? "보호자 · 사장님" : "보호자") 계정으로 가입된 카카오 계정이에요.\n해당 역할을 선택해 로그인해주세요."
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
        guard let id = json?["user_id"] as? Int,
              let sessionToken = json?["session_token"] as? String,
              !sessionToken.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        AuthTokenStore.save(sessionToken)
        userId = id
        nickname = json?["nickname"] as? String ?? fallbackNickname
        isOwner = (json?["is_owner"] as? Int) == 1
        isAdmin = (json?["is_admin"] as? Int) == 1
        UserDefaults.standard.set(id, forKey: "auth_user_id")
        UserDefaults.standard.set(nickname, forKey: "auth_nickname")
        UserDefaults.standard.set(isOwner, forKey: "auth_is_owner")
        UserDefaults.standard.set(isAdmin, forKey: "auth_is_admin")

        if let profile {
            profile.name = nickname
            profile.phone = (json?["phone"] as? String) ?? ""
            profile.address = (json?["address"] as? String) ?? ""
        }
    }

    private func clearLocalSession() {
        userId = nil
        nickname = ""
        isOwner = false
        isAdmin = false
        errorMessage = nil
        AuthTokenStore.clear()
        UserDefaults.standard.removeObject(forKey: "auth_user_id")
        UserDefaults.standard.removeObject(forKey: "auth_nickname")
        UserDefaults.standard.removeObject(forKey: "auth_is_owner")
        UserDefaults.standard.removeObject(forKey: "auth_is_admin")
    }
}
