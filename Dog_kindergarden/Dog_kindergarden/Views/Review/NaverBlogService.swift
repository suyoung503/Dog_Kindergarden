import Foundation
import Observation

// 네이버 블로그 검색 — 가게 이름으로 실제 방문 후기 블로그 글을 가져옴
// 키: Info.plist의 NAVER_CLIENT_ID / NAVER_CLIENT_SECRET (네이버 개발자센터 검색 API)

struct BlogPost: Identifiable {
    let id = UUID()
    let title: String      // HTML 태그 제거됨
    let snippet: String    // 요약 (HTML 태그 제거됨)
    let link: String
    let blogger: String
    let date: String       // yyyy.MM.dd
}

@Observable
final class NaverBlogService {
    var posts: [BlogPost] = []
    var isLoading = false

    private var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "NAVER_CLIENT_ID") as? String ?? ""
    }
    private var clientSecret: String {
        Bundle.main.object(forInfoDictionaryKey: "NAVER_CLIENT_SECRET") as? String ?? ""
    }

    private struct Response: Decodable {
        let items: [Item]
        struct Item: Decodable {
            let title: String
            let link: String
            let description: String
            let bloggername: String
            let postdate: String?
        }
    }

    func load(storeName: String, region: String = "") async {
        let id = clientID, secret = clientSecret
        guard !id.isEmpty, id != "[NAVER_CLIENT_ID]",
              !secret.isEmpty, secret != "[NAVER_CLIENT_SECRET]" else { return }

        isLoading = true
        defer { isLoading = false }

        let query = region.isEmpty ? storeName : "\(region) \(storeName)"
        var comps = URLComponents(string: "https://openapi.naver.com/v1/search/blog.json")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "display", value: "5"),
            URLQueryItem(name: "sort", value: "sim"),
        ]
        guard let url = comps.url else { return }

        var req = URLRequest(url: url)
        req.setValue(id, forHTTPHeaderField: "X-Naver-Client-Id")
        req.setValue(secret, forHTTPHeaderField: "X-Naver-Client-Secret")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let mapped = decoded.items.map { item in
                BlogPost(
                    title: item.title.strippedHTML,
                    snippet: item.description.strippedHTML,
                    link: item.link,
                    blogger: item.bloggername,
                    date: Self.formatDate(item.postdate)
                )
            }
            await MainActor.run { self.posts = mapped }
        } catch {
            #if DEBUG
            print("⚠️ 네이버 블로그 검색 실패: \(error)")
            #endif
        }
    }

    private static func formatDate(_ raw: String?) -> String {
        guard let r = raw, r.count == 8 else { return "" }
        let y = r.prefix(4), m = r.dropFirst(4).prefix(2), d = r.dropFirst(6).prefix(2)
        return "\(y).\(m).\(d)"
    }
}

private extension String {
    // <b>, &amp; 등 HTML 태그·엔티티 제거
    var strippedHTML: String {
        var s = replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
