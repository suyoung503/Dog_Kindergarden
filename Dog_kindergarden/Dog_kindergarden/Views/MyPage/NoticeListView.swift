import SwiftUI

// 공지사항 목록 — 개발자가 DB에 직접 입력한 공지를 최신순으로 표시
struct NoticeListView: View {
    @Environment(AppRouter.self) private var router

    @State private var notices: [Notice] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navBar
                if isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if loadFailed {
                    errorState
                } else if notices.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(notices) { notice in
                            noticeCard(notice)
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
            Text("공지사항")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
    }

    // MARK: - Empty / Error

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "📢", size: 48)
            Text("등록된 공지사항이 없습니다")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .padding(.top, 100)
    }

    private var errorState: some View {
        VStack(spacing: 10) {
            EmojiIcon(emoji: "⚠️", size: 48)
            Text("공지사항을 불러오지 못했어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Button(action: { Task { await load() } }) {
                Text("다시 시도")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.brandOrange)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 100)
    }

    // MARK: - Card

    private func noticeCard(_ notice: Notice) -> some View {
        Button(action: { open(notice) }) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                        .multilineTextAlignment(.leading)
                    Text(notice.createdAt)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.brandBrownMid)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrownLight)
            }
            .padding(14)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            notices = try await APIClient.shared.fetchNotices()
        } catch {
            loadFailed = true
        }
    }

    private func open(_ notice: Notice) {
        router.selectedNotice = notice
        router.go(.noticeDetail)
    }
}
