import Foundation
import Testing
@testable import Dog_kindergarden

@Suite("채팅 비동기 경계와 전송 보호")
@MainActor
struct ChatRoomStateTests {
    private func dto(_ id: Int, _ content: String) -> ChatMessageDTO {
        ChatMessageDTO(message_id: id, sender_id: 2, sender_name: nil, message_type: nil, content: content, created_at: nil)
    }

    private func configure(_ vm: ChatRoomViewModel, room: Int? = 1, user: Int = 1, key: String = "store-a") {
        vm.configure(roomId: room, userId: user, storeKey: key, storeName: key, storeAddress: "주소")
    }

    @Test("먼저 시작한 조회가 늦게 끝나도 최신 메시지를 덮지 않는다")
    func latestLoadWins() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<[ChatMessageDTO]>()
        network.fetch = { call, _ in call == 1 ? try await gate.wait() : [dto(2, "최신")] }
        let vm = network.makeModel(); configure(vm)
        let old = Task { await vm.load() }; await gate.waitUntilStarted()
        await vm.load(); gate.finish(.success([dto(1, "과거")]))
        await old.value
        #expect(vm.messages.map(\.text) == ["최신"])
        #expect(network.reads.count == 1)
    }

    @Test("다른 방의 지연 응답은 새 방 기록과 읽음 사용자를 변경하지 않는다")
    func roomSwitch() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<[ChatMessageDTO]>()
        network.fetch = { _, room in room == 1 ? try await gate.wait() : [dto(20, "B 방")] }
        let vm = network.makeModel(); configure(vm)
        let old = Task { await vm.load() }; await gate.waitUntilStarted()
        configure(vm, room: 2, user: 3); await vm.load()
        gate.finish(.success([dto(10, "A 방")]))
        await old.value
        #expect(vm.messages.map(\.text) == ["B 방"])
        #expect(network.reads.map { "\($0.0):\($0.1)" } == ["2:3"])
    }

    @Test("동일 UID라도 token 또는 API 서버가 바뀌면 이전 응답과 기록을 버린다")
    func sessionSwitch() async {
        for changeServer in [false, true] {
            let network = ChatTestNetwork(), gate = ChatTestGate<[ChatMessageDTO]>()
            network.fetch = { call, _ in call == 1 ? [dto(1, "비공개 과거")] : try await gate.wait() }
            let vm = network.makeModel(); configure(vm); await vm.load()
            let old = Task { await vm.refresh() }; await gate.waitUntilStarted()
            if changeServer { network.baseURL = URL(string: "https://b.invalid/api")! }
            else { network.token = "session-b" }
            gate.finish(.success([dto(1, "A"), dto(2, "A 추가")]))
            await old.value
            #expect(vm.messages.isEmpty)
            #expect(network.reads.count == 1)
        }
    }

    @Test("전송 중 재진입은 두 번째 요청을 만들거나 새 초안을 지우지 않는다")
    func duplicateSend() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<Void>()
        network.post = { call in if call == 1 { try await gate.wait() } }
        let vm = network.makeModel(); configure(vm); vm.inputText = "첫 글"
        let first = Task { await vm.send() }; await gate.waitUntilStarted()
        vm.inputText = "다음 초안"; await vm.send()
        #expect(network.posts.count == 1)
        #expect(vm.inputText == "다음 초안")
        gate.finish(.success(())); await first.value
    }

    @Test("전송 실패가 기다리는 동안 입력한 새 초안을 덮지 않는다")
    func preserveNewDraft() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<Void>()
        network.post = { _ in try await gate.wait() }
        let vm = network.makeModel(); configure(vm); vm.inputText = "실패할 글"
        let send = Task { await vm.send() }; await gate.waitUntilStarted()
        vm.inputText = "작성 중인 다음 글"
        gate.finish(.failure(URLError(.notConnectedToInternet))); await send.value
        #expect(vm.inputText == "작성 중인 다음 글")
        #expect(vm.errorMessage != nil)
    }

    @Test("다음 초안이 없을 때는 실패한 전송 원문을 복원한다")
    func restoreFailedDraft() async {
        let network = ChatTestNetwork()
        network.post = { _ in throw URLError(.notConnectedToInternet) }
        let vm = network.makeModel(); configure(vm); vm.inputText = "  다시 보낼 글  "
        await vm.send()
        #expect(vm.inputText == "다시 보낼 글")
        #expect(vm.messages.isEmpty)
        #expect(!vm.isSending)
    }

    @Test("이전 방 전송 실패는 새 방 초안과 오류를 바꾸지 않는다")
    func staleSendFailure() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<Void>()
        network.post = { _ in try await gate.wait() }
        let vm = network.makeModel(); configure(vm); vm.inputText = "A 전송"
        let send = Task { await vm.send() }; await gate.waitUntilStarted()
        configure(vm, room: 2); vm.inputText = "B 초안"
        gate.finish(.failure(URLError(.timedOut))); await send.value
        #expect(vm.inputText == "B 초안")
        #expect(vm.errorMessage == nil)
    }

    @Test("전송 전에 시작한 조회가 늦게 도착해도 전송한 말풍선을 지우지 않는다")
    func refreshBeforeSend() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<[ChatMessageDTO]>()
        network.fetch = { call, _ in call == 1 ? try await gate.wait() : [dto(2, "방금 전송")] }
        let vm = network.makeModel(); configure(vm)
        let refresh = Task { await vm.refresh() }; await gate.waitUntilStarted()
        vm.inputText = "방금 전송"; await vm.send()
        gate.finish(.success([])); await refresh.value
        for _ in 0..<1000 { if vm.messages.last?.id == "message:2" { break }; await Task.yield() }
        #expect(vm.messages.map(\.text) == ["방금 전송"])
    }

    @Test("진입 조회를 전송이 중단했으면 전송 후 기존 기록까지 다시 읽는다")
    func initialLoadInterruptedBySend() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<[ChatMessageDTO]>()
        network.fetch = { call, _ in call == 1 ? try await gate.wait() : [dto(1, "기존 기록"), dto(2, "새 전송")] }
        let vm = network.makeModel(); configure(vm)
        let load = Task { await vm.load() }; await gate.waitUntilStarted()
        vm.inputText = "새 전송"; await vm.send()
        gate.finish(.success([dto(1, "기존 기록")])); await load.value
        for _ in 0..<1000 { if network.calls == 2 && vm.messages.count == 2 { break }; await Task.yield() }
        #expect(network.calls == 2)
        #expect(vm.messages.map(\.text) == ["기존 기록", "새 전송"])
    }

    @Test("진입 조회 중 전송 실패해도 기록을 복구하고 실패 안내와 초안을 유지한다")
    func failedSendRestoresInitialHistory() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<[ChatMessageDTO]>()
        network.fetch = { call, _ in call == 1 ? try await gate.wait() : [dto(1, "기존 기록")] }
        network.post = { _ in throw URLError(.notConnectedToInternet) }
        let vm = network.makeModel(); configure(vm)
        let load = Task { await vm.load() }; await gate.waitUntilStarted()
        vm.inputText = "실패한 글"; await vm.send()
        gate.finish(.success([dto(1, "과거 스냅샷")])); await load.value
        for _ in 0..<1000 { if network.calls == 2 && vm.messages.count == 1 { break }; await Task.yield() }
        #expect(network.calls == 2)
        #expect(vm.messages.map(\.text) == ["기존 기록"])
        #expect(vm.inputText == "실패한 글")
        #expect(vm.errorMessage != nil)
    }

    @Test("개수가 같아도 서버 메시지 ID나 내용이 바뀌면 반영한다")
    func sameCountChanges() async {
        let network = ChatTestNetwork()
        network.fetch = { call, _ in [dto(call == 1 ? 1 : 2, call == 1 ? "이전" : "새 메시지")] }
        let vm = network.makeModel(); configure(vm); await vm.load(); await vm.refresh()
        #expect(vm.messages.map(\.text) == ["새 메시지"])
    }

    @Test("현재 방 권한이 사라지면 이전 비공개 기록을 비운다", arguments: [401, 403, 404])
    func accessFailure(status: Int) async {
        let network = ChatTestNetwork()
        network.fetch = { call, _ in
            if call == 1 { return [dto(1, "비공개")] }
            throw APIError.httpStatus(status)
        }
        let vm = network.makeModel(); configure(vm); await vm.load(); await vm.refresh()
        #expect(vm.messages.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("조회 재시도가 성공하면 이전 오류를 지운다")
    func clearRecoveredError() async {
        let network = ChatTestNetwork()
        network.fetch = { call, _ in
            if call == 1 { throw URLError(.notConnectedToInternet) }
            return [dto(1, "복구")]
        }
        let vm = network.makeModel(); configure(vm); await vm.load(); await vm.load()
        #expect(vm.messages.map(\.text) == ["복구"])
        #expect(vm.errorMessage == nil)
    }

    @Test("첫 문의 방 생성 도중 문맥이 바뀌면 옛 방에 후속 전송하지 않는다")
    func staleRoomCreation() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<Int>()
        network.open = { try await gate.wait() }
        let vm = network.makeModel(); configure(vm, room: nil); vm.inputText = "A 문의"
        let send = Task { await vm.send() }; await gate.waitUntilStarted()
        configure(vm, room: 2, user: 3, key: "store-b")
        gate.finish(.success(10)); await send.value
        #expect(vm.roomId == 2)
        #expect(network.posts.isEmpty)
    }

    @Test("취소를 무시한 조회 완료는 기록과 읽음을 바꾸지 않는다")
    func canceledLoad() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<[ChatMessageDTO]>()
        network.fetch = { _, _ in try await gate.wait() }
        let vm = network.makeModel(); configure(vm)
        let task = Task { await vm.load() }; await gate.waitUntilStarted()
        task.cancel(); gate.finish(.success([dto(1, "취소된 응답")]))
        await task.value
        #expect(vm.messages.isEmpty)
        #expect(network.reads.isEmpty)
        #expect(!vm.isLoading)
    }

    @Test("종료된 화면의 늦은 응답과 정리가 새 세대를 지우지 않는다")
    func invalidatedView() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<[ChatMessageDTO]>()
        network.fetch = { call, _ in call == 1 ? try await gate.wait() : [dto(2, "새 화면")] }
        let vm = network.makeModel(); configure(vm)
        let oldGeneration = vm.generation
        let task = Task { await vm.load() }; await gate.waitUntilStarted()
        vm.invalidate(); configure(vm); await vm.load()
        gate.finish(.success([dto(1, "옛 화면")])); await task.value
        vm.invalidate(generation: oldGeneration)
        #expect(vm.messages.map(\.text) == ["새 화면"])
    }

    @Test("첫 문의는 한 방에 한 번 전송하고 전체 기록과 시스템 안내를 다시 읽는다")
    func firstInquiry() async {
        let network = ChatTestNetwork()
        network.fetch = { _, _ in [ChatMessageDTO(message_id: 1, sender_id: 0, sender_name: nil, message_type: nil, content: "시스템 안내", created_at: nil),
                                  ChatMessageDTO(message_id: 2, sender_id: 1, sender_name: nil, message_type: nil, content: "첫 문의", created_at: nil)] }
        let vm = network.makeModel(); configure(vm, room: nil); vm.inputText = " 첫 문의 "
        await vm.send()
        for _ in 0..<1000 { if vm.messages.count == 2 { break }; await Task.yield() }
        #expect(vm.roomId == 10)
        #expect(network.posts.map { "\($0.0):\($0.1):\($0.2)" } == ["10:1:첫 문의"])
        #expect(vm.messages.map(\.from) == [.system, .me])
        #expect(vm.messages.map(\.id) == ["message:1", "message:2"])
        #expect(vm.inputText.isEmpty)
        #expect(!vm.isSending)
    }

    @Test("전송 중 도착한 여러 갱신은 전송 후 한 번 재조회한다")
    func refreshAfterSending() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<Void>()
        network.post = { _ in try await gate.wait() }
        network.fetch = { _, _ in [dto(9, "서버 확인")] }
        let vm = network.makeModel(); configure(vm); vm.inputText = "전송"
        let send = Task { await vm.send() }; await gate.waitUntilStarted()
        await vm.refresh(); await vm.refresh()
        #expect(network.calls == 0)
        gate.finish(.success(())); await send.value
        for _ in 0..<1000 { if vm.messages.last?.text == "서버 확인" { break }; await Task.yield() }
        #expect(network.calls == 1)
        #expect(vm.messages.map(\.text) == ["서버 확인"])
    }

    @Test("토큰 없이 조회나 전송을 시도하지 않는다")
    func missingCredentials() async {
        for token in [nil, ""] as [String?] {
            let network = ChatTestNetwork(); network.token = token
            let vm = network.makeModel(); configure(vm); vm.inputText = "로그인 필요"
            await vm.load(); await vm.send()
            #expect(network.calls == 0)
            #expect(network.posts.isEmpty)
        }
    }

    @Test("방 생성 작업 취소 후 후속 전송은 실행하지 않는다")
    func canceledRoomCreation() async {
        let network = ChatTestNetwork(), gate = ChatTestGate<Int>()
        network.open = { try await gate.wait() }
        let vm = network.makeModel(); configure(vm, room: nil); vm.inputText = "취소된 문의"
        let send = Task { await vm.send() }; await gate.waitUntilStarted()
        send.cancel(); gate.finish(.success(10)); await send.value
        #expect(network.posts.isEmpty)
        #expect(vm.roomId == nil)
        #expect(!vm.isSending)
    }

    @Test("같은 서버 메시지 재조회는 행 identity를 유지한다")
    func stableRows() async {
        let network = ChatTestNetwork(); network.fetch = { _, _ in [dto(7, "같은 글")] }
        let vm = network.makeModel(); configure(vm); await vm.load()
        let firstID = vm.messages.first?.id
        await vm.load()
        #expect(vm.messages.first?.id == firstID)
    }
}

@MainActor
private final class ChatTestNetwork {
    var token: String? = "session-a"
    var baseURL = URL(string: "https://a.invalid/api")!
    var calls = 0
    var reads: [(Int, Int)] = []
    var posts: [(Int, Int, String)] = []
    var fetch: (Int, Int) async throws -> [ChatMessageDTO] = { _, _ in [] }
    var post: (Int) async throws -> Void = { _ in }
    var open: () async throws -> Int = { 10 }

    func makeModel() -> ChatRoomViewModel {
        ChatRoomViewModel(
            fetchMessages: { [self] room in calls += 1; return try await fetch(calls, room) },
            createRoom: { [self] _, _, _, _ in try await open() },
            postMessage: { [self] room, user, text in posts.append((room, user, text)); try await post(posts.count) },
            readRoom: { [self] room, user in reads.append((room, user)) },
            credentials: { [self] in (token, baseURL) }
        )
    }
}

@MainActor
private final class ChatTestGate<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    func wait() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitUntilStarted() async { while continuation == nil { await Task.yield() } }
    func finish(_ result: Result<Value, Error>) { continuation?.resume(with: result); continuation = nil }
}
