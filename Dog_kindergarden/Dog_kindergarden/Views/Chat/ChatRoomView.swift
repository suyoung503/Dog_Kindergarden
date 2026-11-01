import SwiftUI
import Observation

struct ChatMessage: Identifiable, Equatable {
    var id = UUID().uuidString
    let from: MessageSender
    let text: String
}

enum MessageSender: Equatable { case store, me, system }

// 최초 방 ID는 작성 모드에서 방을 생성해도 바꾸지 않는다.
struct ChatRoomIdentity: Hashable {
    let roomId: Int?
    let userId: Int
    let storeKey: String
    let token: String?
    let baseURL: URL
}

@Observable
@MainActor
final class ChatRoomViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isLoading = false
    var errorMessage: String?

    private(set) var roomId: Int?
    private(set) var identity: ChatRoomIdentity?
    private(set) var generation: UInt = 0
    private(set) var isSending = false
    private var loadGeneration: UInt = 0
    private var pendingFetchGeneration: UInt?
    private var lastFailureWasSend = false
    private var needsRefreshAfterSending = false
    // 작성 모드용 store 컨텍스트 (roomId 없을 때 첫 전송에서 방 생성)
    private var storeKey = ""
    private var storeName = ""
    private var storeAddress = ""

    private let fetchMessages: (Int) async throws -> [ChatMessageDTO]
    private let createRoom: (Int, String, String, String) async throws -> Int
    private let postMessage: (Int, Int, String) async throws -> Void
    private let readRoom: (Int, Int) async -> Void
    private let credentials: @MainActor () -> (token: String?, baseURL: URL)

    init(
        fetchMessages: @escaping (Int) async throws -> [ChatMessageDTO] = { try await ChatService.messages(roomId: $0) },
        createRoom: @escaping (Int, String, String, String) async throws -> Int = { try await ChatService.openRoom(userId: $0, storeKey: $1, storeName: $2, storeAddress: $3) },
        postMessage: @escaping (Int, Int, String) async throws -> Void = { try await ChatService.send(roomId: $0, senderId: $1, content: $2) },
        readRoom: @escaping (Int, Int) async -> Void = { await ChatService.markRead(roomId: $0, userId: $1) },
        credentials: @escaping @MainActor () -> (token: String?, baseURL: URL) = { (AuthTokenStore.load(), APIEnvironment.apiBaseURL) }
    ) {
        self.fetchMessages = fetchMessages
        self.createRoom = createRoom
        self.postMessage = postMessage
        self.readRoom = readRoom
        self.credentials = credentials
    }

    @discardableResult
    func configure(roomId: Int?, userId: Int, storeKey: String, storeName: String, storeAddress: String) -> UInt {
        invalidate()
        let current = credentials()
        identity = ChatRoomIdentity(roomId: roomId, userId: userId, storeKey: storeKey,
                                    token: current.token, baseURL: current.baseURL)
        self.roomId = roomId
        self.storeKey = storeKey
        self.storeName = storeName
        self.storeAddress = storeAddress
        return generation
    }

    func invalidate(generation expected: UInt? = nil) {
        if let expected, expected != generation { return }
        generation &+= 1
        loadGeneration &+= 1
        pendingFetchGeneration = nil
        lastFailureWasSend = false
        identity = nil
        roomId = nil
        messages = []
        inputText = ""
        errorMessage = nil
        isLoading = false
        isSending = false
        needsRefreshAfterSending = false
    }

    func load() async { await fetch(showLoading: true) }

    // WebSocket invalidation/복귀 시에도 최초 조회와 같은 요청 경계를 사용한다.
    func refresh() async { await fetch(showLoading: false) }

    private func fetch(showLoading: Bool) async {
        let contextGeneration = generation
        guard let identity, isCurrent(identity, generation: contextGeneration), let roomId else { return }
        guard !isSending else { needsRefreshAfterSending = true; return }
        loadGeneration &+= 1
        let requestGeneration = loadGeneration
        pendingFetchGeneration = requestGeneration
        isLoading = showLoading
        defer {
            if pendingFetchGeneration == requestGeneration { pendingFetchGeneration = nil }
            if generation == contextGeneration, loadGeneration == requestGeneration { isLoading = false }
        }
        do {
            let dtos = try await fetchMessages(roomId)
            guard isCurrent(identity, generation: contextGeneration), loadGeneration == requestGeneration else { return }
            guard !isSending else { needsRefreshAfterSending = true; return }
            let loaded = dtos.map { dto in
                ChatMessage(id: "message:\(dto.message_id)",
                            from: dto.sender_id == 0 ? .system : (dto.sender_id == identity.userId ? .me : .store),
                            text: dto.content)
            }
            let changed = loaded != messages
            if changed { messages = loaded }
            if !lastFailureWasSend { errorMessage = nil }
            if showLoading || changed { await readRoom(roomId, identity.userId) }
        } catch {
            guard isCurrent(identity, generation: contextGeneration), loadGeneration == requestGeneration,
                  !Self.isCancellation(error) else { return }
            if Self.isAccessFailure(error) { messages = [] }
            lastFailureWasSend = false
            errorMessage = "메시지를 불러오지 못했어요. 연결 또는 채팅방 접근 권한을 확인해 주세요."
        }
    }

    func send() async {
        let contextGeneration = generation
        guard let identity, isCurrent(identity, generation: contextGeneration), !isSending else { return }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        errorMessage = nil
        lastFailureWasSend = false
        isSending = true
        if pendingFetchGeneration != nil { needsRefreshAfterSending = true }
        // 전송 전에 시작된 조회는 새 말풍선을 모르는 스냅샷일 수 있다.
        loadGeneration &+= 1
        isLoading = false
        defer {
            if generation == contextGeneration, self.identity == identity {
                isSending = false
                if needsRefreshAfterSending, !Task.isCancelled {
                    needsRefreshAfterSending = false
                    Task {
                        guard self.isCurrent(identity, generation: contextGeneration) else { return }
                        await self.refresh()
                    }
                }
            }
        }

        var optimisticID: String?
        do {
            if roomId == nil {
                let rid = try await createRoom(identity.userId, storeKey, storeName, storeAddress)
                guard isCurrent(identity, generation: contextGeneration) else { return }
                roomId = rid
            }
            guard let roomId, isCurrent(identity, generation: contextGeneration) else { return }
            let optimistic = ChatMessage(from: .me, text: trimmed)
            optimisticID = optimistic.id
            messages.append(optimistic)
            try await postMessage(roomId, identity.userId, trimmed)
            guard isCurrent(identity, generation: contextGeneration) else { return }
            if identity.roomId == nil { needsRefreshAfterSending = true }
        } catch {
            guard isCurrent(identity, generation: contextGeneration), !Self.isCancellation(error) else { return }
            if Self.isAccessFailure(error) { messages = [] }
            else if let optimisticID { messages.removeAll { $0.id == optimisticID } }
            lastFailureWasSend = true
            errorMessage = "전송에 실패했어요. 다시 시도해주세요."
            // 기다리는 동안 작성한 다음 초안을 실패한 이전 글로 덮지 않는다.
            if inputText.isEmpty { inputText = trimmed }
        }
    }

    private func isCurrent(_ expected: ChatRoomIdentity, generation expectedGeneration: UInt) -> Bool {
        guard !Task.isCancelled, generation == expectedGeneration, identity == expected else { return false }
        let current = credentials()
        guard expected.userId > 0, let token = expected.token, !token.isEmpty,
              current.token == token, current.baseURL == expected.baseURL else {
            invalidate(generation: expectedGeneration)
            return false
        }
        return true
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func isAccessFailure(_ error: Error) -> Bool {
        switch error as? APIError {
        case .httpStatus(let status), .server(let status, _, _): return [401, 403, 404].contains(status)
        default: return false
        }
    }

}

struct ChatRoomView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppNotificationService.self) private var notificationService
    @Environment(AuthSession.self) private var authSession
    @State private var vm = ChatRoomViewModel()
    @State private var didInitialScroll = false
    @State private var messageListWidth: CGFloat = 0

    private var chatIdentity: ChatRoomIdentity? {
        guard let uid = authSession.userId else { return nil }
        return ChatRoomIdentity(roomId: router.selectedRoomId, userId: uid,
                                storeKey: router.selectedPin?.storeKey ?? "",
                                token: AuthTokenStore.load(), baseURL: APIEnvironment.apiBaseURL)
    }

    private var displayedMessages: [ChatMessage] { vm.identity == chatIdentity ? vm.messages : [] }

    private var draftBinding: Binding<String> {
        Binding(get: { vm.identity == chatIdentity ? vm.inputText : "" },
                set: { if vm.identity == chatIdentity { vm.inputText = $0 } })
    }

    var body: some View {
        VStack(spacing: 0) {
            chatNavBar
            Divider().foregroundStyle(Color.brandBeigeBorder)
            messageList
            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
            inputBar
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task(id: chatIdentity) {
            guard !Task.isCancelled, let identity = chatIdentity else { return }
            let updates = notificationService.updates()
            let pin = router.selectedPin
            let generation = vm.configure(
                roomId: identity.roomId, userId: identity.userId,
                storeKey: identity.storeKey, storeName: router.selectedChat,
                storeAddress: pin?.address ?? ""
            )
            didInitialScroll = false
            defer {
                let ownsContext = vm.generation == generation
                let closingRoom = vm.roomId
                vm.invalidate(generation: generation)
                if ownsContext, let closingRoom, notificationService.activeRoomId == closingRoom {
                    notificationService.activeRoomId = nil
                }
            }
            notificationService.activeRoomId = identity.roomId
            await vm.load()
            for await _ in updates {
                guard !Task.isCancelled, chatIdentity == identity else { return }
                await vm.refresh()
            }
        }
        .onChange(of: vm.roomId) { _, roomId in
            guard vm.identity != nil, vm.identity == chatIdentity else { return }
            notificationService.activeRoomId = roomId
        }
        .onDisappear {
            let closingRoom = vm.roomId
            vm.invalidate()
            // 먼저 열린 다른 방의 열람 상태는 이전 화면이 지우지 않는다.
            if let closingRoom, notificationService.activeRoomId == closingRoom {
                notificationService.activeRoomId = nil
            }
        }
    }

    // MARK: - Nav

    private var chatNavBar: some View {
        HStack(spacing: 12) {
            Button(action: router.back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.brandBrown)
                    .frame(width: 36, height: 36)
            }
            ZStack {
                Circle().fill(Color(hex: "#FFE6CC")).frame(width: 36, height: 36)
                EmojiIcon(emoji: router.chatRoomAvatar, size: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(router.selectedChat)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                // '응답중'은 가게 쪽 상태 표시 — 상대가 손님인 사장님 시점에서는 숨김
                if !router.chatRoomAsOwner {
                    HStack(spacing: 4) {
                        Circle().fill(Color.brandGreen).frame(width: 6, height: 6)
                        Text("응답중").font(.system(size: 10)).foregroundStyle(Color.brandGreen)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
        .padding(.bottom, 12)
        .background(.white)
    }

    // MARK: - Messages

    private let bottomAnchorId = "chat-bottom-anchor"

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    if vm.isLoading && displayedMessages.isEmpty {
                        ProgressView().padding(.top, 40)
                    }
                    ForEach(displayedMessages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                    }
                    // 마지막 메시지 뒤 트레일링 여백을 메시지 사이 간격(spacing: 8)과 동일하게 유지하는 스크롤 앵커
                    Color.clear.frame(height: 0).id(bottomAnchorId)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .onChange(of: displayedMessages.last?.id) { _, _ in
                // 방 진입 시 첫 로드는 즉시 이동, 이후 새 메시지 도착 시에만 애니메이션
                if didInitialScroll {
                    withAnimation { proxy.scrollTo(bottomAnchorId, anchor: .bottom) }
                } else {
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                    didInitialScroll = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                // 별도 애니메이션을 걸면 시스템의 키보드 세이프에어리어 리사이즈 애니메이션과 겹쳐 두 번 움직이는 것처럼 보인다 —
                // 즉시 이동시켜 화면엔 시스템 키보드 회피 애니메이션 하나만 보이게 한다
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            messageListWidth = width
        }
    }

    private var bubbleMaxWidth: CGFloat? {
        guard messageListWidth > 0 else { return nil }
        return max((messageListWidth - 32) * 0.75, 0)
    }

    @ViewBuilder
    private func messageBubble(_ msg: ChatMessage) -> some View {
        switch msg.from {
        case .system:
            // 시스템 안내(sender 0) — 화자 없는 중앙 안내문 (예약 취소·리뷰 요청·알림장 알림)
            Text(msg.text)
                .font(.system(size: 11))
                .foregroundStyle(Color.brandBrownMid)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.brandCreamLight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        case .store:
            HStack(alignment: .bottom, spacing: 6) {
                ZStack {
                    Circle().fill(Color(hex: "#FFE6CC")).frame(width: 28, height: 28)
                    EmojiIcon(emoji: router.chatRoomAvatar, size: 16)
                }
                Text(msg.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrown)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.white)
                    .clipShape(
                        .rect(
                            topLeadingRadius: 18, bottomLeadingRadius: 6,
                            bottomTrailingRadius: 18, topTrailingRadius: 18
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18).stroke(Color.brandBeigeBorder, lineWidth: 1)
                    )
                    .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
                Spacer()
            }
        case .me:
            HStack(alignment: .bottom, spacing: 6) {
                Spacer()
                Text(msg.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.brandOrange)
                    .clipShape(
                        .rect(
                            topLeadingRadius: 18, bottomLeadingRadius: 18,
                            bottomTrailingRadius: 6, topTrailingRadius: 18
                        )
                    )
                    .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
            }
        }
    }

    // MARK: - Input

    private func sendMessage() {
        guard let expected = chatIdentity, vm.identity == expected else { return }
        let generation = vm.generation
        Task {
            guard vm.generation == generation, vm.identity == expected, chatIdentity == expected else { return }
            await vm.send()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("메시지를 입력해주세요", text: draftBinding)
                .font(.system(size: 13))
                .submitLabel(.send)
                .onSubmit(sendMessage)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color.brandCream.ignoresSafeArea())
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.brandBeigeBorder, lineWidth: 1))

            Button(action: sendMessage) {
                ZStack {
                    Circle()
                        .fill(Color.brandOrange)
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    if vm.isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(vm.isSending || vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.identity != chatIdentity)
            .accessibilityLabel(vm.isSending ? "메시지 전송 중" : "메시지 보내기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white)
        .overlay(alignment: .top) { Divider().foregroundStyle(Color.brandBeigeBorder) }
    }
}
