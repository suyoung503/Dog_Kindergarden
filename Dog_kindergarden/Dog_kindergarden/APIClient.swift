//
//  APIClient.swift
//  Dog_kindergarden
//
//  맡겨멍 REST API 연결 레이어
//

import Foundation

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// 시뮬레이터 기준 기본 주소입니다. 실제 기기에서는 Mac의 로컬 IP로 변경하세요.
    var baseURL: URL {
        let saved = UserDefaults.standard.string(forKey: "API_BASE_URL")
        return URL(string: saved ?? "https://matgyeomung-api.dog-kindergarden.workers.dev/api")!
    }

    private init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
    }

    func fetchStores() async throws -> [DogCareStore] {
        let responses: [StoreResponse] = try await request(path: "/stores", method: "GET")
        return responses.map { $0.toDomain() }
    }

    @discardableResult
    func createReservation(store: DogCareStore, startDate: Date, endDate: Date, type: ReservationKind, message: String) async throws -> ReservationResponse {
        let requestBody = ReservationCreateRequest(
            userId: 1,
            petId: 1,
            storeId: Int(store.id) ?? 1,
            startDate: startDate,
            endDate: endDate,
            reservationType: type.rawValue,
            requestMessage: message
        )
        return try await request(path: "/reservations", method: "POST", body: requestBody)
    }


    @discardableResult
    func createReview(reservationId: Int, storeId: Int, rating: Double, revisit: Bool, content: String) async throws -> ReviewResponse {
        let body = ReviewCreateRequest(
            reservationId: reservationId,
            userId: 1,
            storeId: storeId,
            rating: rating,
            revisit: revisit,
            content: content
        )
        return try await request(path: "/reviews", method: "POST", body: body)
    }

    func fetchStoreReviews(storeId: Int) async throws -> [ReviewItem] {
        let responses: [ReviewResponse] = try await request(path: "/stores/\(storeId)/reviews", method: "GET")
        return responses.map { $0.toDomain() }
    }

    func fetchPets(userId: Int = 1) async throws -> [PetProfile] {
        let responses: [PetResponse] = try await request(path: "/users/\(userId)/pets", method: "GET")
        return responses.map { $0.toDomain() }
    }

    func fetchReservations(userId: Int) async throws -> [ReservationSummary] {
        try await request(path: "/users/\(userId)/reservations", method: "GET")
    }

    @discardableResult
    func updateUser(userId: Int, nickname: String, phone: String, address: String) async throws -> UserResponse {
        let body = UserUpdateRequest(nickname: nickname, phone: phone, address: address)
        return try await request(path: "/users/\(userId)", method: "PUT", body: body)
    }

    func fetchFavorites(userId: Int) async throws -> [FavoriteStoreResponse] {
        try await request(path: "/users/\(userId)/favorites", method: "GET")
    }

    @discardableResult
    func addFavorite(userId: Int, storeKey: String, storeName: String, address: String, phone: String, storeType: String, latitude: Double, longitude: Double) async throws -> FavoriteAddResponse {
        let body = FavoriteCreateRequest(
            userId: userId,
            storeKey: storeKey,
            storeName: storeName,
            storeAddress: address,
            phone: phone,
            storeType: storeType,
            latitude: latitude,
            longitude: longitude
        )
        return try await request(path: "/favorites", method: "POST", body: body)
    }

    func removeFavorite(userId: Int, storeId: Int) async throws {
        let _: FavoriteDeleteResponse = try await request(path: "/users/\(userId)/favorites/\(storeId)", method: "DELETE")
    }

    func fetchDiaries(reservationId: Int = 1) async throws -> [DiaryEntry] {
        let responses: [DiaryResponse] = try await request(path: "/diaries/\(reservationId)", method: "GET")
        return responses.map { $0.toDomain() }
    }

    func fetchMessages(roomId: Int = 1) async throws -> [ChatMessageItem] {
        let responses: [ChatMessageResponse] = try await request(path: "/chatrooms/\(roomId)/messages", method: "GET")
        return responses.map { $0.toDomain() }
    }

    func sendMessage(roomId: Int = 1, content: String) async throws -> ChatMessageItem {
        let requestBody = ChatMessageCreateRequest(senderId: 1, messageType: "TEXT", content: content)
        let response: ChatMessageResponse = try await request(path: "/chatrooms/\(roomId)/messages", method: "POST", body: requestBody)
        return response.toDomain()
    }

    private func request<Response: Decodable>(path: String, method: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    private func request<RequestBody: Encodable, Response: Decodable>(path: String, method: String, body: RequestBody) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.badStatus
        }
        return try decoder.decode(Response.self, from: data)
    }
}

enum APIError: Error {
    case badStatus
}

enum ReservationKind: String {
    case normal = "NORMAL"
    case regular = "REGULAR"
}

struct StoreResponse: Decodable {
    let storeId: Int?
    let id: Int?
    let name: String
    let address: String?
    let roadAddress: String?
    let latitude: Double?
    let longitude: Double?
    let phone: String?
    let status: String?
    let openTime: String?
    let pickup: Bool?
    let playground: Bool?
    let largeDog: Bool?
    let priceInfo: String?

    func toDomain() -> DogCareStore {
        DogCareStore(
            id: String(storeId ?? id ?? 0),
            name: name,
            status: status ?? "영업",
            roadAddress: roadAddress ?? address ?? "",
            lotAddress: "",
            phone: phone ?? "",
            x: longitude.map { String($0) } ?? "",
            y: latitude.map { String($0) } ?? ""
        )
    }
}

struct ReservationCreateRequest: Encodable {
    let userId: Int
    let petId: Int
    let storeId: Int
    let startDate: Date
    let endDate: Date
    let reservationType: String
    let requestMessage: String
}

struct ReservationResponse: Decodable {
    let reservationId: Int?
    let id: Int?
    let status: String?
    let storeId: Int?
}

struct ReviewResponse: Decodable {
    let reviewId: Int?
    let reservationId: Int?
    let userId: Int?
    let storeId: Int?
    let rating: Double?
    let revisit: Int?
    let content: String?
    let createdAt: String?

    func toDomain() -> ReviewItem {
        ReviewItem(
            rating: rating ?? 0,
            revisit: (revisit ?? 0) == 1,
            content: content ?? "",
            createdAt: createdAt ?? "방금"
        )
    }
}


struct ReviewCreateRequest: Encodable {
    let reservationId: Int
    let userId: Int
    let storeId: Int
    let rating: Double
    let revisit: Bool
    let content: String
}

struct ReviewItem {
    let rating: Double
    let revisit: Bool
    let content: String
    let createdAt: String
}

struct PetResponse: Decodable {
    let petId: Int?
    let name: String
    let breed: String?
    let age: Int?
    let weight: Double?
    let gender: String?
    let note: String?
    let imageUrl: String?

    func toDomain() -> PetProfile {
        PetProfile(
            name: name,
            breed: breed ?? "정보 없음",
            age: age ?? 0,
            weight: weight ?? 0,
            gender: gender ?? "정보 없음",
            note: note ?? "특이사항 없음"
        )
    }
}

struct DiaryResponse: Decodable {
    let diaryId: Int?
    let content: String
    let createdAt: String?
    let mediaType: String?

    func toDomain() -> DiaryEntry {
        let icon: String
        switch mediaType {
        case "IMAGE": icon = "📷"
        case "VIDEO": icon = "🎥"
        default: icon = "📝"
        }
        return DiaryEntry(dateText: createdAt ?? "방금", content: content, mediaIcon: icon)
    }
}

struct ChatMessageResponse: Decodable {
    let messageId: Int?
    let senderId: Int?
    let senderName: String?
    let messageType: String?
    let content: String
    let createdAt: String?

    func toDomain() -> ChatMessageItem {
        let mine = senderId == 1
        return ChatMessageItem(
            sender: senderName ?? (mine ? "나" : "업체"),
            content: content,
            isMine: mine,
            isAuto: messageType == "AUTO"
        )
    }
}

struct ChatMessageCreateRequest: Encodable {
    let senderId: Int
    let messageType: String
    let content: String
}

struct ReservationSummary: Decodable {
    let reservationId: Int?
    let storeId: Int?
    let storeName: String?
    let startDate: String?
    let endDate: String?
    let reservationType: String?
    let status: String?
}

struct UserUpdateRequest: Encodable {
    let nickname: String
    let phone: String
    let address: String
}

struct UserResponse: Decodable {
    let userId: Int?
    let nickname: String?
    let phone: String?
    let address: String?
}

struct FavoriteCreateRequest: Encodable {
    let userId: Int
    let storeKey: String
    let storeName: String
    let storeAddress: String
    let phone: String
    let storeType: String
    let latitude: Double
    let longitude: Double
}

struct FavoriteStoreResponse: Decodable {
    let storeId: Int
    let storeKey: String?
    let name: String
    let address: String?
    let phone: String?
    let storeType: String?
    let latitude: Double?
    let longitude: Double?
}

struct FavoriteAddResponse: Decodable {
    let storeId: Int?
    let favorited: Bool?
}

struct FavoriteDeleteResponse: Decodable {
    let ok: Bool?
}
