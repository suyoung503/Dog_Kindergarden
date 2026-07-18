import SwiftUI
import Observation

struct ChatMessage: Identifiable {
    let id = UUID()
    let from: MessageSender
    let text: String
}

enum MessageSender { case store, me, system }

@Observable
@MainActor
final class ChatRoomViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isLoading = false
    var errorMessage: String?

    private(set) var roomId: Int?
    private var myUserId = 1
    // 작성 모드용 store 컨텍스트 (roomId 없을 때 첫 전송에서 방 생성)
    private var storeKey = ""
    private var storeName = ""
    private var storeAddress = ""

    func configure(roomId: Int?, userId: Int, storeKey: String, storeName: String, storeAddress: String) {
        self.roomId = roomId
        self.myUserId = userId
        self.storeKey = storeKey
        self.storeName = storeName
        self.storeAddress = storeAddress
    }

    func load() async {
        guard let roomId else { return }   // 작성 모드는 빈 화면
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await ChatService.messages(roomId: roomId)
            messages = dtos.map(map)
            await ChatService.markRead(roomId: roomId, userId: myUserId)
        } catch {
            errorMessage = "메시지를 불러오지 못했어요."
        }
    }

    // 상대(사장님/손님)가 보낸 새 메시지 반영 — 방이 열려 있는 동안 주기 호출
    func refresh() async {
        guard let roomId, !isSending else { return }
        guard let dtos = try? await ChatService.messages(roomId: roomId) else { return }
        if dtos.count != messages.count {
            messages = dtos.map(map)
            // 방을 보고 있는 중에 도착한 메시지도 바로 읽음 처리
            await ChatService.markRead(roomId: roomId, userId: myUserId)
        }
    }

    private var isSending = false

    func send() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        // 작성 모드 첫 전송: 방 생성 → 전송 → 전체 로드(이전/시스템 메시지 포함)
        if roomId == nil {
            do {
                let rid = try await ChatService.openRoom(
                    userId: myUserId, storeKey: storeKey,
                    storeName: storeName, storeAddress: storeAddress
                )
                roomId = rid
                try await ChatService.send(roomId: rid, senderId: myUserId, content: trimmed)
                await load()
            } catch {
                errorMessage = "전송에 실패했어요."
                inputText = trimmed
            }
            return
        }

        guard let roomId else { return }
        // 낙관적 추가 후 전송, 실패 시 롤백
        let optimistic = ChatMessage(from: .me, text: trimmed)
        messages.append(optimistic)
        do {
            try await ChatService.send(roomId: roomId, senderId: myUserId, content: trimmed)
        } catch {
            messages.removeAll { $0.id == optimistic.id }
            errorMessage = "전송에 실패했어요."
            inputText = trimmed
        }
    }

    private func map(_ dto: ChatMessageDTO) -> ChatMessage {
        // 자동메시지(sender 0)는 화자 없는 시스템 안내 — 양쪽 시점 모두 중앙 안내문
        if dto.sender_id == 0 { return ChatMessage(from: .system, text: dto.content) }
        return ChatMessage(from: dto.sender_id == myUserId ? .me : .store, text: dto.content)
    }
}

struct ChatRoomView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var authSession
    @State private var vm = ChatRoomViewModel()

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
        .task {
            // 미로그인 폴백(?? 1)은 user 1 데이터 혼입 위험이 있어 두지 않는다 — 이 화면은 로그인 후에만 진입
            guard let uid = authSession.userId else { return }
            let pin = router.selectedPin
            vm.configure(
                roomId: router.selectedRoomId,
                userId: uid,
                storeKey: pin?.storeKey ?? "",
                storeName: router.selectedChat,
                storeAddress: pin?.address ?? ""
            )
            await vm.load()
        }
        .task {
            // 3초 주기 폴링 — 상대가 보낸 메시지를 방에 머무는 동안 반영 (화면 이탈 시 자동 취소)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await vm.refresh()
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

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    if vm.isLoading && vm.messages.isEmpty {
                        ProgressView().padding(.top, 40)
                    }
                    ForEach(vm.messages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
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
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)
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
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .trailing)
            }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button(action: {}) {
                ZStack {
                    Circle().fill(Color(hex: "#FFE6CC")).frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 15)).foregroundStyle(Color.brandBrown)
                }
            }
            HStack {
                TextField("메시지를 입력해주세요", text: $vm.inputText)
                    .font(.system(size: 13))
                    .submitLabel(.send)
                    .onSubmit { Task { await vm.send() } }
                Image(systemName: "face.smiling")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.brandBrownLight)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Color.brandCream.ignoresSafeArea())
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.brandBeigeBorder, lineWidth: 1))

            Button(action: { Task { await vm.send() } }) {
                ZStack {
                    Circle()
                        .fill(Color.brandOrange)
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white)
        .overlay(alignment: .top) { Divider().foregroundStyle(Color.brandBeigeBorder) }
    }
}
