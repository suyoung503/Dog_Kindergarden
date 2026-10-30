import SwiftUI
import Observation

@Observable
@MainActor
final class ChatListViewModel {
    var rooms: [ChatRoomSummary] = []
    var receivedRooms: [OwnerChatRoomSummary] = []   // 사장님: 내 가게로 온 손님 문의방
    var loadPhase: AsyncLoadPhase = .idle

    func load(userId: Int, isOwner: Bool) async {
        guard !loadPhase.isLoading else { return }
        loadPhase = .loading
        do {
            let loadedRooms = try await ChatService.rooms(userId: userId)
            let loadedReceived: [OwnerChatRoomSummary]
            if isOwner {
                let received = try await ChatService.ownerRooms(ownerId: userId)
                // 내가 내 가게에 문의한 방은 '내 채팅'에만 표시
                loadedReceived = received.filter { r in
                    !loadedRooms.contains { $0.room_id == r.room_id }
                }
            } else {
                loadedReceived = []
            }
            rooms = loadedRooms
            receivedRooms = loadedReceived
            loadPhase = .loaded
        } catch {
            loadPhase = .failed("채팅 목록을 불러오지 못했어요. 연결을 확인하고 다시 시도해 주세요.")
        }
    }
}

struct ChatListView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppNotificationService.self) private var notificationService
    @Environment(AuthSession.self) private var authSession
    @State private var vm = ChatListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            navBar
            if vm.rooms.isEmpty && vm.receivedRooms.isEmpty {
                emptyContent
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        loadStatusHeader
                        // 사장님: 받은 문의 섹션을 위에 분리
                        if !vm.receivedRooms.isEmpty {
                            sectionHeader("받은 문의")
                            ForEach(vm.receivedRooms) { room in
                                receivedRow(room)
                            }
                            if !vm.rooms.isEmpty {
                                sectionHeader("내 채팅")
                            }
                        }
                        ForEach(vm.rooms) { room in
                            chatRow(room)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                }
            }
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task {
            let updates = notificationService.updates()
            await load()
            for await _ in updates {
                guard !Task.isCancelled else { return }
                await load()
            }
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
            Text("채팅")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
        .padding(.bottom, 4)
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyContent: some View {
        switch vm.loadPhase {
        case .idle, .loading:
            AsyncLoadingStateView(message: "채팅 목록을 불러오는 중이에요")
                .frame(maxHeight: .infinity, alignment: .top)
        case .loaded:
            emptyState
        case .failed(let message):
            AsyncLoadFailureView(message: message) {
                Task { await load() }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var loadStatusHeader: some View {
        switch vm.loadPhase {
        case .loading:
            AsyncRefreshIndicator()
        case .failed(let message):
            AsyncLoadFailureView(message: message, compact: true) {
                Task { await load() }
            }
        case .idle, .loaded:
            EmptyView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            EmojiIcon(emoji: "💬", size: 40)
            Text("아직 채팅방이 없어요")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Text("예약하거나 가게에 문의하면\n채팅방이 생겨요")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandBrownMid)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Section

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.brandBrownMid)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    // 받은 문의 행 — 손님 닉네임 + 가게명. 탭하면 같은 ChatRoomView에서 답장
    private func receivedRow(_ room: OwnerChatRoomSummary) -> some View {
        // 보호자 프로필 — 강아지 아바타(dog_b/dog_c)를 방마다 고정 순환
        let avatar = "img:\(dogAvatarName(room.room_id))"
        return Button(action: {
            router.selectedChat = room.customer_name ?? "보호자"
            router.selectedRoomId = room.room_id
            router.chatRoomAsOwner = true
            router.chatRoomAvatar = avatar
            router.go(.chatRoom)
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#FFD9A8"))
                        .frame(width: 48, height: 48)
                    EmojiIcon(emoji: avatar, size: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(room.customer_name ?? "보호자")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.brandBrown)
                        Text(room.store_name ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.brandBrownMid)
                            .lineLimit(1)
                        Spacer()
                        Text(shortTime(room.last_time))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.brandBrownMid)
                    }
                    Text(room.last_message ?? "새 문의")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#7a5635"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row

    private func chatRow(_ room: ChatRoomSummary) -> some View {
        // 가게 프로필 — 타입별 호텔/유치원 아이콘
        let isHotel = room.store_type == "호텔"
        let avatar = storeTypeEmoji(room.store_type)
        return Button(action: {
            router.selectedChat = room.store_name ?? "채팅"
            router.selectedRoomId = room.room_id
            router.chatRoomAsOwner = false
            router.chatRoomAvatar = avatar
            router.go(.chatRoom)
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isHotel ? Color(hex: "#FFE6CC") : Color.brandGreenLight)
                        .frame(width: 48, height: 48)
                    EmojiIcon(emoji: avatar, size: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(room.store_name ?? "채팅")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.brandBrown)
                        Spacer()
                        Text(shortTime(room.last_time))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.brandBrownMid)
                    }
                    Text(room.last_message ?? "새 채팅방")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#7a5635"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time

    // 서버 시각(UTC "yyyy-MM-dd HH:mm:ss")을 로컬 "M/d HH:mm"으로
    private static let inFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let outFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        f.timeZone = .current
        return f
    }()

    private func shortTime(_ s: String?) -> String {
        guard let s, let d = Self.inFmt.date(from: s) else { return "" }
        return Self.outFmt.string(from: d)
    }

    // MARK: - Actions

    private func load() async {
        guard !vm.loadPhase.isLoading else { return }
        guard let uid = authSession.userId else {
            vm.loadPhase = .failed("로그인 정보를 확인하지 못했어요.")
            return
        }
        await vm.load(userId: uid, isOwner: authSession.isOwner)
    }
}
