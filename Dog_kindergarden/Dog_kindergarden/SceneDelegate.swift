import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

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
    func sceneDidBecomeActive(_ scene: UIScene) { }
    func sceneWillResignActive(_ scene: UIScene) { }
    func sceneWillEnterForeground(_ scene: UIScene) { }
    func sceneDidEnterBackground(_ scene: UIScene) {
        AppNotificationService.scheduleBackgroundRefresh()
    }
}
