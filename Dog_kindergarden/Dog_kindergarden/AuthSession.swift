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
    var isLoading = false
    var errorMessage: String?

    var isLoggedIn: Bool { userId != nil }

    private let baseURL = "https://matgyeomung-api.dog-kindergarden.workers.dev"

    init() {
        userId   = UserDefaults.standard.value(forKey: "auth_user_id") as? Int
        nickname = UserDefaults.standard.string(forKey: "auth_nickname") ?? ""
    }

    func loginWithKakao(profile: UserProfile? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // 카카오톡 앱 로그인 or 웹 로그인
            let _: OAuthToken = try await withCheckedThrowingContinuation { cont in
                if UserApi.isKakaoTalkLoginAvailable() {
                    UserApi.shared.loginWithKakaoTalk { token, error in
                        if let error { cont.resume(throwing: error); return }
                        guard let token else { return }
                        cont.resume(returning: token)
                    }
                } else {
                    UserApi.shared.loginWithKakaoAccount { token, error in
                        if let error { cont.resume(throwing: error); return }
                        guard let token else { return }
                        cont.resume(returning: token)
                    }
                }
            }

            // 카카오 사용자 정보 조회
            let kakaoUser: KakaoSDKUser.User = try await withCheckedThrowingContinuation { cont in
                UserApi.shared.me { user, error in
                    if let error { cont.resume(throwing: error); return }
                    guard let user else { return }
                    cont.resume(returning: user)
                }
            }

            let kakaoId = "\(kakaoUser.id ?? 0)"
            let name    = kakaoUser.kakaoAccount?.profile?.nickname ?? "보호자"

            try await registerWithBackend(kakaoId: kakaoId, nickname: name, profile: profile)
        } catch {
            errorMessage = "로그인에 실패했어요. 다시 시도해주세요."
        }
    }

    func logout() {
        UserApi.shared.logout { _ in }
        userId   = nil
        nickname = ""
        UserDefaults.standard.removeObject(forKey: "auth_user_id")
        UserDefaults.standard.removeObject(forKey: "auth_nickname")
    }

#if DEBUG
    // 시뮬레이터 개발자 진입 — 고정 kakao_id로 실제 유저 행을 만들어
    // 프로필 저장·예약 등 서버 연동이 실제로 동작하게 함
    func loginAsDeveloper(profile: UserProfile? = nil) async {
        do {
            try await registerWithBackend(kakaoId: "dev-simulator", nickname: "테스트", profile: profile)
        } catch {
            // 오프라인 폴백 (서버 연동 기능은 동작하지 않음)
            userId = 1
            nickname = "테스트"
        }
    }
#endif

    // 프로필 수정 저장 후 세션 닉네임도 함께 갱신
    func updateNickname(_ name: String) {
        nickname = name
        UserDefaults.standard.set(name, forKey: "auth_nickname")
    }

    private func registerWithBackend(kakaoId: String, nickname: String, profile: UserProfile?) async throws {
        guard let url = URL(string: "\(baseURL)/api/auth/kakao") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "kakao_id": kakaoId,
            "nickname": nickname
        ])

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let id = json?["user_id"] as? Int {
            self.userId   = id
            self.nickname = json?["nickname"] as? String ?? nickname
            UserDefaults.standard.set(id, forKey: "auth_user_id")
            UserDefaults.standard.set(self.nickname, forKey: "auth_nickname")

            // 서버에 저장된 프로필(닉네임·연락처·주소)을 로컬 UserProfile에도 반영
            if let profile {
                profile.name = self.nickname
                if let phone = json?["phone"] as? String, !phone.isEmpty {
                    profile.phone = phone
                }
                if let address = json?["address"] as? String, !address.isEmpty {
                    profile.address = address
                }
            }
        }
    }
}
