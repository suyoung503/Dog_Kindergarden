import Foundation
import Observation

// 공유에는 공개된 가게 식별자만 담는다. 계정/토큰/전화번호를 URL에 넣지 않는다.
enum StoreShareLink {
    private static let publicPage = "https://matgyeomung-api.dog-kindergarden.workers.dev/store"

    static func publicURL(storeKey: String) -> URL? {
        makeURL(base: publicPage, storeKey: storeKey)
    }

    static func appURL(storeKey: String) -> URL? {
        makeURL(base: "matgyeomung://store", storeKey: storeKey)
    }

    static func storeKey(from url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "matgyeomung", parts.host == "store", parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1,
              items[0].name == "key", let key = items[0].value, valid(key) else { return nil }
        return key
    }

    private static func makeURL(base: String, storeKey: String) -> URL? {
        guard valid(storeKey), var parts = URLComponents(string: base) else { return nil }
        parts.queryItems = [URLQueryItem(name: "key", value: storeKey)]
        // '+'도 값으로 보존한다 (브라우저 URLSearchParams는 원시 '+'를 공백으로 읽는다).
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }

    private static func valid(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 512
            && key == key.trimmingCharacters(in: .whitespacesAndNewlines)
            && !key.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

// SceneDelegate가 UI 생성 전에 받은 콜드 링크도 로그인 완료까지 메모리에 보관한다.
@Observable
@MainActor
final class StoreShareInbox {
    struct Request: Equatable {
        let id = UUID()
        let storeKey: String
    }

    static let shared = StoreShareInbox()
    private(set) var pending: Request?

    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let key = StoreShareLink.storeKey(from: url) else { return false }
        pending = Request(storeKey: key)
        return true
    }

    func consume(_ request: Request) {
        if pending == request { pending = nil }
    }
}
