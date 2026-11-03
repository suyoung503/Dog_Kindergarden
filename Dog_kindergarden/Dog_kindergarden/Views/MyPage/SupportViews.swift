import SwiftUI
import Observation

@Observable
@MainActor
final class SupportConversationViewModel {
    var messages: [SupportMessageResponse] = []
    var inputText = ""
    var isLoading = false
    var isSending = false
    var errorMessage: String?
    private(set) var conversationId: Int?

    private var isAdmin = false
    private(set) var generation: UInt = 0
    private var isReloading = false

    private let fetchConversation: () async throws -> SupportConversationStatus
    private let openConversation: () async throws -> SupportConversation
    private let fetchMessages: (Int) async throws -> [SupportMessageResponse]
    private let postMessage: (Int, String) async throws -> SupportMessageResponse

    init(
        fetchConversation: @escaping () async throws -> SupportConversationStatus = { try await APIClient.shared.fetchMySupportConversation() },
        openConversation: @escaping () async throws -> SupportConversation = { try await APIClient.shared.openSupportConversation() },
        fetchMessages: @escaping (Int) async throws -> [SupportMessageResponse] = { try await APIClient.shared.fetchSupportMessages(conversationId: $0) },
        postMessage: @escaping (Int, String) async throws -> SupportMessageResponse = { try await APIClient.shared.sendSupportMessage(conversationId: $0, content: $1) }
    ) {
        self.fetchConversation = fetchConversation
        self.openConversation = openConversation
        self.fetchMessages = fetchMessages
        self.postMessage = postMessage
    }

    @discardableResult
    func configure(conversationId: Int?, isAdmin: Bool) -> UInt {
        invalidate()
        self.conversationId = conversationId
        self.isAdmin = isAdmin
        return generation
    }

    func invalidate(generation expected: UInt? = nil) {
        if let expected, expected != generation { return }
        generation &+= 1
        conversationId = nil
        messages = []
        inputText = ""
        errorMessage = nil
        isLoading = false
        isSending = false
        isReloading = false
    }

    func load() async { await reloadMessages(showLoading: true) }

    func refresh() async { await reloadMessages(showLoading: false) }

    func send() async {
        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Task.isCancelled, !content.isEmpty, !isSending else { return }
        let requestGeneration = generation
        guard let conversationId else {
            errorMessage = "문의 대화를 열지 못했어요. 다시 시도해주세요."
            return
        }

        isSending = true
        errorMessage = nil
        inputText = ""
        defer { if generation == requestGeneration { isSending = false } }
        do {
            let message = try await postMessage(conversationId, content)
            guard !Task.isCancelled, generation == requestGeneration else { return }
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
        } catch {
            guard !Task.isCancelled, generation == requestGeneration else { return }
            if inputText.isEmpty { inputText = content }
            errorMessage = supportErrorMessage(error)
        }
    }

    func isMine(_ message: SupportMessageResponse) -> Bool {
        isAdmin ? message.senderRole == "ADMIN" : message.senderRole == "USER"
    }

    private func reloadMessages(showLoading: Bool) async {
        guard !Task.isCancelled, !isReloading, !isSending,
              showLoading || errorMessage == nil else { return }
        let requestGeneration = generation
        isReloading = true
        isLoading = showLoading
        if showLoading { errorMessage = nil }
        defer {
            if generation == requestGeneration {
                isLoading = false
                isReloading = false
            }
        }
        do {
            if conversationId == nil {
                guard !isAdmin else {
                    errorMessage = "선택한 문의를 찾을 수 없어요."
                    return
                }
                let status = try await fetchConversation()
                guard !Task.isCancelled, generation == requestGeneration else { return }
                guard status.adminAvailable else {
                    errorMessage = "현재 문의를 받을 운영자가 없어요. 잠시 후 다시 시도해주세요."
                    return
                }
                if let existing = status.conversation {
                    conversationId = existing.conversationId
                } else {
                    let opened = try await openConversation()
                    guard !Task.isCancelled, generation == requestGeneration else { return }
                    conversationId = opened.conversationId
                }
            }
            guard let conversationId else { return }
            let previousIDs = Set(messages.map(\.id))
            let loaded = try await fetchMessages(conversationId)
            guard !Task.isCancelled, generation == requestGeneration else { return }
            let loadedIDs = Set(loaded.map(\.id))
            // 조회를 기다리는 동안 전송에 성공한 글만 오래된 스냅샷에 보충한다.
            let sentWhileLoading = messages.filter { !previousIDs.contains($0.id) && !loadedIDs.contains($0.id) }
            messages = (loaded + sentWhileLoading).sorted { $0.id < $1.id }
        } catch {
            guard !Task.isCancelled, generation == requestGeneration else { return }
            if showLoading { errorMessage = supportErrorMessage(error) }
        }
    }

    private func supportErrorMessage(_ error: Error) -> String {
        if case let APIError.server(_, code, message) = error {
            if code == "SUPPORT_ADMIN_UNAVAILABLE" {
                return "현재 문의를 받을 운영자가 없어요. 잠시 후 다시 시도해주세요."
            }
            if let message, !message.isEmpty { return message }
        }
        return "문의 내용을 불러오지 못했어요. 잠시 후 다시 시도해주세요."
    }
}

private struct SupportConversationContext: Hashable {
    let conversationId: Int?
    let userId: Int?
    let isAdmin: Bool
    let token: String?
    let baseURL: URL
}

struct SupportConversationView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession
    @State private var viewModel = SupportConversationViewModel()
    @State private var configuredContext: SupportConversationContext?
    @State private var didInitialScroll = false
    @State private var messageAreaWidth: CGFloat = 0

    private let bottomAnchor = "support-conversation-bottom"

    private var conversationContext: SupportConversationContext {
        SupportConversationContext(conversationId: router.selectedSupportConversationId,
                                   userId: authSession.userId, isAdmin: authSession.isAdmin,
                                   token: AuthTokenStore.load(), baseURL: APIEnvironment.apiBaseURL)
    }

    private var displayedMessages: [SupportMessageResponse] {
        configuredContext == conversationContext ? viewModel.messages : []
    }

    private var draftBinding: Binding<String> {
        Binding(get: { configuredContext == conversationContext ? viewModel.inputText : "" },
                set: { if configuredContext == conversationContext { viewModel.inputText = $0 } })
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider().foregroundStyle(Color.brandBeigeBorder)
            messageArea
            if configuredContext == conversationContext, let errorMessage = viewModel.errorMessage {
                errorBanner(errorMessage)
            }
            inputBar
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task(id: conversationContext) {
            guard !Task.isCancelled else { return }
            let context = conversationContext
            let generation = viewModel.configure(conversationId: context.conversationId, isAdmin: context.isAdmin)
            configuredContext = context
            didInitialScroll = false
            defer { viewModel.invalidate(generation: generation) }
            await viewModel.load()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return }
                guard conversationContext == context else { return }
                await viewModel.refresh()
            }
        }
        .onDisappear {
            configuredContext = nil
            viewModel.invalidate()
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
            VStack(alignment: .leading, spacing: 2) {
                Text(router.selectedSupportConversationTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Text(authSession.isAdmin ? "고객 문의" : "맡겨멍 운영자와의 1:1 문의")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.brandBrownMid)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
        .padding(.bottom, 12)
        .background(.white)
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    if viewModel.isLoading && displayedMessages.isEmpty {
                        ProgressView().padding(.top, 48)
                    } else if !viewModel.isLoading,
                              displayedMessages.isEmpty,
                              viewModel.errorMessage == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 34))
                                .foregroundStyle(Color.brandOrange)
                            Text(authSession.isAdmin ? "아직 메시지가 없어요" : "궁금한 내용을 남겨주세요")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.brandBrown)
                            if !authSession.isAdmin {
                                Text("운영자가 확인한 뒤 이 대화에서 답변해드려요.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.brandBrownMid)
                            }
                        }
                        .padding(.top, 56)
                    }

                    ForEach(displayedMessages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 0).id(bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: displayedMessages.count) { _, _ in
                if didInitialScroll {
                    withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                } else {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    didInitialScroll = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            messageAreaWidth = width
        }
    }

    private var bubbleMaxWidth: CGFloat? {
        guard messageAreaWidth > 0 else { return nil }
        return max((messageAreaWidth - 32) * 0.75, 0)
    }

    private func messageBubble(_ message: SupportMessageResponse) -> some View {
        let mine = viewModel.isMine(message)
        return HStack(alignment: .bottom, spacing: 6) {
            if mine { Spacer() }
            if !mine {
                Circle()
                    .fill(Color(hex: "#FFE6CC"))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: authSession.isAdmin ? "person.fill" : "headphones")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.brandOrange)
                    )
            }
            Text(message.content)
                .font(.system(size: 13))
                .foregroundStyle(mine ? .white : Color.brandBrown)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(mine ? Color.brandOrange : .white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    if !mine {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.brandBeigeBorder, lineWidth: 1)
                    }
                }
                .frame(maxWidth: bubbleMaxWidth, alignment: mine ? .trailing : .leading)
            if !mine { Spacer() }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("재시도") {
                let context = conversationContext, generation = viewModel.generation
                Task {
                    guard configuredContext == context, conversationContext == context,
                          viewModel.generation == generation else { return }
                    await viewModel.load()
                }
            }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.brandOrange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.06))
    }

    private func sendMessage() {
        let context = conversationContext, generation = viewModel.generation
        Task {
            guard configuredContext == context, conversationContext == context,
                  viewModel.generation == generation else { return }
            await viewModel.send()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("메시지를 입력해주세요", text: draftBinding, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit(sendMessage)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.brandCream)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.brandBeigeBorder, lineWidth: 1))

            Button(action: sendMessage) {
                Circle()
                    .fill(Color.brandOrange)
                    .frame(width: 40, height: 40)
                    .overlay(
                        viewModel.isSending
                            ? AnyView(ProgressView().tint(.white))
                            : AnyView(Image(systemName: "paperplane.fill").font(.system(size: 15)).foregroundStyle(.white))
                    )
            }
            .disabled(
                configuredContext != conversationContext ||
                viewModel.isSending ||
                viewModel.conversationId == nil ||
                viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white)
        .overlay(alignment: .top) { Divider().foregroundStyle(Color.brandBeigeBorder) }
    }
}

@Observable
@MainActor
final class SupportConversationListViewModel {
    var conversations: [SupportConversationSummary] = []
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            conversations = try await APIClient.shared.fetchSupportConversations()
        } catch {
            conversations = []
            errorMessage = "고객 문의 목록을 불러오지 못했어요."
        }
    }
}

struct SupportConversationListView: View {
    @Environment(AppRouter.self) private var router
    @State private var viewModel = SupportConversationListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.brandBrownMid)
                    Button("다시 불러오기") { Task { await viewModel.load() } }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.brandOrange)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.conversations.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.brandOrange)
                    Text("아직 들어온 고객 문의가 없어요")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
                .refreshable { await viewModel.load() }
            }
        }
        .background(Color.brandCream.ignoresSafeArea())
        .task { await viewModel.load() }
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
            Text("고객 문의")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.brandBrown)
            Spacer()
        }
        .padding(.horizontal, 20)
        .safeAreaTopPadding()
        .padding(.bottom, 12)
    }

    private func conversationRow(_ conversation: SupportConversationSummary) -> some View {
        Button {
            router.selectedSupportConversationId = conversation.conversationId
            router.selectedSupportConversationTitle = conversation.userName ?? "고객"
            router.go(.supportConversation)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: "#FFE6CC"))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundStyle(Color.brandOrange)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conversation.userName ?? "고객")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.brandBrown)
                        Spacer()
                        Text(shortTime(conversation.lastMessageAt ?? conversation.updatedAt))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.brandBrownMid)
                    }
                    Text(conversation.lastMessage ?? "새 문의")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#7a5635"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let inputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let outputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    private func shortTime(_ value: String?) -> String {
        guard let value, let date = Self.inputFormatter.date(from: value) else { return "" }
        return Self.outputFormatter.string(from: date)
    }
}
