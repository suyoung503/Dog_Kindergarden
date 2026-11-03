import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("고객 문의 지연 응답과 전송 보호")
@MainActor
struct SupportConversationStateTests {
    @Test("전송 실패는 대기 중 새로 작성한 초안을 덮지 않는다")
    func preserveNewDraft() async throws {
        let network = SupportTestNetwork(), gate = SupportTestGate<SupportMessageResponse>()
        network.post = { _, _ in try await gate.wait() }
        let vm = network.makeModel(); vm.configure(conversationId: 1, isAdmin: false)
        vm.inputText = "실패할 글"
        let send = Task { await vm.send() }; try await gate.waitUntilStarted()
        vm.inputText = "다음 초안"
        gate.finish(.failure(URLError(.notConnectedToInternet))); await send.value
        #expect(vm.inputText == "다음 초안")
        #expect(vm.errorMessage != nil)
        #expect(!vm.isSending)
    }

    @Test("다음 초안이 없으면 실패한 전송 내용을 복원한다")
    func restoreFailedDraft() async {
        let network = SupportTestNetwork()
        network.post = { _, _ in throw URLError(.notConnectedToInternet) }
        let vm = network.makeModel(); vm.configure(conversationId: 1, isAdmin: false)
        vm.inputText = "  다시 보낼 글  "; await vm.send()
        #expect(vm.inputText == "다시 보낼 글")
        #expect(vm.messages.isEmpty)
        #expect(!vm.isSending)
    }

    @Test("동시에 열 번 전송해도 한 번만 요청하고 다음 초안은 유지한다")
    func duplicateSend() async throws {
        let network = SupportTestNetwork(), gate = SupportTestGate<SupportMessageResponse>()
        network.post = { _, _ in try await gate.wait() }
        let vm = network.makeModel(); vm.configure(conversationId: 1, isAdmin: false)
        vm.inputText = " 첫 글 "
        let send = Task { await vm.send() }; try await gate.waitUntilStarted()
        vm.inputText = "다음 초안"
        let duplicates = (0..<9).map { _ in Task { await vm.send() } }
        for duplicate in duplicates { await duplicate.value }
        #expect(network.posts.map { "\($0.0):\($0.1)" } == ["1:첫 글"])
        #expect(vm.inputText == "다음 초안")
        gate.finish(.success(message(2, "첫 글"))); await send.value
        #expect(vm.messages.map(\.content) == ["첫 글"])
        #expect(!vm.isSending)
    }

    @Test("전송 전에 시작한 지연 조회는 보낸 메시지와 기존 기록을 모두 보존한다", arguments: [false, true])
    func loadBeforeSend(initialLoad: Bool) async throws {
        let network = SupportTestNetwork(), gate = SupportTestGate<[SupportMessageResponse]>()
        network.fetch = { _, _ in try await gate.wait() }
        let vm = network.makeModel(); vm.configure(conversationId: 1, isAdmin: false)
        let load = Task { if initialLoad { await vm.load() } else { await vm.refresh() } }
        try await gate.waitUntilStarted()
        vm.inputText = "방금 전송"; await vm.send()
        gate.finish(.success([message(1, "기존 기록")])); await load.value
        #expect(vm.messages.map(\.content) == ["기존 기록", "방금 전송"])
        #expect(!vm.isLoading)
    }

    @Test("지연 조회에 이미 보낸 메시지가 있으면 말풍선을 중복하지 않는다")
    func loadedSendIsNotDuplicated() async throws {
        let network = SupportTestNetwork(), gate = SupportTestGate<[SupportMessageResponse]>()
        network.fetch = { _, _ in try await gate.wait() }
        let vm = network.makeModel(); vm.configure(conversationId: 1, isAdmin: false)
        let load = Task { await vm.load() }; try await gate.waitUntilStarted()
        vm.inputText = "방금 전송"; await vm.send()
        gate.finish(.success([message(1, "기존 기록"), message(2, "방금 전송")])); await load.value
        #expect(vm.messages.map(\.id) == [1, 2])
    }

    @Test("전송 응답보다 조회가 먼저 도착해도 같은 서버 메시지를 두 번 추가하지 않는다")
    func loadBeforeSendAcknowledgement() async throws {
        let network = SupportTestNetwork(), fetchGate = SupportTestGate<[SupportMessageResponse]>(), postGate = SupportTestGate<SupportMessageResponse>()
        network.fetch = { _, _ in try await fetchGate.wait() }
        network.post = { _, _ in try await postGate.wait() }
        let vm = network.makeModel(); vm.configure(conversationId: 1, isAdmin: false)
        let load = Task { await vm.load() }; try await fetchGate.waitUntilStarted()
        vm.inputText = "방금 전송"
        let send = Task { await vm.send() }; try await postGate.waitUntilStarted()
        fetchGate.finish(.success([message(1, "기존 기록"), message(2, "방금 전송")])); await load.value
        postGate.finish(.success(message(2, "방금 전송"))); await send.value
        #expect(vm.messages.map(\.id) == [1, 2])
        #expect(!vm.isSending)
    }

    @Test("느린 갱신 중 재진입 조회를 겹치지 않는다")
    func singleFlightReload() async throws {
        let network = SupportTestNetwork(), gate = SupportTestGate<[SupportMessageResponse]>()
        network.fetch = { call, _ in call == 1 ? try await gate.wait() : [message(2, "두 번째") ] }
        let vm = network.makeModel(); vm.configure(conversationId: 1, isAdmin: false)
        let refresh = Task { await vm.refresh() }; try await gate.waitUntilStarted()
        await vm.refresh(); await vm.load()
        #expect(network.fetchCount == 1)
        gate.finish(.success([message(1, "첫 조회")])); await refresh.value
        await vm.refresh()
        #expect(network.fetchCount == 2)
        #expect(vm.messages.map(\.content) == ["두 번째"])
    }

    @Test("알림으로 다른 문의를 열면 이전 대화의 지연 조회를 적용하지 않는다")
    func conversationSwitchDuringLoad() async throws {
        let network = SupportTestNetwork(), gate = SupportTestGate<[SupportMessageResponse]>()
        network.fetch = { _, conversation in conversation == 1 ? try await gate.wait() : [message(20, "B 대화", conversation: 2)] }
        let vm = network.makeModel()
        let generation = vm.configure(conversationId: 1, isAdmin: true)
        let load = Task {
            defer { vm.invalidate(generation: generation) }
            await vm.load()
        }
        try await gate.waitUntilStarted()
        vm.inputText = "A 초안"
        vm.configure(conversationId: 2, isAdmin: true); await vm.load()
        gate.finish(.success([message(10, "A 대화")])); await load.value
        #expect(vm.conversationId == 2)
        #expect(vm.messages.map(\.content) == ["B 대화"])
        #expect(vm.inputText.isEmpty)
    }

    @Test("이전 대화 전송의 성공이나 실패는 새 대화 초안과 전송 상태를 변경하지 않는다", arguments: [false, true])
    func conversationSwitchDuringSend(fails: Bool) async throws {
        let network = SupportTestNetwork(), oldGate = SupportTestGate<SupportMessageResponse>(), newGate = SupportTestGate<SupportMessageResponse>()
        network.post = { conversation, _ in conversation == 1 ? try await oldGate.wait() : try await newGate.wait() }
        let vm = network.makeModel(); vm.configure(conversationId: 1, isAdmin: true); vm.inputText = "A 글"
        let old = Task { await vm.send() }; try await oldGate.waitUntilStarted()
        vm.configure(conversationId: 2, isAdmin: true); vm.inputText = "B 글"
        let current = Task { await vm.send() }
        // 기존 구현은 이전 대화 isSending 때문에 B 전송 자체도 차단한다.
        for _ in 0..<1000 { if network.posts.count == 2 { break }; await Task.yield() }
        #expect(network.posts.count == 2)
        vm.inputText = "B 다음 초안"
        oldGate.finish(fails ? .failure(URLError(.timedOut)) : .success(message(2, "A 글")))
        await old.value
        #expect(vm.inputText == "B 다음 초안")
        #expect(vm.messages.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.isSending)
        newGate.finish(.success(message(20, "B 글", conversation: 2))); await current.value
        #expect(!vm.isSending)
    }

    @Test("화면 task 취소 후 지연 상태 조회가 끝나도 대화를 새로 생성하지 않는다")
    func canceledConversationLookup() async throws {
        let network = SupportTestNetwork(), gate = SupportTestGate<SupportConversationStatus>()
        network.lookup = { try await gate.wait() }
        let vm = network.makeModel(); vm.configure(conversationId: nil, isAdmin: false)
        let load = Task { await vm.load() }; try await gate.waitUntilStarted()
        load.cancel(); gate.finish(.success(SupportConversationStatus(adminAvailable: true, conversation: nil)))
        await load.value
        #expect(network.openCount == 0)
        #expect(network.fetchCount == 0)
        #expect(vm.conversationId == nil)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isLoading)
    }

    @Test("화면을 떠난 뒤 도착한 전송 응답은 닫힌 화면을 다시 채우지 않는다", arguments: [false, true])
    func disappearedWhileSending(fails: Bool) async throws {
        let network = SupportTestNetwork(), gate = SupportTestGate<SupportMessageResponse>()
        network.post = { _, _ in try await gate.wait() }
        let vm = network.makeModel(); vm.configure(conversationId: 1, isAdmin: false); vm.inputText = "A 글"
        let send = Task { await vm.send() }; try await gate.waitUntilStarted()
        vm.invalidate()
        gate.finish(fails ? .failure(URLError(.timedOut)) : .success(message(2, "A 글")))
        await send.value
        #expect(vm.messages.isEmpty)
        #expect(vm.inputText.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.conversationId == nil)
        #expect(!vm.isSending)
    }

    private func message(_ id: Int, _ content: String, conversation: Int = 1) -> SupportMessageResponse {
        SupportMessageResponse(messageId: id, conversationId: conversation, senderId: 7,
                               senderRole: "USER", content: content, createdAt: nil)
    }
}

@MainActor
private final class SupportTestNetwork {
    var fetchCount = 0
    var openCount = 0
    var posts: [(Int, String)] = []
    var fetch: (Int, Int) async throws -> [SupportMessageResponse] = { _, _ in [] }
    var post: (Int, String) async throws -> SupportMessageResponse = { conversation, content in
        SupportMessageResponse(messageId: 2, conversationId: conversation, senderId: 7,
                               senderRole: "USER", content: content, createdAt: nil)
    }
    var lookup: () async throws -> SupportConversationStatus = {
        SupportConversationStatus(adminAvailable: true, conversation: nil)
    }

    func makeModel() -> SupportConversationViewModel {
        SupportConversationViewModel(
            fetchConversation: { [self] in try await lookup() },
            openConversation: { [self] in
                openCount += 1
                return SupportConversation(conversationId: 1, userId: 7, status: "OPEN", createdAt: nil, updatedAt: nil)
            },
            fetchMessages: { [self] conversation in fetchCount += 1; return try await fetch(fetchCount, conversation) },
            postMessage: { [self] conversation, content in posts.append((conversation, content)); return try await post(conversation, content) }
        )
    }
}

@MainActor
private final class SupportTestGate<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    func wait() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilStarted() async throws {
        for _ in 0..<1000 {
            if continuation != nil { return }
            await Task.yield()
        }
        throw URLError(.timedOut)
    }
    func finish(_ result: Result<Value, Error>) { continuation?.resume(with: result); continuation = nil }
}
