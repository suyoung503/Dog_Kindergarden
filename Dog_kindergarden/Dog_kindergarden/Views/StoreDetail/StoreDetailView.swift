import SwiftUI

private let typeTagColor = Color(hex: "#FFE6CC")

struct StoreDetailView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession
    @Environment(\.openURL) private var openURL
    @State private var reviewService = ReviewService()
    @State private var blogService = NaverBlogService()
    @State private var showWriteSheet = false
    @State private var kakaoPlace: KakaoPlace? = nil   // 네이버·카카오로 보강한 전체 주소·전화
    @State private var storeDetail: StoreDetailResponse? = nil // DB 크롤링 보강 정보
    @State private var favoriteStoreId: Int? = nil     // nil이 아니면 찜한 가게 (해제용 store_id)
    @State private var isMyStore = false                // 사장님 계정: 이 가게가 내 가게로 등록됨
    @State private var showImageGallery = false
    @State private var selectedImageIndex = 0
    @State private var isStoreDetailLoading = true
    @State private var storeDetailLoadFailed = false
    @State private var externalOpenError: String?

    private var pin: MapPin? { router.selectedPin }
    private var storeName: String { pin?.name ?? router.selectedStore }
    private var storeKey: String { pin?.storeKey ?? router.selectedStore }
    private var isPartner: Bool { storeDetail?.isPartner == true }
    private var canBook: Bool { storeDetail?.canBook == true }
    private var canChat: Bool { storeDetail?.canChat == true }
    private var canReviewStore: Bool { storeDetail?.canReview == true }
    private var reviewTaskID: String { "\(storeKey)|\(canReviewStore)" }
    private var reviewEligibilityTaskID: String {
        "\(storeKey)|\(authSession.userId ?? 0)|\(canReviewStore)"
    }

    // 카카오 우선, 없으면 공공데이터(마스킹) 폴백
    private var displayAddress: String {
        if isPartner, let k = kakaoPlace, !k.best.isEmpty { return k.best }
        return pin?.address ?? ""
    }
    private var displayPhone: String {
        if isPartner, let k = kakaoPlace, !k.phone.isEmpty { return k.phone }
        return pin?.phone ?? ""
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    heroSection
                    titleCard
                    contactActionsSection
                    if isStoreDetailLoading {
                        capabilityLoadingSection
                    } else if storeDetailLoadFailed {
                        capabilityErrorSection
                    } else if isPartner {
                        partnerDetailSection
                    } else {
                        generalStoreSection
                    }
                    if canReviewStore {
                        petReviewSection
                    }
                    if isPartner {
                        blogSection       // 파트너 업체의 네이버 블로그 검색 결과
                    }
                    noticeSection         // 일반 안내(체크리스트)
                }
                .padding(.bottom, 80)
            }
            .background(Color.brandCream.ignoresSafeArea())
            .ignoresSafeArea(edges: .top)

            bottomBar
        }
        .task(id: reviewTaskID) {
            guard canReviewStore else {
                reviewService.clear()
                return
            }
            await reviewService.load(storeKey: storeKey)
        }
        .task(id: reviewEligibilityTaskID) {
            guard canReviewStore, let uid = authSession.userId else {
                reviewService.clearEligibility()
                return
            }
            await reviewService.loadEligibility(storeKey: storeKey, userId: uid)
        }
        .task(id: storeKey) {
            isStoreDetailLoading = true
            storeDetailLoadFailed = false
            do {
                storeDetail = try await APIClient.shared.fetchStoreDetail(storeKey: storeKey)
            } catch {
                storeDetail = nil
                storeDetailLoadFailed = true
            }
            isStoreDetailLoading = false
        }
        .task(id: storeKey) {
            // 찜 여부 확인 — 내 찜 목록에서 같은 store_key 찾기
            guard let uid = authSession.userId else { return }
            let list = (try? await APIClient.shared.fetchFavorites(userId: uid)) ?? []
            favoriteStoreId = list.first(where: { ($0.storeKey ?? "") == storeKey })?.storeId
        }
        .task(id: storeKey) {
            // 사장님 계정: 이 가게가 내 가게로 등록되어 있는지 확인
            guard authSession.isOwner, let uid = authSession.userId else { return }
            let mine = (try? await APIClient.shared.fetchOwnerStores(userId: uid)) ?? []
            isMyStore = mine.contains { ($0.storeKey ?? "") == storeKey }
        }
        .task(id: "\(storeKey)|\(isPartner)") {
            // 외부 API Secret은 Worker에만 두고, D1에 등록된 파트너의 storeKey만 보강한다.
            guard isPartner else {
                kakaoPlace = nil
                return
            }
            kakaoPlace = await StoreEnrichmentService.lookupPlace(storeKey: storeKey)
        }
        .task(id: "\(storeKey)|\(isPartner)") {
            // 네이버 블로그 후기 검색 (지역명 + 가게명)
            guard isPartner else {
                blogService.posts = []
                return
            }
            await blogService.load(storeKey: storeKey)
        }
        .sheet(isPresented: $showWriteSheet) {
            ReviewWriteSheet(storeName: storeName) { draft in
                guard let uid = authSession.userId,
                      reviewService.eligibility?.eligible == true else { return false }
                return await reviewService.submit(
                    storeKey: storeKey,
                    storeName: storeName,
                    userId: uid,
                    draft: draft
                )
            }
        }
        .fullScreenCover(isPresented: $showImageGallery) {
            StoreImageGalleryView(
                imageURLs: galleryImageUrls,
                selectedIndex: $selectedImageIndex
            )
        }
        .alert("연결할 수 없어요", isPresented: Binding(
            get: { externalOpenError != nil },
            set: { if !$0 { externalOpenError = nil } }
        )) {
            Button("확인", role: .cancel) { externalOpenError = nil }
        } message: {
            Text(externalOpenError ?? "잠시 후 다시 시도해주세요.")
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
                    Text("아직 이용 인증 리뷰가 없어요")
                        .font(.system(size: 12)).foregroundStyle(Color.brandBrownMid)
                }

                // 리뷰 목록
                ForEach(reviewService.reviews.prefix(5)) { r in
                    reviewRow(r)
                }

                // 작성 버튼
                Button(action: { showWriteSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: canWriteReview ? "checkmark.seal.fill" : "lock.fill")
                            .font(.system(size: 13))
                        Text(reviewButtonTitle).font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(canWriteReview ? Color.brandOrange : Color.brandBrownLight)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(canWriteReview ? Color(hex: "#FFF1DC") : Color.white.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                }
                .disabled(!canWriteReview)

                Text(reviewEligibilityMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brandBrownMid)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var canWriteReview: Bool {
        canReviewStore && authSession.userId != nil && reviewService.eligibility?.eligible == true
    }

    private var reviewButtonTitle: String {
        if reviewService.isCheckingEligibility { return "이용 내역 확인 중…" }
        return canWriteReview ? "이용 인증 리뷰 쓰기" : "리뷰 작성 잠김"
    }

    private var reviewEligibilityMessage: String {
        guard authSession.userId != nil else {
            return "로그인 후 이용 내역이 확인된 보호자만 작성할 수 있어요"
        }
        if reviewService.isCheckingEligibility { return "확정된 이용 완료 내역을 확인하고 있어요" }
        return reviewService.eligibility?.guidanceMessage ?? "리뷰 작성 자격을 불러오지 못했어요"
    }

    // 절반 이상 보호자가 동의한 태그만 노출
    private func confirmedTags(_ s: ReviewSummary) -> [String] {
        let half = max(1, s.count / 2)
        var tags: [String] = []
        if (s.cctv ?? 0) >= half { tags.append("CCTV") }
        if (s.pickup ?? 0) >= half { tags.append("픽업") }
        if (s.large_dog ?? 0) >= half { tags.append("대형견 OK") }
        if (s.separation_care ?? 0) >= half { tags.append("분리불안 케어") }
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
                if r.verified == 1 {
                    Text("이용 인증")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: "#2c6b4a"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.brandGreenLight)
                        .clipShape(Capsule())
                }
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
            if let imageURL = representativeImageUrl, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        heroGradient
                    }
                }
                .frame(height: 220)
                .clipped()
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.35), .clear],
                                   startPoint: .bottom, endPoint: .top)
                )
                .contentShape(Rectangle())
                .onTapGesture { openImageGallery(at: 0) }
            } else {
                heroGradient
            }

            HStack {
                Button(action: router.back) {
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "chevron.left").foregroundStyle(Color.brandBrown))
                }
                Spacer()
                HStack(spacing: 8) {
                    ShareLink(item: shareText) {
                        heroButton(icon: "square.and.arrow.up")
                    }
                    .accessibilityLabel("가게 정보 공유")
                    Button(action: toggleFavorite) {
                        heroButton(
                            icon: favoriteStoreId != nil ? "heart.fill" : "heart",
                            tint: favoriteStoreId != nil ? Color.brandOrange : Color.brandBrown
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 52)
        }
        .frame(height: 220)
    }

    private var heroGradient: some View {
        LinearGradient(colors: defaultHeroColors,
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(height: 220)
            .overlay(
                EmojiIcon(emoji: defaultStoreEmoji, size: 64)
                    .opacity(0.9)
            )
    }

    private var defaultStoreEmoji: String {
        let type = pin?.type ?? ""
        if type.contains("호텔") && type.contains("유치원") { return "🐾" }
        return type.contains("호텔") ? "🏨" : "🏠"
    }

    private var defaultHeroColors: [Color] {
        let type = pin?.type ?? ""
        if type.contains("호텔") && type.contains("유치원") {
            return [Color.brandGreenLight, Color(hex: "#FFE6CC")]
        }
        return type.contains("호텔")
            ? [Color(hex: "#FFE6CC"), Color.brandOrange]
            : [Color.brandGreenLight, Color(hex: "#F6C978")]
    }

    private func heroButton(icon: String, tint: Color = Color.brandBrown) -> some View {
        Circle()
            .fill(.white.opacity(0.9))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint))
    }

    private var shareText: String {
        [storeName, displayAddress, displayPhone]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // 찜 토글 — 추가는 성공 후 채움, 해제는 낙관적으로 비우고 실패 시 되돌림
    private func toggleFavorite() {
        guard let uid = authSession.userId else { return }
        Task {
            if let sid = favoriteStoreId {
                favoriteStoreId = nil
                do { try await APIClient.shared.removeFavorite(userId: uid, storeId: sid) }
                catch { favoriteStoreId = sid }
            } else {
                guard let p = pin else { return }
                let response = try? await APIClient.shared.addFavorite(
                    userId: uid,
                    storeKey: storeKey,
                    storeName: storeName,
                    address: displayAddress,
                    phone: displayPhone,
                    storeType: p.type,
                    latitude: p.latitude,
                    longitude: p.longitude
                )
                favoriteStoreId = response?.storeId
            }
        }
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
                    if isPartner {
                        Text("맡겨멍 파트너")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.brandOrange)
                            .clipShape(Capsule())
                    }
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
                // 사장님 계정: 마이페이지 '내 가게'에서 등록한 가게면 뱃지 표시
                if authSession.isOwner && isMyStore {
                    Label("내 가게", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "#2c6b4a"))
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

    // MARK: - 파트너 상세 / 일반 업체 안내

    private var capabilityLoadingSection: some View {
        sectionWrapper(title: "이용 안내") {
            HStack(spacing: 10) {
                ProgressView().tint(Color.brandOrange)
                Text("예약 지원 여부를 확인하고 있어요")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandBrownMid)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
    }

    private var capabilityErrorSection: some View {
        sectionWrapper(title: "이용 안내") {
            VStack(alignment: .leading, spacing: 6) {
                Label("업체 정보를 불러오지 못했어요", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Text("안전을 위해 예약과 채팅을 잠시 사용할 수 없습니다. 잠시 후 다시 열어주세요.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandBrownMid)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
    }

    private var partnerDetailSection: some View {
        sectionWrapper(title: "상세 정보") {
            VStack(alignment: .leading, spacing: 12) {
                if !partnerTags.isEmpty {
                    FlowTags(tags: partnerTags)
                }

                detailTextCard(
                    title: "영업시간",
                    value: storeDetail?.openTime,
                    fallback: "영업시간은 업체에 문의해주세요."
                )

                detailTextCard(
                    title: "가격",
                    value: storeDetail?.priceInfo,
                    fallback: "가격은 업체마다 다릅니다. 예약 확정 전 업체와 확인해주세요."
                )

                if !galleryImageUrls.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(galleryImageUrls.enumerated()), id: \.offset) { index, raw in
                                if let url = URL(string: raw) {
                                    Button {
                                        openImageGallery(at: index)
                                    } label: {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image.resizable().scaledToFill()
                                            default:
                                                Color(hex: "#FFE6CC")
                                            }
                                        }
                                        .frame(width: 88, height: 88)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("가게 이미지 \(index + 1) 크게 보기")
                                }
                            }
                        }
                    }
                }

                Text("가격과 운영 정보는 예약 확정 전에 업체와 다시 확인해주세요.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.brandBrownLight)
            }
        }
    }

    private var generalStoreSection: some View {
        sectionWrapper(title: "이용 안내") {
            VStack(alignment: .leading, spacing: 10) {
                Label("현재 맡겨멍 예약을 지원하지 않는 업체입니다", systemImage: "info.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Text("영업시간과 가격은 업체에 직접 문의해주세요. 채팅·예약·알림장·앱 내부 리뷰는 맡겨멍 파트너 업체에서만 제공됩니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandBrownMid)
                    .fixedSize(horizontal: false, vertical: true)

            }
            .padding(14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        }
    }

    private var contactActionsSection: some View {
        sectionWrapper(title: "연락·위치") {
            HStack(spacing: 8) {
                Button {
                    guard let phoneURL else {
                        externalOpenError = "이 업체는 연결 가능한 전화번호를 제공하지 않았어요."
                        return
                    }
                    openExternalURL(phoneURL, failureMessage: "이 기기에서 전화 앱을 열 수 없어요.")
                } label: {
                    contactButton(
                        phoneURL == nil ? "전화번호 없음" : "전화하기",
                        icon: phoneURL == nil ? "phone.down.fill" : "phone.fill",
                        enabled: phoneURL != nil
                    )
                }

                Button {
                    guard let externalMapURL else {
                        externalOpenError = "지도에서 검색할 가게 정보가 없어요."
                        return
                    }
                    openExternalURL(externalMapURL, failureMessage: "지도 페이지를 열 수 없어요.")
                } label: {
                    contactButton("지도에서 보기", icon: "map.fill", enabled: externalMapURL != nil)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var partnerTags: [String] {
        var tags: [String] = []
        if storeDetail?.largeDog == 1 { tags.append("대형견 가능") }
        if storeDetail?.pickup == 1 { tags.append("픽업 가능") }
        if storeDetail?.playground == 1 { tags.append("운동장 있음") }
        return tags
    }

    private func detailTextCard(title: String, value: String?, fallback: String) -> some View {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text((normalized?.isEmpty == false ? normalized.map(formattedDetailText) : nil) ?? fallback)
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    private func contactButton(_ title: String, icon: String, enabled: Bool = true) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(enabled ? Color.brandOrange : Color.brandBrownLight)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(enabled ? Color(hex: "#FFF1DC") : Color.brandCream)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var phoneURL: URL? {
        let raw = displayPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.contains("*"), !raw.contains("X"), !raw.contains("x") else { return nil }
        let digits = raw.filter(\.isNumber)
        guard (8...15).contains(digits.count) else { return nil }
        let normalized = raw.hasPrefix("+") ? "+\(digits)" : digits
        return URL(string: "tel:\(normalized)")
    }

    private var externalMapURL: URL? {
        if let raw = kakaoPlace?.placeURL, !raw.isEmpty, let url = URL(string: raw) { return url }
        let query = [storeName, displayAddress]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://map.kakao.com/link/search/\(encoded)")
    }

    private func openExternalURL(_ url: URL, failureMessage: String) {
        openURL(url) { accepted in
            if !accepted { externalOpenError = failureMessage }
        }
    }

    private var galleryImageUrls: [String] {
        let detailImages = (storeDetail?.images ?? [])
            .sorted {
                if ($0.sortOrder ?? 0) == ($1.sortOrder ?? 0) {
                    return ($0.imageId ?? 0) < ($1.imageId ?? 0)
                }
                return ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0)
            }
            .compactMap { $0.imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        for raw in [storeDetail?.imageUrl ?? ""] + detailImages where !raw.isEmpty {
            if !result.contains(raw) { result.append(raw) }
        }
        return result
    }

    private var representativeImageUrl: String? {
        let storedRepresentative = storeDetail?.imageUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedRepresentative, !storedRepresentative.isEmpty {
            return storedRepresentative
        }
        return galleryImageUrls.first
    }

    private func openImageGallery(at index: Int) {
        guard galleryImageUrls.indices.contains(index) else { return }
        selectedImageIndex = index
        showImageGallery = true
    }

    private func formattedDetailText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: " / ", with: "\n")
    }

    // MARK: - 블로그 후기 (네이버)

    private var blogSection: some View {
        sectionWrapper(title: "블로그 후기") {
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

    // MARK: - Notice (업체별 정책을 확인하도록 안내하는 공통 체크리스트)

    private var noticeSection: some View {
        sectionWrapper(title: "맡기기 전 체크리스트") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["예방접종 확인 서류가 필요한지 문의해주세요","성향과 건강 상태를 미리 알려주세요","사료·준비물 제공 범위를 확인해주세요","가격과 취소 규정을 업체에 확인해주세요"], id: \.self) { t in
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
        Group {
            if isStoreDetailLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(Color.brandOrange)
                    Text("예약 지원 여부 확인 중")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.brandBrownMid)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            } else if canBook || canChat {
                HStack(spacing: 8) {
                    Button(action: openChat) {
                        EmojiIcon(emoji: "💬", size: 22)
                            .frame(width: 52, height: 52)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
                    }
                    .disabled(!canChat)
                    Button(action: { if canBook { router.go(.booking) } }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("예약하기").font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(canBook ? Color.brandOrange : Color.brandBrownLight)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                        .shadow(color: canBook ? Color.brandOrange.opacity(0.7) : .clear, radius: 9, x: 0, y: 8)
                    }
                    .disabled(!canBook)
                }
            } else {
                Label("일반 업체 · 예약과 채팅은 지원하지 않아요", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.brandBrownMid)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
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
        guard canChat else { return }
        let name = storeName
        let key = storeKey
        Task {
            guard let uid = authSession.userId else { return }
            let rid = await ChatService.lookup(userId: uid, storeKey: key)
            router.selectedChat = name
            router.selectedRoomId = rid
            router.chatRoomAsOwner = false
            router.chatRoomAvatar = (pin?.type == "호텔") ? "🏨" : "🏠"
            router.go(.chatRoom)
        }
    }

    // MARK: - Helper

    private func sectionWrapper<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EmojiTitle(title: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
