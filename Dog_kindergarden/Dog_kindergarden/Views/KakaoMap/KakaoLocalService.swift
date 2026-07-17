import Foundation

// 카카오 로컬 키워드 검색 — 공공데이터의 마스킹된 주소(***)를 전체 주소로 보강
// REST 키는 Info.plist의 KAKAO_REST_API_KEY (네이티브 키와 별개)

struct KakaoPlace {
    let roadAddress: String   // 도로명 주소 (전체)
    let address: String       // 지번 주소 (전체)
    let phone: String
    let placeURL: String      // 카카오플레이스 링크

    var best: String { roadAddress.isEmpty ? address : roadAddress }
}

enum KakaoLocalService {
    private static var restKey: String {
        Bundle.main.object(forInfoDictionaryKey: "KAKAO_REST_API_KEY") as? String ?? ""
    }

    private struct Response: Decodable {
        let documents: [Doc]
        struct Doc: Decodable {
            let place_name: String
            let address_name: String?
            let road_address_name: String?
            let phone: String?
            let place_url: String?
        }
    }

    /// 가게 이름 + 좌표 주변에서 가장 가까운 장소를 찾아 전체 주소 반환
    /// 카카오맵에 미등록이면 nil — 호출부에서 네이버 지역 검색 → coordAddress 순으로 폴백
    /// (반경을 늘려 이름만 비슷한 다른 가게가 잡히는 것보다 안전)
    static func lookup(name: String, lat: Double, lon: Double) async -> KakaoPlace? {
        let key = restKey
        guard !key.isEmpty, key != "[REST_API_KEY]" else { return nil }

        var comps = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "x", value: String(lon)),
            URLQueryItem(name: "y", value: String(lat)),
            URLQueryItem(name: "radius", value: "1000"),   // 1km 내
            URLQueryItem(name: "sort", value: "distance"),
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("KakaoAK \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let doc = decoded.documents.first else { return nil }
            return KakaoPlace(
                roadAddress: doc.road_address_name ?? "",
                address: doc.address_name ?? "",
                phone: doc.phone ?? "",
                placeURL: doc.place_url ?? ""
            )
        } catch {
            #if DEBUG
            print("⚠️ 카카오 로컬 검색 실패: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - 좌표→주소 변환 폴백

    private struct CoordResponse: Decodable {
        let documents: [Doc]
        struct Doc: Decodable {
            let road_address: Addr?
            let address: Addr?
            struct Addr: Decodable { let address_name: String? }
        }
    }

    /// 핀 좌표(공공데이터 소재지)의 실제 전체 주소 — 전화·링크는 없음 (최후 폴백)
    static func coordAddress(lat: Double, lon: Double) async -> KakaoPlace? {
        let key = restKey
        guard !key.isEmpty, key != "[REST_API_KEY]" else { return nil }

        var comps = URLComponents(string: "https://dapi.kakao.com/v2/local/geo/coord2address.json")!
        comps.queryItems = [
            URLQueryItem(name: "x", value: String(lon)),
            URLQueryItem(name: "y", value: String(lat)),
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("KakaoAK \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(CoordResponse.self, from: data)
            guard let doc = decoded.documents.first else { return nil }
            return KakaoPlace(
                roadAddress: doc.road_address?.address_name ?? "",
                address: doc.address?.address_name ?? "",
                phone: "",
                placeURL: ""
            )
        } catch {
            #if DEBUG
            print("⚠️ 카카오 좌표→주소 변환 실패: \(error)")
            #endif
            return nil
        }
    }
}
