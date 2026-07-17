import SwiftUI

struct StartView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession
    @Environment(UserProfile.self) private var userProfile
    @State private var selectedRole: UserRole = .user

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                logoSection
                illustrationSection
                taglineSection
                roleCards
                loginButtons
                footerText
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "#FFF1DC"), Color(hex: "#FAF3E7"), Color(hex: "#FFE9D2")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Sections

    private var logoSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.brandOrange)
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.brandOrange.opacity(0.6), radius: 7, x: 0, y: 6)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: "#FFF8EF"))
                }
                Text("맡겨멍")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
            }
            Text("MAT-GYEO-MEONG · Premium Pet Care")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
        }
        .safeAreaTopPadding()
    }

    private var illustrationSection: some View {
        ZStack {
            Circle()
                .fill(Color.brandGreenLight.opacity(0.7))
                .frame(width: 32, height: 32)
                .offset(x: -110, y: -30)
            Circle()
                .fill(Color.brandBlueLight.opacity(0.8))
                .frame(width: 20, height: 20)
                .offset(x: 110, y: 0)
            HStack(spacing: 8) {
                EmojiIcon(emoji: "🏠", size: 80)
                Image("dog_c").resizable().scaledToFit().frame(width: 80, height: 80)
            }
            .frame(width: 260, height: 200)
        }
        .padding(.top, 20)
    }

    private var taglineSection: some View {
        VStack(spacing: 8) {
            Text("우리 아이를 믿고 맡기는\n가장 귀여운 방법")
                .font(.system(size: 19, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.brandBrown)
            HStack(spacing: 4) {
                Text("따뜻한 손길로 돌봐드릴게요")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandBrownMid)
                EmojiIcon(emoji: "🐾", size: 14)
            }
        }
        .padding(.top, 12)
    }

    private var roleCards: some View {
        VStack(spacing: 12) {
            RoleCardView(
                title: "보호자",
                subtitle: "우리 강아지를 맡길 곳을 찾아요",
                emoji: "img:dog_c",
                tint: Color(hex: "#FFE6CC"),
                ring: Color.brandOrange,
                isSelected: selectedRole != .owner,
                action: { selectedRole = .user }
            )
            RoleCardView(
                title: "보호자 · 사장님",
                subtitle: "받은 예약 요청도 확인하고 관리해요",
                emoji: "🏠",
                tint: Color.brandGreenLight,
                ring: Color.brandGreen,
                isSelected: selectedRole == .owner,
                action: { selectedRole = .owner }
            )
        }
        .padding(.top, 20)
    }

    private var loginButtons: some View {
        VStack(spacing: 10) {
            Button(action: {
                Task {
                    await authSession.loginWithKakao(profile: userProfile, asOwner: selectedRole == .owner)
                    if authSession.isLoggedIn {
                        router.go(.home)
                    }
                }
            }) {
                HStack(spacing: 8) {
                    if authSession.isLoading {
                        ProgressView().tint(Color(hex: "#3C1E1E"))
                    } else {
                        Image(systemName: "message.fill").font(.system(size: 16))
                        Text("카카오 간편로그인")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.brandKakaoYellow)
                .foregroundStyle(Color(hex: "#3C1E1E"))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .shadow(color: Color.brandKakaoYellow.opacity(0.8), radius: 9, x: 0, y: 8)
            }
            .disabled(authSession.isLoading)

            if let error = authSession.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 20)
        .onAppear {
            if authSession.isLoggedIn { router.go(.home) }
        }
    }

    private var footerText: some View {
        VStack(spacing: 8) {
            Text("처음이라면 자동으로 회원가입 돼요 · 3초면 시작\n시작 시 이용약관 및 개인정보처리방침에 동의합니다")
                .font(.system(size: 10))
                .foregroundStyle(Color.brandBrownMid)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
#if DEBUG
            Button("개발자 진입 (시뮬레이터용)") {
                Task {
                    await authSession.loginAsDeveloper(profile: userProfile, asOwner: selectedRole == .owner)
                    if authSession.isLoggedIn { router.go(.home) }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.brandBrownLight)
#endif
        }
        .padding(.top, 12)
    }
}

// MARK: - RoleCardView

struct RoleCardView: View {
    let title: String
    let subtitle: String
    let emoji: String
    let tint: Color
    let ring: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(tint)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(ring.opacity(0.2), lineWidth: 2)
                        )
                        .frame(width: 56, height: 56)
                    EmojiIcon(emoji: emoji, size: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.brandBrownMid)
                }
                Spacer()
                if isSelected {
                    ZStack {
                        Circle().fill(Color.brandOrange).frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brandBrownLight)
                }
            }
            .padding(16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.pill)
                    .stroke(isSelected ? Color.brandOrange : Color(hex: "#F1E2CB"), lineWidth: 2)
            )
            .shadow(color: Color.brandBrown.opacity(0.12), radius: 9, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}
