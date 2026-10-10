import Foundation

struct KakaoPlace {
    let roadAddress: String
    let address: String
    let phone: String
    let placeURL: String

    var best: String { roadAddress.isEmpty ? address : roadAddress }
}

/// 외부 장소 API의 자격 증명을 앱에 넣지 않고 맡겨멍 Worker의 제한된 가게 보강 API만 호출한다.
enum StoreEnrichmentService {
    private struct PlaceResponse: Decodable {
        let roadAddress: String
        let address: String
        let phone: String
        let placeUrl: String
    }

    static func lookupPlace(storeKey: String) async -> KakaoPlace? {
        var components = URLComponents(
            url: APIEnvironment.apiBaseURL.appendingPathComponent("store-enrichment/place"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "storeKey", value: storeKey)]
        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await APITransport.data(for: APITransport.request(url: url))
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(PlaceResponse.self, from: data)
            return KakaoPlace(
                roadAddress: response.roadAddress,
                address: response.address,
                phone: response.phone,
                placeURL: response.placeUrl
            )
        } catch {
            #if DEBUG
            print("⚠️ 가게 장소 보강 실패: \(error)")
            #endif
            return nil
        }
    }
}
