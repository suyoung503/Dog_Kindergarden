//
//  APIClient.swift
//  Dog_kindergarden
//
//  맡겨멍 REST API 연결 레이어
//

import Foundation
import Security

extension Notification.Name {
    static let apiSessionInvalidated = Notification.Name("apiSessionInvalidated")
}

enum APIEnvironment {
    private static let productionAPI = "https://matgyeomung-api.dog-kindergarden.workers.dev/api"

    static var apiBaseURL: URL {
        let raw = UserDefaults.standard.string(forKey: "API_BASE_URL") ?? productionAPI
        var url = URL(string: raw) ?? URL(string: productionAPI)!
        if url.lastPathComponent != "api" {
            url.appendPathComponent("api")
        }
        return url
    }

    static var isLocalDevelopment: Bool {
        guard let host = apiBaseURL.host else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static var privacyPolicyURL: URL {
        apiBaseURL.deletingLastPathComponent().appendingPathComponent("privacy")
    }

    static var supportURL: URL {
        apiBaseURL.deletingLastPathComponent().appendingPathComponent("support")
    }
}

enum AuthTokenStore {
    private static let service = "net.suyoung.Dog-kindergarden.api-session"
    private static let account = "current"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum APITransport {
    static func request(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthTokenStore.load(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var authorized = request
        if authorized.value(forHTTPHeaderField: "Authorization") == nil,
           let token = AuthTokenStore.load(), !token.isEmpty {
            authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: authorized)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatus
        }
        handleUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
        return (data, http)
    }

    static func handleUnauthorized(_ statusCode: Int) {
        guard statusCode == 401, AuthTokenStore.load() != nil else { return }
        AuthTokenStore.clear()
        NotificationCenter.default.post(name: .apiSessionInvalidated, object: nil)
    }
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// 시뮬레이터 기준 기본 주소입니다. 실제 기기에서는 Mac의 로컬 IP로 변경하세요.
    var baseURL: URL {
        APIEnvironment.apiBaseURL
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

    func fetchPets(userId: Int) async throws -> [PetProfile] {
        let responses: [PetResponse] = try await request(path: "/users/\(userId)/pets", method: "GET")
        return responses.map { $0.toDomain() }
    }

    func fetchReservations(userId: Int) async throws -> [ReservationSummary] {
        try await request(path: "/users/\(userId)/reservations", method: "GET")
    }

    // byOwner: 사장님 취소면 서버가 고객 채팅방에 취소 안내 자동 메시지를 남긴다
    func cancelReservation(reservationId: Int, byOwner: Bool = false) async throws {
        if byOwner {
            let _: ReservationCancelResponse = try await request(path: "/reservations/\(reservationId)/cancel", method: "PATCH", body: ReservationCancelRequest(byOwner: true))
        } else {
            let _: ReservationCancelResponse = try await request(path: "/reservations/\(reservationId)/cancel", method: "PATCH")
        }
    }

    // 사장님이 받은 예약 요청 — 내 가게(owner_id)로 온 REQUEST만
    func fetchPendingReservations(ownerId: Int) async throws -> [PendingReservation] {
        try await request(path: "/owners/\(ownerId)/reservations/pending", method: "GET")
    }

    func confirmReservation(reservationId: Int) async throws {
        let _: ReservationCancelResponse = try await request(path: "/reservations/\(reservationId)/confirm", method: "PATCH")
    }

    // MARK: - 알림장(diary)

    // 사장님 '맡은 아이들' — 내 가게로 온 확정(CONFIRMED) 예약
    func fetchConfirmedReservations(ownerId: Int) async throws -> [PendingReservation] {
        try await request(path: "/owners/\(ownerId)/reservations/confirmed", method: "GET")
    }

    func fetchDiaries(reservationId: Int) async throws -> [DiaryEntry] {
        try await request(path: "/reservations/\(reservationId)/diaries", method: "GET")
    }

    // 엔트리 생성 — 서버가 보호자 채팅방에 새 알림장 도착 자동 메시지를 남긴다
    @discardableResult
    func createDiary(reservationId: Int, content: String) async throws -> DiaryEntry {
        try await request(path: "/reservations/\(reservationId)/diaries", method: "POST", body: DiaryContentRequest(content: content))
    }

    // 엔트리 수정 — 자동 메시지 없음
    @discardableResult
    func updateDiary(diaryId: Int, content: String) async throws -> DiaryEntry {
        try await request(path: "/diaries/\(diaryId)", method: "PATCH", body: DiaryContentRequest(content: content))
    }

    // 엔트리 삭제 — 자동 메시지 없음
    func deleteDiary(diaryId: Int) async throws {
        let _: ReservationCancelResponse = try await request(path: "/diaries/\(diaryId)", method: "DELETE")
    }

    @discardableResult
    func updateUser(userId: Int, nickname: String, phone: String, address: String) async throws -> UserResponse {
        let body = UserUpdateRequest(nickname: nickname, phone: phone, address: address)
        return try await request(path: "/users/\(userId)", method: "PUT", body: body)
    }

    @discardableResult
    func deleteAccount(userId: Int) async throws -> AccountDeletionResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("users/\(userId)/account"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthTokenStore.load(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus }
        APITransport.handleUnauthorized(http.statusCode)
        if http.statusCode == 409,
           let blocked = try? decoder.decode(AccountDeletionBlockedResponse.self, from: data),
           blocked.code == "ACTIVE_RESERVATIONS" {
            throw AccountDeletionError.activeReservations(
                customer: blocked.activeReservations,
                owner: blocked.activeOwnedReservations
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
        return try decoder.decode(AccountDeletionResponse.self, from: data)
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

    func fetchMyStoreOwnerApplications(userId: Int) async throws -> [StoreOwnerApplication] {
        try await request(path: "/users/\(userId)/store-owner-applications", method: "GET")
    }

    func fetchPendingStoreOwnerApplications() async throws -> [StoreOwnerApplication] {
        try await request(path: "/owner-applications", method: "GET")
    }

    func fetchPendingStoreOwnerApplicationCount() async throws -> Int {
        let response: PendingOwnerApplicationCount = try await request(path: "/owner-applications/pending-count", method: "GET")
        return response.count
    }

    func approveStoreOwnerApplication(id: Int) async throws {
        let _: StoreOwnerApplicationActionResponse = try await request(path: "/owner-applications/\(id)/approve", method: "PATCH")
    }

    func rejectStoreOwnerApplication(id: Int) async throws {
        let _: StoreOwnerApplicationActionResponse = try await request(path: "/owner-applications/\(id)/reject", method: "PATCH")
    }

    func fetchOwnerStores(userId: Int) async throws -> [OwnerStoreResponse] {
        try await request(path: "/owners/\(userId)/stores", method: "GET")
    }

    // 지도 핀 소스 — 선별(큐레이션)된 서울 가게 전체
    func fetchStores() async throws -> [StoreDetailResponse] {
        try await request(path: "/stores", method: "GET")
    }

    // 공지사항 — 목록은 본문 제외, 상세는 본문 포함(body가 nil이면 목록에서 온 요약)
    func fetchNotices() async throws -> [Notice] {
        try await request(path: "/notices", method: "GET")
    }

    func fetchNotice(id: Int) async throws -> Notice? {
        try await request(path: "/notices/\(id)", method: "GET")
    }

    // MARK: - 고객센터 1:1 문의

    func fetchMySupportConversation() async throws -> SupportConversationStatus {
        try await request(path: "/support/conversation", method: "GET")
    }

    @discardableResult
    func openSupportConversation() async throws -> SupportConversation {
        try await request(path: "/support/conversation", method: "POST")
    }

    func fetchSupportConversations() async throws -> [SupportConversationSummary] {
        try await request(path: "/support/conversations", method: "GET")
    }

    func fetchSupportMessages(conversationId: Int) async throws -> [SupportMessageResponse] {
        try await request(path: "/support/conversations/\(conversationId)/messages", method: "GET")
    }

    @discardableResult
    func sendSupportMessage(conversationId: Int, content: String) async throws -> SupportMessageResponse {
        try await request(
            path: "/support/conversations/\(conversationId)/messages",
            method: "POST",
            body: SupportMessageCreateRequest(content: content)
        )
    }

    func fetchStoreDetail(storeKey: String) async throws -> StoreDetailResponse? {
        var components = URLComponents(url: baseURL.appendingPathComponent("stores/detail"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "storeKey", value: storeKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
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
        var authorized = request
        if let token = AuthTokenStore.load(), !token.isEmpty {
            authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: authorized)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.badStatus }
        APITransport.handleUnauthorized(httpResponse.statusCode)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? decoder.decode(APIErrorResponse.self, from: data)
            if payload?.code != nil || payload?.message != nil {
                throw APIError.server(
                    status: httpResponse.statusCode,
                    code: payload?.code,
                    message: payload?.message
                )
            }
            throw APIError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

enum APIError: Error {
    case badStatus
    case httpStatus(Int)
    case server(status: Int, code: String?, message: String?)
}

private struct APIErrorResponse: Decodable {
    let code: String?
    let message: String?
}

enum AccountDeletionError: Error {
    case activeReservations(customer: Int, owner: Int)
}

struct AccountDeletionResponse: Decodable {
    let ok: Bool
    let deletedAt: String?
}

private struct AccountDeletionBlockedResponse: Decodable {
    let code: String
    let activeReservations: Int
    let activeOwnedReservations: Int
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
    let petName: String?
    let startDate: String?
    let endDate: String?
    let reservationType: String?
    let status: String?
}

struct ReservationCancelResponse: Decodable {
    let ok: Bool?
}

// 사장님 취소 표시 — 인코더가 snake_case(by_owner)로 변환해 서버에 전달
struct ReservationCancelRequest: Encodable {
    let byOwner: Bool
}

struct PendingReservation: Decodable, Identifiable {
    var id: Int { reservationId ?? 0 }
    let reservationId: Int?
    let storeName: String?
    let storeType: String?
    let petName: String?
    let petBreed: String?
    let petAge: Int?
    let petWeight: Double?
    let petGender: String?
    let petNote: String?
    let userName: String?
    let userPhone: String?
    let userAddress: String?
    let startDate: String?
    let reservationType: String?
    let requestMessage: String?
}

// 알림장 엔트리 — 사진(photos)은 R2 활성화 전까지 항상 빈 배열
struct DiaryPhoto: Decodable, Identifiable {
    var id: Int { photoId ?? 0 }
    let photoId: Int?
    let url: String?
}

struct DiaryEntry: Decodable, Identifiable {
    var id: Int { diaryId ?? 0 }
    let diaryId: Int?
    let content: String?
    let createdAt: String?
    let photos: [DiaryPhoto]?
}

struct DiaryContentRequest: Encodable {
    let content: String
}

struct StoreClaimRequest: Encodable {
    let userId: Int
    let storeKey: String
    let storeName: String
    let storeAddress: String
}

struct StoreClaimResponse: Decodable {
    let applicationId: Int?
    let storeId: Int?
    let ownerId: Int?
    let status: String?
}

struct StoreOwnerApplication: Decodable, Identifiable {
    var id: Int { applicationId }
    let applicationId: Int
    let userId: Int
    let storeId: Int
    let status: String
    let appliedAt: String?
    let reviewedAt: String?
    let storeKey: String?
    let storeName: String?
    let storeAddress: String?
    let nickname: String?
    let email: String?
    let phone: String?
    let address: String?
    let isOwner: Int?
}

struct PendingOwnerApplicationCount: Decodable {
    let count: Int
}

struct StoreOwnerApplicationActionResponse: Decodable {
    let ok: Bool?
    let status: String?
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

struct StoreImageResponse: Decodable, Identifiable {
    var id: Int { imageId ?? 0 }
    let imageId: Int?
    let imageUrl: String?
    let sortOrder: Int?
}

struct StoreDetailResponse: Decodable {
    let storeId: Int?
    let storeKey: String?
    let name: String?
    let address: String?
    let phone: String?
    let status: String?
    let latitude: Double?
    let longitude: Double?
    let openTime: String?
    let pickup: Int?
    let playground: Int?
    let largeDog: Int?
    let priceInfo: String?
    let imageUrl: String?
    let storeType: String?
    let images: [StoreImageResponse]?
    let partnerStatus: String?
    let isPartner: Bool?
    let canBook: Bool?
    let canChat: Bool?
    let canDiary: Bool?
    let canReview: Bool?
}

struct Notice: Decodable, Identifiable {
    let id: Int
    let title: String
    let createdAt: String
    let body: String?
}

struct SupportConversation: Decodable, Identifiable {
    var id: Int { conversationId }
    let conversationId: Int
    let userId: Int
    let status: String
    let createdAt: String?
    let updatedAt: String?
}

struct SupportConversationStatus: Decodable {
    let adminAvailable: Bool
    let conversation: SupportConversation?
}

struct SupportConversationSummary: Decodable, Identifiable {
    var id: Int { conversationId }
    let conversationId: Int
    let userId: Int
    let status: String
    let createdAt: String?
    let updatedAt: String?
    let userName: String?
    let userEmail: String?
    let lastMessage: String?
    let lastMessageAt: String?
}

struct SupportMessageResponse: Decodable, Identifiable {
    var id: Int { messageId }
    let messageId: Int
    let conversationId: Int
    let senderId: Int
    let senderRole: String
    let content: String
    let createdAt: String?
}

private struct SupportMessageCreateRequest: Encodable {
    let content: String
}
