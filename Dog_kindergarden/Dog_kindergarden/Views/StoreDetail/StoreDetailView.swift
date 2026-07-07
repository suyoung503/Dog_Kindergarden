import SwiftUI

private let typeTagColor = Color(hex: "#FFE6CC")

struct StoreDetailView: View {
    @Environment(AppRouter.self) private var router
    @Environment(UserProfile.self) private var userProfile
    @Environment(AuthSession.self) private var authSession
    @State private var reviewService = ReviewService()
    @State private var blogService = NaverBlogService()
    @State private var showWriteSheet = false
    @State private var kakaoPlace: KakaoPlace? = nil   // 카카오로 보강한 전체 주소·전화

    private var pin: MapPin? { router.selectedPin }
    private var storeName: String { pin?.name ?? router.selectedStore }
    private var storeKey: String { pin?.storeKey ?? router.selectedStore }

    // 카카오 우선, 없으면 공공데이터(마스킹) 폴백
    private var displayAddress: String {
        if let k = kakaoPlace, !k.best.isEmpty { return k.best }
        return pin?.address ?? ""
    }
    private var displayPhone: String {
        if let k = kakaoPlace, !k.phone.isEmpty { return k.phone }
        return pin?.phone ?? ""
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                    titleCard
                    petReviewSection      // 🐾 펫 특화 리뷰 (핵심 가치, 실데이터)
                    blogSection           // 📝 네이버 블로그 후기
                    noticeSection         // 일반 안내(체크리스트)
                }
                .padding(.bottom, 80)
            }
            .background(Color.brandCream.ignoresSafeArea())
            .ignoresSafeArea(edges: .top)

            bottomBar
        }
        .task(id: storeKey) { await reviewService.load(storeKey: storeKey) }
        .task(id: storeKey) {
            // 카카오 로컬 검색으로 마스킹된 주소(***)를 전체 주소로 보강
            if let p = pin {
                kakaoPlace = await KakaoLocalService.lookup(name: p.name, lat: p.latitude, lon: p.longitude)
            }
        }
        .task(id: storeKey) {
            // 네이버 블로그 후기 검색 (지역명 + 가게명)
            let region = (pin?.address ?? "").split(separator: " ").prefix(2).joined(separator: " ")
            await blogService.load(storeName: storeName, region: region)
        }
        .sheet(isPresented: $showWriteSheet) {
            ReviewWriteSheet(storeName: storeName) { draft in
                await reviewService.submit(
                    storeKey: storeKey,
                    storeName: storeName,
                    userName: userProfile.name,
                    draft: draft
                )
            }
        }
    }

    // MARK: - 펫 특화 리뷰

    private var petReviewSection: some View {
        sectionWrapper(title: "🐾 우리 아이 리뷰") {
            VStack(alignment: .leading, spacing: 12) {
                // 보호자들이 인증한 태그 (= 필터 데이터)
                if let s = reviewService.summary, s.count > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Color.brandOrange)
                        Text(String(format: "%.1f", s.avg_rating ?? 0))
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.brandBrown)
                        Text("· 보호자 \(s.count)명").font(.system(size: 12)).foregroundStyle(Color.brandBrownMid)
                    }
                    FlowTags(tags: confirmedTags(s))
                } else {
                    Text("아직 리뷰가 없어요. 첫 보호자가 되어주세요 🐶")
                        .font(.system(size: 12)).foregroundStyle(Color.brandBrownMid)
                }

                // 리뷰 목록
                ForEach(reviewService.reviews.prefix(5)) { r in
                    reviewRow(r)
                }

                // 작성 버튼
                Button(action: { showWriteSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil").font(.system(size: 13))
                        Text("리뷰 쓰기").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Color.brandOrange)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Color(hex: "#FFF1DC"))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                }
            }
        }
    }

    // 절반 이상 보호자가 동의한 태그만 노출
    private func confirmedTags(_ s: ReviewSummary) -> [String] {
        let half = max(1, s.count / 2)
        var tags: [String] = []
        if (s.cctv ?? 0) >= half { tags.append("📹 CCTV") }
        if (s.pickup ?? 0) >= half { tags.append("🚗 픽업") }
        if (s.large_dog ?? 0) >= half { tags.append("🐕 대형견 OK") }
        if (s.separation_care ?? 0) >= half { tags.append("💛 분리불안 케어") }
        return tags
    }

    private func reviewRow(_ r: PetReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: Double(i) < r.rating ? "star.fill" : "star")
                        .font(.system(size: 9)).foregroundStyle(Color.brandOrange)
                }
                Text(r.user_name ?? "익명").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.brandBrownMid)
            }
            if let c = r.content, !c.isEmpty {
                Text(c).font(.system(size: 12)).foregroundStyle(Color.brandBrown)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .top) {
            // 실제 가게 사진이 없으므로 브랜드 그라데이션 (사진인 척하지 않음)
            LinearGradient(colors: [Color(hex: "#FFE6CC"), Color.brandOrange],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 220)
                .overlay(
                    EmojiIcon(emoji: pin?.type == "호텔" ? "🏨" : "🏠", size: 64)
                        .opacity(0.9)
                )
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.25), .clear],
                                   startPoint: .bottom, endPoint: .top)
                )

            HStack {
                Button(action: router.back) {
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "chevron.left").foregroundStyle(Color.brandBrown))
                }
                Spacer()
                HStack(spacing: 8) {
                    heroButton(icon: "square.and.arrow.up")
                    heroButton(icon: "heart.fill", tint: Color.brandOrange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)
        }
        .frame(height: 220)
    }

    private func heroButton(icon: String, tint: Color = Color.brandBrown) -> some View {
        Circle()
            .fill(.white.opacity(0.9))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint))
    }

    // MARK: - Title card

    private var titleCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "#FFE6CC"))
                    .frame(width: 56, height: 56)
                EmojiIcon(emoji: "🐶", size: 28)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(storeName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                    if let st = pin?.status, !st.isEmpty {
                        Text(st)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: "#2c6b4a"))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.brandGreenLight)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                // 리뷰 평점 (실데이터)
                if let s = reviewService.summary, s.count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Color.brandOrange)
                        Text(String(format: "%.1f", s.avg_rating ?? 0))
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandBrown)
                        Text("(리뷰 \(s.count))").font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
                    }
                }
                // 주소 (카카오 보강 우선)
                if !displayAddress.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin").font(.system(size: 10)).foregroundStyle(Color.brandBrownMid)
                        Text(displayAddress).font(.system(size: 11)).foregroundStyle(Color.brandBrownMid)
                    }
                }
                // 유형 태그
                Text(pin?.type ?? "유치원")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.brandBrown)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(typeTagColor)
                    .clipShape(Capsule())
                    .padding(.top, 4)
                // 전화 (카카오 보강 우선)
                if !displayPhone.isEmpty {
                    Label(displayPhone, systemImage: "phone")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.brandBrown)
                        .labelStyle(IconAndText(iconColor: Color.brandOrange))
                        .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        .overlay(RoundedRectangle(cornerRadius: Radius.pill).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .shadow(color: Color.brandBrown.opacity(0.12), radius: 12, x: 0, y: 10)
        .padding(.horizontal, 16)
        .offset(y: -28)
    }

    // MARK: - 블로그 후기 (네이버)

    private var blogSection: some View {
        sectionWrapper(title: "📝 블로그 후기") {
            VStack(alignment: .leading, spacing: 8) {
                if blogService.posts.isEmpty {
                    Text(blogService.isLoading ? "블로그 후기를 찾는 중…" : "관련 블로그 글을 찾지 못했어요.")
                        .font(.system(size: 12)).foregroundStyle(Color.brandBrownMid)
                } else {
                    ForEach(blogService.posts) { post in
                        if let url = URL(string: post.link) {
                            Link(destination: url) { blogRow(post) }
                        } else {
                            blogRow(post)
                        }
                    }
                    Text("네이버 블로그 검색 결과 · 광고성 글이 포함될 수 있어요")
                        .font(.system(size: 9)).foregroundStyle(Color.brandBrownLight)
                }
            }
        }
    }

    private func blogRow(_ post: BlogPost) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(post.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.brandBrown)
                .lineLimit(1)
            Text(post.snippet)
                .font(.system(size: 11))
                .foregroundStyle(Color.brandBrownMid)
                .lineLimit(2)
            HStack(spacing: 4) {
                Text(post.blogger).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.brandOrange)
                if !post.date.isEmpty {
                    Text("· \(post.date)").font(.system(size: 10)).foregroundStyle(Color.brandBrownLight)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square").font(.system(size: 11)).foregroundStyle(Color.brandBrownLight)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    // MARK: - Notice (일반 안내 — 특정 가게 주장이 아니라 보편적 체크리스트)

    private var noticeSection: some View {
        sectionWrapper(title: "맡기기 전 체크리스트") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["광견병 접종 증명서 필수","공격성이 있는 경우 사전 상담","사료는 직접 준비해주세요"], id: \.self) { t in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.brandOrange)
                            .padding(.top, 1)
                        Text(t).font(.system(size: 12)).foregroundStyle(Color(hex: "#7a5635"))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#FFF1DC"))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color(hex: "#F5C98B"), lineWidth: 1))
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button(action: openChat) {
                Text("💬")
                    .font(.system(size: 18))
                    .frame(width: 52, height: 52)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
            }
            Button(action: { router.go(.booking) }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("예약하기").font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.brandOrange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                .shadow(color: Color.brandOrange.opacity(0.7), radius: 9, x: 0, y: 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.white)
        .overlay(alignment: .top) {
            Divider().foregroundStyle(Color.brandBeigeBorder)
        }
    }

    // 이 가게와 문의 채팅 — 기존 방 있으면 그 방으로, 없으면 작성 모드로 진입
    private func openChat() {
        let name = storeName
        let key = storeKey
        Task {
            let rid = await ChatService.lookup(userId: authSession.userId ?? 1, storeKey: key)
            router.selectedChat = name
            router.selectedRoomId = rid
            router.go(.chatRoom)
        }
    }

    // MARK: - Helper

    private func sectionWrapper<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EmojiTitle(title: title)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

// MARK: - Custom LabelStyle

private struct IconAndText: LabelStyle {
    let iconColor: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(iconColor)
            configuration.title
        }
    }
}
