import SwiftUI

// MARK: - Hex initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Design Tokens (default_shadcn_theme.css 기준)
extension Color {

    // MARK: Base
    /// --background: #ffffff
    static let tokenBackground = Color(hex: "#ffffff")
    /// --foreground: oklch(0.145 0 0) ≈ #1a1a1a
    static let tokenForeground = Color(hex: "#1a1a1a")

    // MARK: Card
    /// --card: #ffffff
    static let tokenCard = Color(hex: "#ffffff")
    /// --card-foreground: oklch(0.145 0 0) ≈ #1a1a1a
    static let tokenCardForeground = Color(hex: "#1a1a1a")

    // MARK: Popover
    /// --popover: oklch(1 0 0) ≈ #ffffff
    static let tokenPopover = Color(hex: "#ffffff")
    /// --popover-foreground: oklch(0.145 0 0) ≈ #1a1a1a
    static let tokenPopoverForeground = Color(hex: "#1a1a1a")

    // MARK: Primary
    /// --primary: #030213
    static let tokenPrimary = Color(hex: "#030213")
    /// --primary-foreground: oklch(1 0 0) ≈ #ffffff
    static let tokenPrimaryForeground = Color(hex: "#ffffff")

    // MARK: Secondary
    /// --secondary: oklch(0.95 0.0058 264.53) ≈ #efeffd
    static let tokenSecondary = Color(hex: "#efeffd")
    /// --secondary-foreground: #030213
    static let tokenSecondaryForeground = Color(hex: "#030213")

    // MARK: Muted
    /// --muted: #ececf0
    static let tokenMuted = Color(hex: "#ececf0")
    /// --muted-foreground: #717182
    static let tokenMutedForeground = Color(hex: "#717182")

    // MARK: Accent
    /// --accent: #e9ebef
    static let tokenAccent = Color(hex: "#e9ebef")
    /// --accent-foreground: #030213
    static let tokenAccentForeground = Color(hex: "#030213")

    // MARK: Destructive
    /// --destructive: #d4183d
    static let tokenDestructive = Color(hex: "#d4183d")
    /// --destructive-foreground: #ffffff
    static let tokenDestructiveForeground = Color(hex: "#ffffff")

    // MARK: Border / Input
    /// --border: rgba(0,0,0,0.1)
    static let tokenBorder = Color.black.opacity(0.1)
    /// --input-background: #f3f3f5
    static let tokenInputBackground = Color(hex: "#f3f3f5")
    /// --switch-background: #cbced4
    static let tokenSwitchBackground = Color(hex: "#cbced4")

    // MARK: Ring
    /// --ring: oklch(0.708 0 0) ≈ #b3b3b3
    static let tokenRing = Color(hex: "#b3b3b3")

    // MARK: Chart
    /// --chart-1: oklch(0.646 0.222 41.116) ≈ #e8622a
    static let tokenChart1 = Color(hex: "#e8622a")
    /// --chart-2: oklch(0.6 0.118 184.704) ≈ #21a08a
    static let tokenChart2 = Color(hex: "#21a08a")
    /// --chart-3: oklch(0.398 0.07 227.392) ≈ #2e5f82
    static let tokenChart3 = Color(hex: "#2e5f82")
    /// --chart-4: oklch(0.828 0.189 84.429) ≈ #d4b428
    static let tokenChart4 = Color(hex: "#d4b428")
    /// --chart-5: oklch(0.769 0.188 70.08) ≈ #d49a1e
    static let tokenChart5 = Color(hex: "#d49a1e")

    // MARK: Sidebar
    /// --sidebar: oklch(0.985 0 0) ≈ #f9f9f9
    static let tokenSidebar = Color(hex: "#f9f9f9")
    /// --sidebar-foreground: oklch(0.145 0 0) ≈ #1a1a1a
    static let tokenSidebarForeground = Color(hex: "#1a1a1a")
    /// --sidebar-primary: #030213
    static let tokenSidebarPrimary = Color(hex: "#030213")
    /// --sidebar-primary-foreground: oklch(0.985 0 0) ≈ #f9f9f9
    static let tokenSidebarPrimaryForeground = Color(hex: "#f9f9f9")
    /// --sidebar-accent: oklch(0.97 0 0) ≈ #f7f7f7
    static let tokenSidebarAccent = Color(hex: "#f7f7f7")
    /// --sidebar-accent-foreground: oklch(0.205 0 0) ≈ #303030
    static let tokenSidebarAccentForeground = Color(hex: "#303030")
    /// --sidebar-border: oklch(0.922 0 0) ≈ #e6e6e6
    static let tokenSidebarBorder = Color(hex: "#e6e6e6")
    /// --sidebar-ring: oklch(0.708 0 0) ≈ #b3b3b3
    static let tokenSidebarRing = Color(hex: "#b3b3b3")

    // MARK: 맡겨멍 Brand Colors (프로토타입 커스텀)
    static let brandOrange      = Color(hex: "#F5A65B")
    static let brandOrangeLight = Color(hex: "#F5C98B")
    static let brandBrown       = Color(hex: "#5B3A1F")
    static let brandBrownMid    = Color(hex: "#a07a55")
    static let brandBrownLight  = Color(hex: "#C9A27A")
    static let brandCream       = Color(hex: "#FAF3E7")
    static let brandCreamLight  = Color(hex: "#F1E2CB")
    static let brandIvory       = Color(hex: "#FFF1DC")
    static let brandBeigeBorder = Color(hex: "#EBD9BF")
    static let brandGreen       = Color(hex: "#5BB58A")
    static let brandGreenDark   = Color(hex: "#2c6b4a")
    static let brandGreenLight  = Color(hex: "#BFE9D5")
    static let brandBlueLight   = Color(hex: "#C7E6F5")
    static let brandKakaoYellow = Color(hex: "#FEE500")
    static let brandNaverGreen  = Color(hex: "#03C75A")
}
