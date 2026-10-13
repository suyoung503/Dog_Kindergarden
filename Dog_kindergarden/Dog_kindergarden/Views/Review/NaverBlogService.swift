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
    var loadPhase: AsyncLoadPhase = .idle
    private var activeStoreKey: String?

    var isLoading: Bool { loadPhase.isLoading }

    private struct Item: Decodable {
        let title: String
        let snippet: String
        let link: String
        let blogger: String
        let date: String
    }

    func load(storeKey: String) async {
        if activeStoreKey != storeKey { posts = [] }
        activeStoreKey = storeKey
        loadPhase = .loading

        var comps = URLComponents(
            url: APIEnvironment.apiBaseURL.appendingPathComponent("store-enrichment/blogs"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "storeKey", value: storeKey),
        ]
        guard let url = comps.url else {
            loadPhase = .failed("블로그 후기 주소를 만들지 못했어요.")
            return
        }

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
            await MainActor.run {
                guard self.activeStoreKey == storeKey else { return }
                self.posts = mapped
                self.loadPhase = .loaded
            }
        } catch {
            await MainActor.run {
                guard self.activeStoreKey == storeKey else { return }
                self.loadPhase = .failed("블로그 후기를 불러오지 못했어요. 네트워크 연결을 확인해주세요.")
            }
            #if DEBUG
            print("⚠️ 네이버 블로그 검색 실패: \(error)")
            #endif
        }
    }

    func clear() {
        posts = []
        loadPhase = .idle
        activeStoreKey = nil
    }
}
