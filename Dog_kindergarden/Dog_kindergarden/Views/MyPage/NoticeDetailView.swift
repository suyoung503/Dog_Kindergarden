import SwiftUI

// 공지사항 상세 — 목록에서 넘어온 id로 본문을 다시 조회
struct NoticeDetailView: View {
    @Environment(AppRouter.self) private var router

    @State private var notice: Notice?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navBar
                if isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if loadFailed || notice == nil {
                    errorState
                } else if let notice {
                    content(notice)
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
            Text("공지사항")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    // MARK: - Content / Error

    private func content(_ notice: Notice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(notice.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text(notice.createdAt)
                .font(.system(size: 11))
                .foregroundStyle(Color.brandBrownMid)
            Divider()
            Text(notice.body ?? "")
                .font(.system(size: 14))
                .foregroundStyle(Color.brandBrown)
                .multilineTextAlignment(.leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var errorState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "⚠️", size: 48)
            Text("공지사항을 불러오지 못했어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Button(action: router.back) {
                Text("목록으로")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.brandOrange)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 100)
    }

    // MARK: - Actions

    private func load() async {
        guard let id = router.selectedNotice?.id else {
            loadFailed = true
            isLoading = false
            return
        }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            notice = try await APIClient.shared.fetchNotice(id: id)
        } catch {
            loadFailed = true
        }
    }
}
