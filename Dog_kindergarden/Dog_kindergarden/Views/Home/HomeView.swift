import SwiftUI


struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BoardingStore.self) private var boarding
    @Environment(TagStore.self) private var tagStore
    @Environment(UserProfile.self) private var userProfile
    @State private var searchText = ""
    @State private var showFAB = false
    @State private var activeFilter: ReviewTag? = nil    // 리뷰 태그 필터
    @State private var activeType: String? = nil         // "호텔" | "유치원" 필터
    // 현재 지도에 보이는 범위 — 카메라 이동/줌이 멈출 때 갱신
    @State private var mapBounds: MapBounds? = nil

    // 수도권 = 서울 + 경기(인천 포함). bounds 확정 전 초기 폴백에만 사용
    private let metroKeys = ["서울", "경기"]
    // 화면 영역 안 가게가 많을 때 표시 상한 (중심에서 가까운 순)
    private let maxVisiblePins = 50
    // 초기 지도 위치 — 서울+경기가 한 화면에 들어오도록
    private let metroCenter = (lat: 37.45, lon: 127.0)
    private let metroZoom = 8

    // 현재 화면 범위 + (유형·검색·리뷰태그) 필터를 전국 데이터에 적용
    private var visiblePins: [MapPin] {
        var result = boarding.pins
        if let t = activeType {
            result = result.filter { $0.type == t }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter { $0.name.contains(q) || $0.address.contains(q) }
        }
        if let f = activeFilter {
            result = result.filter { tagStore.tagsByKey[$0.storeKey]?.has(f) == true }
        }
        guard let b = mapBounds else {
            // 초기(카메라 정착 전): 수도권만 폴백 표시
            return result.filter { metroKeys.contains($0.province) }
        }
        result = result.filter { b.contains(lat: $0.latitude, lon: $0.longitude) }
        // 화면 중심에서 가까운 순으로 상한만큼만
        if result.count > maxVisiblePins {
            result.sort {
                hypot($0.latitude - b.centerLat, $0.longitude - b.centerLon)
                    < hypot($1.latitude - b.centerLat, $1.longitude - b.centerLon)
            }
            result = Array(result.prefix(maxVisiblePins))
        }
        return result
    }

    private let quickFilters: [(emoji: String, text: String, bg: Color)] = [
        ("🏨", "호텔",  Color(hex: "#FFE6CC")),
        ("🏠", "유치원", Color.brandGreenLight),
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    headerRow
                    searchBar
                    quickChips
                    mapSection
                    recentSection
                }
                .padding(.bottom, 96)
            }
            .background(Color.brandCream.ignoresSafeArea())

            FloatingActionButton(isOpen: $showFAB)
                .padding(.trailing, 20)
                .padding(.bottom, 28)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Button(action: { router.go(.myPage) }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#FFE6CC"))
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Color.brandOrange, lineWidth: 2))
                        Image(router.userDogAvatar).resizable().scaledToFit().frame(width: 26, height: 26)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text("\(userProfile.name)님")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.brandBrown)
                            EmojiIcon(emoji: "🐾", size: 14)
                        }
                        Text("오늘도 멍멍이 케어를 찾아볼까요?")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.brandBrownMid)
                    }
                }
            }
            Spacer()
            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                    Image(systemName: "bell")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.brandBrown)
                }
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .padding(.top, 7)
                        .padding(.trailing, 7)
                }
                .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, UIApplication.safeAreaTop + 12)
        .padding(.bottom, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.brandBrownLight)
                .font(.system(size: 14))
            TextField("지역, 가게 이름으로 검색", text: $searchText)
                .font(.system(size: 13))
                .foregroundStyle(Color.brandBrown)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Quick chips

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickFilters, id: \.text) { f in
                    let on = activeType == f.text
                    Button(action: {
                        activeType = on ? nil : f.text
                    }) {
                        HStack(spacing: 5) {
                            EmojiIcon(emoji: f.emoji, size: 15)
                            Text(f.text)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(on ? .white : Color.brandBrown)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(on ? Color.brandOrange : f.bg)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 12)
    }

    // MARK: - Map

    private var mapSection: some View {
        koreaMapCard
            .padding(.top, 16)
    }

    private var koreaMapCard: some View {
        ZStack(alignment: .topLeading) {
            // 항상 이동·줌 가능한 지도 — 화면에 보이는 범위의 가게를 핀으로 표시
            KakaoMapContainer(
                pins: visiblePins,
                centerLat: metroCenter.lat,
                centerLon: metroCenter.lon,
                zoomLevel: metroZoom,
                onPinTapped: { pin in
                    router.selectedStore = pin.name
                    router.selectedPin = pin
                    // 최근 본 목록 갱신 — 중복 제거 후 맨 앞 삽입, 최대 5개
                    router.recentPins.removeAll { $0.storeKey == pin.storeKey }
                    router.recentPins.insert(pin, at: 0)
                    if router.recentPins.count > 5 { router.recentPins.removeLast() }
                    router.go(.storeDetail)
                },
                onCameraStopped: { bounds in mapBounds = bounds }
            )
            // 카메라 위치 유지를 위해 id 고정 — 핀 갱신은 updateUIViewController가 처리
            .id("viewportMap")

            // 리뷰 태그 필터 칩
            filterChips
                .padding(12)
        }
        .frame(height: 490)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .shadow(color: Color.brandBrown.opacity(0.12), radius: 10, x: 0, y: 10)
        .padding(.horizontal, 20)
    }

    // 보호자 리뷰 태그로 가게 필터
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ReviewTag.allCases) { tag in
                    let on = activeFilter == tag
                    Button(action: { activeFilter = on ? nil : tag }) {
                        Text(tag.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(on ? .white : Color.brandBrown)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Color.brandOrange : .white)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
                    }
                }
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("최근 본 케어")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.brandBrown)
                .padding(.horizontal, 20)

            if router.recentPins.isEmpty {
                Text("핀을 눌러 가게를 확인하면 여기에 표시돼요")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandBrownMid)
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(router.recentPins) { pin in
                            Button(action: {
                                router.selectedStore = pin.name
                                router.selectedPin = pin
                                router.go(.storeDetail)
                            }) {
                                recentPinCard(pin)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 20)
    }

    private func recentPinCard(_ pin: MapPin) -> some View {
        let isHotel = pin.type == "호텔"
        let bg: Color = isHotel ? Color(hex: "#FFE6CC") : Color.brandGreenLight
        let areaText = pin.address
            .components(separatedBy: " ")
            .prefix(2)
            .joined(separator: " ")

        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(bg)
                    .frame(height: 64)
                EmojiIcon(emoji: isHotel ? "🏨" : "🏠", size: 34)
                Text(pin.type)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(isHotel ? Color.brandOrange : Color.brandGreen)
                    .clipShape(Capsule())
                    .padding(5)
            }
            .padding(.bottom, 8)
            Text(pin.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.brandBrown)
                .lineLimit(1)
            Text(areaText.isEmpty ? pin.province : areaText)
                .font(.system(size: 10))
                .foregroundStyle(Color.brandBrownMid)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 140)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }
}

// MARK: - FloatingActionButton

private struct FABItem {
    let icon: String
    let label: String
    let bg: Color
    let destination: AppScreen
}

private let fabItems: [FABItem] = [
    FABItem(icon: "person",          label: "강아지 프로필", bg: Color(hex: "#FFE6CC"), destination: .dogProfile),
    FABItem(icon: "message",         label: "채팅",         bg: Color.brandGreenLight, destination: .chatList),
    FABItem(icon: "calendar",        label: "예약 내역",    bg: Color(hex: "#FFF1A8"), destination: .reservationList),
    FABItem(icon: "gearshape",       label: "설정",         bg: Color.brandBlueLight,  destination: .myPage),
]

struct FloatingActionButton: View {
    @Environment(AppRouter.self) private var router
    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isOpen {
                ForEach(fabItems, id: \.label) { item in
                    Button(action: {
                        isOpen = false
                        router.go(item.destination)
                    }) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().fill(item.bg).frame(width: 28, height: 28)
                                Image(systemName: item.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.brandBrown)
                            }
                            Text(item.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.brandBrown)
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 16)
                        .frame(height: 40)
                        .background(.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.brandBeigeBorder, lineWidth: 1))
                        .shadow(color: Color.brandBrown.opacity(0.15), radius: 7, x: 0, y: 6)
                    }
                }
            }
            Button(action: { withAnimation(.spring(response: 0.3)) { isOpen.toggle() } }) {
                ZStack {
                    Circle()
                        .fill(Color.brandOrange)
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.brandOrange.opacity(0.7), radius: 12, x: 0, y: 12)
                    Image(systemName: isOpen ? "xmark" : "pawprint.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(hex: "#FFF8EF"))
                }
            }
        }
    }
}
