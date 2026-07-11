import SwiftUI

struct MyPageView: View {
    @Environment(AppRouter.self) private var router
    @Environment(UserProfile.self) private var userProfile
    @Environment(AuthSession.self) private var authSession

    @State private var showEditSheet = false
    @State private var showLogoutConfirm = false
    @State private var showMyStoreSheet = false
    @State private var reservationCount: Int?
    @State private var petCount: Int?
    @State private var chatCount: Int?
    @State private var favoriteCount: Int?
    @State private var myStores: [OwnerStoreResponse] = []   // 사장님: 등록한 내 가게

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
        .sheet(isPresented: $showEditSheet) {
            ProfileEditSheet()
        }
        .sheet(isPresented: $showMyStoreSheet, onDismiss: { Task { await reloadMyStores() } }) {
            MyStoreSheet()
        }
        .task {
            guard let uid = authSession.userId else { return }
            reservationCount = (try? await APIClient.shared.fetchReservations(userId: uid))?.count
            petCount = (try? await APIClient.shared.fetchPets(userId: uid))?.count
            chatCount = (try? await ChatService.rooms(userId: uid))?.count
            favoriteCount = (try? await APIClient.shared.fetchFavorites(userId: uid))?.count
            await reloadMyStores()
        }
        .alert("로그아웃 하시겠어요?", isPresented: $showLogoutConfirm) {
            Button("취소", role: .cancel) {}
            Button("로그아웃", role: .destructive) {
                authSession.logout()
                router.reset(to: .start)
            }
        } message: {
            Text("다시 로그인해야 이용할 수 있어요.")
        }
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
        .safeAreaTopPadding()
    }

    // MARK: - Profile card

    // 통계는 실데이터: 로딩 전에는 "-" 표시
    private var stats: [(label: String, value: String)] {
        [
            ("예약",   reservationCount.map(String.init) ?? "-"),
            ("강아지", petCount.map(String.init) ?? "-"),
            ("채팅",   chatCount.map(String.init) ?? "-")
        ]
    }

    private var profileSubtitle: String {
        let phone = userProfile.phone.isEmpty ? "연락처를 등록해주세요" : userProfile.phone
        return authSession.isLoggedIn ? "\(phone) · 카카오 로그인" : phone
    }

    private var profileCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white).frame(width: 64, height: 64).shadow(radius: 4)
                    Image(router.userDogAvatar).resizable().scaledToFit().frame(width: 42, height: 42)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(userProfile.name)님")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    Text(profileSubtitle)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Button(action: { showEditSheet = true }) {
                    Text("수정")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.25))
                        .clipShape(Capsule())
                }
            }
            if authSession.isLoggedIn {
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
            MyPageItem(icon: "calendar",         label: "예약 내역",    badge: reservationCount.map(String.init), bg: Color(hex: "#FFE6CC")) { router.go(.reservationList) }
            MyPageItem(icon: "heart",             label: "찜한 가게",    badge: favoriteCount.map(String.init), bg: Color(hex: "#FFC4C4")) { router.go(.favorites) }
            MyPageItem(icon: "message",           label: "채팅",         badge: chatCount.map(String.init), bg: Color.brandGreenLight) { router.go(.chatList) }
            MyPageItem(icon: "gift",              label: "쿠폰함",       badge: "5장", bg: Color(hex: "#FFF1A8"))
        }
    }

    // 사장님: 등록 가게 표시 (1곳이면 상호명, 여러 곳이면 개수)
    private var myStoreBadge: String? {
        guard !myStores.isEmpty else { return nil }
        return myStores.count == 1 ? (myStores[0].name ?? "1곳") : "\(myStores.count)곳"
    }

    private var infoSection: some View {
        MyPageSection(title: "내 정보") {
            if authSession.isOwner {
                MyPageItem(icon: "building.2",    label: "내 가게",      badge: myStoreBadge, bg: Color(hex: "#FFD9A8")) { showMyStoreSheet = true }
            }
            MyPageItem(icon: "pawprint",          label: "우리 아이 프로필", bg: Color(hex: "#FFE6CC")) { router.go(.dogProfile) }
            MyPageItem(icon: "bell",              label: "알림 설정",    bg: Color.brandBlueLight)
            MyPageItem(icon: "gearshape",         label: "앱 설정",      bg: Color(hex: "#E8E0F0"))
        }
    }

    private func reloadMyStores() async {
        guard authSession.isOwner, let uid = authSession.userId else { return }
        myStores = (try? await APIClient.shared.fetchOwnerStores(userId: uid)) ?? []
    }

    private var supportSection: some View {
        MyPageSection(title: "고객지원") {
            MyPageItem(icon: "bubble.left",       label: "1:1 문의")
            MyPageItem(icon: "megaphone",         label: "공지사항")
            MyPageItem(icon: "rectangle.portrait.and.arrow.right", label: "로그아웃") { showLogoutConfirm = true }
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

// MARK: - ProfileEditSheet

struct ProfileEditSheet: View {
    @Environment(UserProfile.self) private var userProfile
    @Environment(AuthSession.self) private var authSession
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    sheetField("이름",   text: $name,    placeholder: "보호자 이름")
                    sheetField("연락처", text: $phone,   placeholder: "010-0000-0000")
                    sheetField("주소",   text: $address, placeholder: "서울시 강남구 …")

                    Button(action: save) {
                        HStack(spacing: 6) {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("저장하기").font(.system(size: 15, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.brandOrange)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                        .shadow(color: Color.brandOrange.opacity(0.7), radius: 9, x: 0, y: 8)
                    }
                    .disabled(isLoading)

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(Color.brandCream.ignoresSafeArea())
            .navigationTitle("프로필 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.brandBrown)
                    }
                }
            }
            .onAppear {
                name    = userProfile.name
                phone   = userProfile.phone
                address = userProfile.address
            }
        }
    }

    // 로그인 상태면 서버에도 저장, 아니면 로컬(UserDefaults)만
    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "이름을 입력해주세요."
            return
        }
        errorMessage = nil
        Task {
            if let uid = authSession.userId {
                isLoading = true
                defer { isLoading = false }
                do {
                    try await APIClient.shared.updateUser(userId: uid, nickname: trimmedName, phone: phone, address: address)
                } catch {
                    errorMessage = "저장에 실패했어요. 다시 시도해주세요."
                    return
                }
                authSession.updateNickname(trimmedName)
            }
            userProfile.name    = trimmedName
            userProfile.phone   = phone
            userProfile.address = address
            dismiss()
        }
    }

    private func sheetField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "#7a5635"))
            TextField(placeholder, text: text)
                .font(.system(size: 13))
                .foregroundStyle(Color.brandBrown)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        }
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
