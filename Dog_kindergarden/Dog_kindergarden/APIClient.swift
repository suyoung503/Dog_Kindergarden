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

    func cancelReservation(reservationId: Int) async throws {
        let _: ReservationCancelResponse = try await request(path: "/reservations/\(reservationId)/cancel", method: "PATCH")
    }

    // 사장님이 받은 예약 요청 — 내 가게(owner_id)로 온 REQUEST만
    func fetchPendingReservations(ownerId: Int) async throws -> [PendingReservation] {
        try await request(path: "/owners/\(ownerId)/reservations/pending", method: "GET")
    }

    func confirmReservation(reservationId: Int) async throws {
        let _: ReservationCancelResponse = try await request(path: "/reservations/\(reservationId)/confirm", method: "PATCH")
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

    // 사장님-가게 연결: 마이페이지 '내 가게'에서 상호명 검색으로 등록
    @discardableResult
    func claimStore(userId: Int, storeKey: String, storeName: String, storeAddress: String) async throws -> StoreClaimResponse {
        let body = StoreClaimRequest(userId: userId, storeKey: storeKey, storeName: storeName, storeAddress: storeAddress)
        return try await request(path: "/stores/claim", method: "POST", body: body)
    }

    func fetchOwnerStores(userId: Int) async throws -> [OwnerStoreResponse] {
        try await request(path: "/owners/\(userId)/stores", method: "GET")
    }

    // 내 가게 등록 해제 (잘못 등록 시 복구 경로)
    func unclaimStore(userId: Int, storeId: Int) async throws {
        let _: StoreUnclaimResponse = try await request(path: "/owners/\(userId)/stores/\(storeId)", method: "DELETE")
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

struct PetProfile {
    let name: String
    let breed: String
    let age: Int
    let weight: Double
    let gender: String
    let note: String
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

struct ReservationSummary: Decodable {
    let reservationId: Int?
    let storeId: Int?
    let storeName: String?
    let storeType: String?
    let startDate: String?
    let endDate: String?
    let reservationType: String?
    let status: String?
}

struct ReservationCancelResponse: Decodable {
    let ok: Bool?
}

struct PendingReservation: Decodable {
    let reservationId: Int?
    let storeName: String?
    let storeType: String?
    let petName: String?
    let startDate: String?
    let reservationType: String?
    let requestMessage: String?
}

struct StoreClaimRequest: Encodable {
    let userId: Int
    let storeKey: String
    let storeName: String
    let storeAddress: String
}

struct StoreClaimResponse: Decodable {
    let storeId: Int?
    let ownerId: Int?
}

struct StoreUnclaimResponse: Decodable {
    let ok: Bool?
}

struct OwnerStoreResponse: Decodable {
    let storeId: Int?
    let storeKey: String?
    let name: String?
    let address: String?
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
