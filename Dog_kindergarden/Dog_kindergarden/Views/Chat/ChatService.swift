import Foundation

// 채팅 네트워킹 — 방 조회/생성, 목록, 메시지 로드/전송
// 백엔드: /api/chatrooms/* , /api/users/:id/chatrooms

struct ChatMessageDTO: Decodable, Identifiable {
    let message_id: Int
    let sender_id: Int
    let sender_name: String?
    let message_type: String?
    let content: String
    let created_at: String?

    var id: Int { message_id }
}

struct ChatRoomSummary: Decodable, Identifiable {
    let room_id: Int
    let store_id: Int?
    let store_name: String?
    let last_message: String?
    let last_time: String?

    var id: Int { room_id }
}

// 사장님 문의함 목록 행 — 손님 닉네임 포함
struct OwnerChatRoomSummary: Decodable, Identifiable {
    let room_id: Int
    let store_id: Int?
    let store_name: String?
    let customer_name: String?
    let last_message: String?
    let last_time: String?

    var id: Int { room_id }
}

enum ChatService {
    private static let base = apiBaseURL

    /// 조회 전용(쓰기 없음): (user, store) 방이 있으면 room_id, 없으면 nil
    static func lookup(userId: Int, storeKey: String) async -> Int? {
        var comps = URLComponents(string: "\(base)/api/chatrooms/lookup")!
        comps.queryItems = [
            URLQueryItem(name: "user_id", value: String(userId)),
            URLQueryItem(name: "store_key", value: storeKey),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["room_id"] as? Int
        } catch {
            return nil
        }
    }

    /// 내 채팅방 목록 (메시지가 1개 이상 있는 방만)
    static func rooms(userId: Int) async throws -> [ChatRoomSummary] {
        let url = URL(string: "\(base)/api/users/\(userId)/chatrooms")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([ChatRoomSummary].self, from: data)
    }

    /// 사장님 문의함: 내 가게로 온 채팅방 목록 (메시지가 1개 이상 있는 방만)
    static func ownerRooms(ownerId: Int) async throws -> [OwnerChatRoomSummary] {
        let url = URL(string: "\(base)/api/owners/\(ownerId)/chatrooms")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([OwnerChatRoomSummary].self, from: data)
    }

    /// 방의 메시지 목록
    static func messages(roomId: Int) async throws -> [ChatMessageDTO] {
        let url = URL(string: "\(base)/api/chatrooms/\(roomId)/messages")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([ChatMessageDTO].self, from: data)
    }

    /// 문의 방 get-or-create → room_id (첫 메시지 전송 시 호출)
    static func openRoom(
        userId: Int, storeKey: String, storeName: String, storeAddress: String
    ) async throws -> Int {
        let url = URL(string: "\(base)/api/chatrooms")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": userId,
            "store_key": storeKey,
            "store_name": storeName,
            "store_address": storeAddress,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let roomId = json?["room_id"] as? Int else {
            throw URLError(.cannotParseResponse)
        }
        return roomId
    }

    /// 메시지 전송
    static func send(roomId: Int, senderId: Int, content: String) async throws {
        let url = URL(string: "\(base)/api/chatrooms/\(roomId)/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "sender_id": senderId,
            "content": content,
        ])
        _ = try await URLSession.shared.data(for: req)
    }

    /// 안 읽은 메시지 수 — 홈 종 아이콘 빨간 점용 (보호자/사장님 시점은 서버가 계정 역할로 판단)
    static func unreadCount(userId: Int) async -> Int {
        let url = URL(string: "\(base)/api/users/\(userId)/unread-count")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        return json["unread"] as? Int ?? 0
    }

    /// 방 열람 읽음 처리 — 현재 마지막 메시지까지 읽음으로 기록 (실패해도 다음 열람에서 재시도되므로 무시)
    static func markRead(roomId: Int, userId: Int) async {
        let url = URL(string: "\(base)/api/chatrooms/\(roomId)/read")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["user_id": userId])
        _ = try? await URLSession.shared.data(for: req)
    }
}
