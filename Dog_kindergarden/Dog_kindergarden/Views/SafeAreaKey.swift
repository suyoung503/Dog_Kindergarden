import UIKit
import SwiftUI

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

// 상단 safe area + 12pt 여백 모디파이어.
// 주의: UIApplication.safeAreaTop을 body 평가 중에 직접 읽으면 콜드 런치 때 아직 확정되지
// 않은 윈도우 레이아웃과 피드백 순환(AttributeGraph cycle)이 생겨 그 화면이 얼어붙는다.
// 값을 @State에 캐시하고 레이아웃이 끝난 onAppear에서 채워, body가 UIKit 레이아웃을 읽지 않게 한다.
private struct SafeAreaTopPadding: ViewModifier {
    @State private var topInset: CGFloat = 56 // 44(기본 safe area) + 12
    func body(content: Content) -> some View {
        content
            .padding(.top, topInset)
            .onAppear { topInset = UIApplication.safeAreaTop + 12 }
    }
}

extension View {
    /// 상단 safe area + 12pt 여백. `.padding(.top, UIApplication.safeAreaTop + 12)` 대신 사용한다.
    func safeAreaTopPadding() -> some View {
        modifier(SafeAreaTopPadding())
    }
}
