import SwiftUI

// MARK: - Spacing
// Tailwind 4pt grid 기반
enum Spacing {
    /// 2pt
    static let xxs: CGFloat = 2
    /// 4pt
    static let xs: CGFloat = 4
    /// 6pt
    static let sm: CGFloat = 6
    /// 8pt
    static let md: CGFloat = 8
    /// 12pt
    static let lg: CGFloat = 12
    /// 16pt
    static let xl: CGFloat = 16
    /// 20pt
    static let xl2: CGFloat = 20
    /// 24pt
    static let xl3: CGFloat = 24
    /// 32pt
    static let xl4: CGFloat = 32
    /// 40pt
    static let xl5: CGFloat = 40
    /// 48pt
    static let xl6: CGFloat = 48
}

// MARK: - Corner Radius
// --radius: 0.625rem = 10pt (base)
enum Radius {
    /// --radius-sm: calc(var(--radius) - 4px) = 6pt
    static let sm: CGFloat = 6
    /// --radius-md: calc(var(--radius) - 2px) = 8pt
    static let md: CGFloat = 8
    /// --radius-lg (base): var(--radius) = 10pt
    static let lg: CGFloat = 10
    /// --radius-xl: calc(var(--radius) + 4px) = 14pt
    static let xl: CGFloat = 14
    /// 맡겨멍 전용 — 폰 프레임 외곽 (55px)
    static let phoneOuter: CGFloat = 55
    /// 맡겨멍 전용 — 폰 프레임 내부 (45px)
    static let phoneInner: CGFloat = 45
    /// 맡겨멍 전용 — pill 버튼
    static let pill: CGFloat = 999
}

// MARK: - Typography
enum Typography {
    /// --font-weight-normal: 400
    static let weightNormal: Font.Weight = .regular
    /// --font-weight-medium: 500
    static let weightMedium: Font.Weight = .medium

    /// 기본 폰트 사이즈 (--font-size: 16px)
    static let base: CGFloat = 16

    static let caption: Font  = .system(size: 11, weight: .regular)
    static let footnote: Font = .system(size: 12, weight: .regular)
    static let body: Font     = .system(size: 16, weight: .regular)
    static let bodyMedium: Font = .system(size: 16, weight: .medium)
    static let title3: Font   = .system(size: 20, weight: .bold)
    static let title2: Font   = .system(size: 22, weight: .bold)
    static let title: Font    = .system(size: 26, weight: .bold)
}

// MARK: - Shadow
enum Shadow {
    struct Style {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    /// 카드 기본 그림자
    static let card = Style(
        color: Color(hex: "#5B3A1F").opacity(0.12),
        radius: 16,
        x: 0,
        y: 8
    )
    /// 폰 프레임 그림자
    static let phoneFrame = Style(
        color: Color(hex: "#5B3A1F").opacity(0.35),
        radius: 60,
        x: 0,
        y: 30
    )
}
