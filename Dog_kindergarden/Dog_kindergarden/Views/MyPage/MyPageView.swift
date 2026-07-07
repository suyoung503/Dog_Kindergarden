import SwiftUI

struct MyPageView: View {
    @Environment(AppRouter.self) private var router

    private let stats: [(label: String, value: String)] = [
        ("예약", "12"), ("강아지", "3"), ("포인트", "2,400")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navBar
                profileCard
                activitySection
                infoSection
                supportSection
                versionFooter
            }
            .padding(.bottom, 24)
        }
        .background(Color.brandCream.ignoresSafeArea())
    }

    // MARK: - Nav

    private var navBar: some View {
        HStack(spacing: 12) {
            Button(action: router.back) {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                    .overlay(Image(systemName: "chevron.left").font(.system(size: 15)).foregroundStyle(Color.brandBrown))
            }
            Text("마이페이지")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, UIApplication.safeAreaTop + 12)
    }

    // MARK: - Profile card

    private var profileCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white).frame(width: 64, height: 64).shadow(radius: 4)
                    Image(router.userDogAvatar).resizable().scaledToFit().frame(width: 42, height: 42)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("상민님")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    Text("010-1234-5678 · 카카오 로그인")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Button(action: {}) {
                    Text("수정")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.25))
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 8) {
                ForEach(stats, id: \.label) { s in
                    VStack(spacing: 2) {
                        Text(s.value).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        Text(s.label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: "#FFE6CC"), Color.brandOrange],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Sections

    private var activitySection: some View {
        MyPageSection(title: "내 활동") {
            MyPageItem(icon: "calendar",         label: "예약 내역",    badge: "2",   bg: Color(hex: "#FFE6CC")) { router.go(.booking) }
            MyPageItem(icon: "heart",             label: "찜한 케어",    badge: "8",   bg: Color(hex: "#FFC4C4"))
            MyPageItem(icon: "message",           label: "채팅",         badge: "3",   bg: Color.brandGreenLight) { router.go(.chatList) }
            MyPageItem(icon: "gift",              label: "쿠폰함",       badge: "5장", bg: Color(hex: "#FFF1A8"))
        }
    }

    private var infoSection: some View {
        MyPageSection(title: "내 정보") {
            MyPageItem(icon: "pawprint",          label: "우리 아이 프로필", bg: Color(hex: "#FFE6CC")) { router.go(.dogProfile) }
            MyPageItem(icon: "bell",              label: "알림 설정",    bg: Color.brandBlueLight)
            MyPageItem(icon: "gearshape",         label: "앱 설정",      bg: Color(hex: "#E8E0F0"))
        }
    }

    private var supportSection: some View {
        MyPageSection(title: "고객지원") {
            MyPageItem(icon: "bubble.left",       label: "1:1 문의")
            MyPageItem(icon: "megaphone",         label: "공지사항")
            MyPageItem(icon: "rectangle.portrait.and.arrow.right", label: "로그아웃")
        }
    }

    private var versionFooter: some View {
        Text("맡겨멍 v1.0.0")
            .font(.system(size: 10))
            .foregroundStyle(Color.brandBrownMid)
            .padding(.top, 24)
    }
}

// MARK: - MyPageSection

struct MyPageSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.brandBrownMid)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
            .padding(.horizontal, 20)
        }
        .padding(.top, 20)
    }
}

// MARK: - MyPageItem

struct MyPageItem: View {
    let icon: String
    let label: String
    var badge: String? = nil
    var bg: Color = Color.brandCream
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: action ?? {}) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(bg)
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.brandBrown)
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brandBrown)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.brandOrange)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrownLight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider()
            .foregroundStyle(Color(hex: "#F1E2CB"))
            .padding(.leading, 60)
    }
}
