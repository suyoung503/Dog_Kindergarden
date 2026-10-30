import UIKit
import SwiftUI
import KakaoSDKAuth

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var notificationService = AppNotificationService.shared

    // Scene 기반 앱에서는 카카오톡 로그인 복귀 URL이 AppDelegate가 아니라 여기로 전달된다
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts { handleURL(context.url) }
    }

    private func handleURL(_ url: URL) {
        if AuthApi.isKakaoTalkLoginUrl(url) {
            _ = AuthController.handleOpenUrl(url: url)
        } else {
            StoreShareInbox.shared.receive(url)
        }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        for context in connectionOptions.urlContexts { handleURL(context.url) }

        let hostingController = UIHostingController(rootView: RootView())
        // 호스팅 컨트롤러 배경 투명 — SwiftUI 뷰가 직접 배경 담당
        hostingController.view.backgroundColor = .clear

        let window = UIWindow(windowScene: windowScene)
        // 윈도우 배경을 앱 배경색으로 — 어떤 틈새도 검정으로 보이지 않게
        window.backgroundColor = UIColor(red: 0.98, green: 0.95, blue: 0.91, alpha: 1) // #FAF3E7
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) { }
    func sceneDidBecomeActive(_ scene: UIScene) {
        // UIKit에서 호스팅한 SwiftUI의 scenePhase 대신 실제 장면 수명주기를 전달한다.
        notificationService.setForegroundActive(true)
        Task { await notificationService.refreshAuthorizationStatus() }
    }
    func sceneWillResignActive(_ scene: UIScene) {
        notificationService.setForegroundActive(false)
    }
    func sceneWillEnterForeground(_ scene: UIScene) { }
    func sceneDidEnterBackground(_ scene: UIScene) {
        notificationService.setForegroundActive(false)
        AppNotificationService.scheduleBackgroundRefresh()
    }
}
