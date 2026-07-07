import UIKit

// GeometryReader 없이 UIKit에서 직접 safeArea 읽기
extension UIApplication {
    static var safeAreaTop: CGFloat {
        (shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 44
    }
    static var safeAreaBottom: CGFloat {
        (shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom) ?? 34
    }
}
