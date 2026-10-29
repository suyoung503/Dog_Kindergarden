import SwiftUI

struct NotificationInboxView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppNotificationService.self) private var notificationService

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider().foregroundStyle(Color.brandBeigeBorder)
            if notificationService.inboxItems.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task { notificationService.markAllInboxRead() }
        .onChange(of: notificationService.inboxItems.count) { _, _ in
            notificationService.markAllInboxRead()
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 12) {
            Button(action: router.back) {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.brandBeigeBorder, lineWidth: 1))
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.brandBrown)
                    )
            }
            Text("알림")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Spacer()
            if !notificationService.inboxItems.isEmpty {
                Button("전체 삭제") { notificationService.clearInbox() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.brandBrownMid)
            }
        }
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
        .padding(.bottom, 12)
        .background(.white)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 38))
                .foregroundStyle(Color.brandOrange)
            Text("아직 새 알림이 없어요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text("알림 권한을 끄더라도 예약·채팅·문의 소식은 이곳에서 확인할 수 있어요.")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(notificationService.inboxItems) { item in
                    Button {
                        notificationService.markInboxRead(id: item.id)
                        if let link = item.deepLink {
                            notificationService.pendingDeepLink = link
                        }
                    } label: {
                        notificationRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .refreshable { await notificationService.pollOnce() }
    }

    private func notificationRow(_ item: AppInboxItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(iconColor(for: item.type).opacity(0.14))
                .frame(width: 44, height: 44)
                .overlay {
                    if item.type == "diary" {
                        EmojiIcon(emoji: "📔", size: 25)
                    } else {
                        Image(systemName: iconName(for: item.type))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(iconColor(for: item.type))
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.relativeFormatter.localizedString(for: item.receivedAt, relativeTo: Date()))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.brandBrownMid)
                }
                Text(item.body)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#7a5635"))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if item.deepLink != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.brandBrownLight)
                    .padding(.top, 16)
            }
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.brandBeigeBorder, lineWidth: 1))
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "chat": return "message.fill"
        case "support": return "bubble.left.and.bubble.right.fill"
        case "owner_application", "owner_application_rejected": return "building.2.fill"
        case "reservation_request", "reservation_confirmed", "reservation_submitted", "reservation_canceled": return "calendar"
        default: return "bell.fill"
        }
    }

    private func iconColor(for type: String) -> Color {
        switch type {
        case "chat": return Color.brandGreen
        case "support": return Color(hex: "#3C88A8")
        case "owner_application", "owner_application_rejected": return Color.brandOrange
        default: return Color.brandBrown
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()
}
