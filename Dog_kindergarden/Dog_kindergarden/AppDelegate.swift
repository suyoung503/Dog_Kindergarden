import UIKit
import KakaoMapsSDK
import KakaoSDKCommon
import KakaoSDKAuth
import UserNotifications
import BackgroundTasks

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let appKey = Bundle.main.object(forInfoDictionaryKey: "KAKAO_NATIVE_APP_KEY") as? String ?? ""
        // KakaoMaps SDK 초기화
        SDKInitializer.InitSDK(appKey: appKey)
        // KakaoSDK (로그인) 초기화
        KakaoSDK.initSDK(appKey: appKey)
        // 로컬 알림 포그라운드 표시·탭 딥링크 델리게이트
        UNUserNotificationCenter.current().delegate = AppNotificationService.shared
        // 백그라운드 알림 폴링 등록 (didFinishLaunching 리턴 전에 등록해야 함)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppNotificationService.backgroundTaskId, using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            AppNotificationService.handleBackgroundRefresh(refresh)
        }
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if AuthApi.isKakaoTalkLoginUrl(url) {
            return AuthController.handleOpenUrl(url: url)
        }
        return false
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}
}
