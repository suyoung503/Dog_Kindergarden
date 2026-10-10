import Foundation
import Observation

// 네이버 블로그 검색 결과는 Worker가 D1의 가게 정보로 조회한다.
// 앱은 Naver Client Secret이나 임의 검색어를 보유·전송하지 않는다.

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

    private struct Item: Decodable {
        let title: String
        let snippet: String
        let link: String
        let blogger: String
        let date: String
    }

    func load(storeKey: String) async {
        isLoading = true
        defer { isLoading = false }

        var comps = URLComponents(
            url: APIEnvironment.apiBaseURL.appendingPathComponent("store-enrichment/blogs"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "storeKey", value: storeKey),
        ]
        guard let url = comps.url else { return }

        do {
            let (data, _) = try await APITransport.data(for: APITransport.request(url: url))
            let decoded = try JSONDecoder().decode([Item].self, from: data)
            let mapped = decoded.map { item in
                BlogPost(
                    title: item.title,
                    snippet: item.snippet,
                    link: item.link,
                    blogger: item.blogger,
                    date: item.date
                )
            }
            await MainActor.run { self.posts = mapped }
        } catch {
            await MainActor.run { self.posts = [] }
            #if DEBUG
            print("⚠️ 네이버 블로그 검색 실패: \(error)")
            #endif
        }
    }
}
