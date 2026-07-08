import SwiftUI

// 찜한 가게 목록 — 가게 상세의 하트로 저장한 가게를 서버(favorites)에서 불러와 표시
struct FavoritesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession

    @State private var favorites: [FavoriteStoreResponse] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navBar
                if isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if favorites.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(favorites, id: \.storeId) { favorite in
                            favoriteCard(favorite)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task { await load() }
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
            Text("찜한 가게")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "🐶", size: 48)
            Text("아직 찜한 가게가 없어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text("가게 상세에서 하트를 누르면 여기에 모여요")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
        }
        .padding(.top, 100)
    }

    // MARK: - Card

    private func favoriteCard(_ favorite: FavoriteStoreResponse) -> some View {
        let isHotel = (favorite.storeType ?? "") == "호텔"
        return Button(action: { open(favorite) }) {
            HStack(alignment: .top, spacing: 12) {
                // 가게 프로필 (실제 사진이 없으므로 타입별 이모지 아이콘)
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isHotel ? Color(hex: "#FFE6CC") : Color.brandGreenLight)
                        .frame(width: 56, height: 56)
                    EmojiIcon(emoji: isHotel ? "🏨" : "🏠", size: 28)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(favorite.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                        .multilineTextAlignment(.leading)
                    if let address = favorite.address, !address.isEmpty {
                        Text(address)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.brandBrownMid)
                            .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 6) {
                        Text(favorite.storeType ?? "유치원")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.brandBrown)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(isHotel ? Color(hex: "#FFE6CC") : Color.brandGreenLight)
                            .clipShape(Capsule())
                        if let phone = favorite.phone, !phone.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "phone").font(.system(size: 9)).foregroundStyle(Color.brandOrange)
                                Text(phone).font(.system(size: 11)).foregroundStyle(Color.brandBrown)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer()
                Button(action: { remove(favorite) }) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.brandOrange)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func load() async {
        defer { isLoading = false }
        guard let uid = authSession.userId else { return }
        favorites = (try? await APIClient.shared.fetchFavorites(userId: uid)) ?? []
    }

    // 저장된 가게로 상세화면 이동 — 원본 store_key를 유지해 리뷰·찜 상태가 이어지게 함
    private func open(_ favorite: FavoriteStoreResponse) {
        router.selectedPin = MapPin(
            name: favorite.name,
            type: favorite.storeType ?? "유치원",
            rating: 0,
            distance: "",
            latitude: favorite.latitude ?? 0,
            longitude: favorite.longitude ?? 0,
            province: "",
            address: favorite.address ?? "",
            phone: favorite.phone ?? "",
            storeKeyOverride: favorite.storeKey
        )
        router.go(.storeDetail)
    }

    // 낙관적 해제 — 실패 시 목록 복원
    private func remove(_ favorite: FavoriteStoreResponse) {
        guard let uid = authSession.userId else { return }
        let backup = favorites
        favorites.removeAll { $0.storeId == favorite.storeId }
        Task {
            do { try await APIClient.shared.removeFavorite(userId: uid, storeId: favorite.storeId) }
            catch { favorites = backup }
        }
    }
}
