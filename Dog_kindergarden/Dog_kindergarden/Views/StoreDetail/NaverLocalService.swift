import Foundation

// 네이버 지역 검색 — 카카오맵에 없는 가게의 실제 주소를 네이버 플레이스에서 보강
// NCP NAVER API HUB 경유 (구 개발자센터 검색 API는 신규 등록 중단 → API HUB로 이관)
// 키: Info.plist의 NAVER_CLIENT_ID / NAVER_CLIENT_SECRET (블로그 검색과 같은 Application)

struct NaverPlace {
    let roadAddress: String   // 도로명 주소
    let address: String       // 지번 주소

    var best: String { roadAddress.isEmpty ? address : roadAddress }
}

enum NaverLocalService {
    private static var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "NAVER_CLIENT_ID") as? String ?? ""
    }
    private static var clientSecret: String {
        Bundle.main.object(forInfoDictionaryKey: "NAVER_CLIENT_SECRET") as? String ?? ""
    }

    private struct Response: Decodable {
        let items: [Item]
        struct Item: Decodable {
            let title: String
            let roadAddress: String?
            let address: String?
            let mapx: String?   // WGS84 경도 × 1e7
            let mapy: String?   // WGS84 위도 × 1e7
        }
    }

    /// "지역 가게이름"으로 검색해 핀 좌표 최근접 결과의 주소 반환, 없으면 이름만으로 재시도
    /// 좌표 검증으로 같은 이름의 다른 지역 가게를 배제한다
    static func lookup(name: String, region: String, lat: Double, lon: Double) async -> NaverPlace? {
        let id = clientID, secret = clientSecret
        guard !id.isEmpty, id != "[NAVER_CLIENT_ID]",
              !secret.isEmpty, secret != "[NAVER_CLIENT_SECRET]" else { return nil }

        let query = region.isEmpty ? name : "\(region) \(name)"
        if let place = await search(query: query, lat: lat, lon: lon, id: id, secret: secret) {
            return place
        }
        guard !region.isEmpty else { return nil }
        return await search(query: name, lat: lat, lon: lon, id: id, secret: secret)
    }

    private static func search(query: String, lat: Double, lon: Double, id: String, secret: String) async -> NaverPlace? {
        var comps = URLComponents(string: "https://naverapihub.apigw.ntruss.com/search/v1/local")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "display", value: "5"),
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue(id, forHTTPHeaderField: "X-NCP-APIGW-API-KEY-ID")
        req.setValue(secret, forHTTPHeaderField: "X-NCP-APIGW-API-KEY")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            // 핀 좌표에서 가장 가까운 결과 선택 — 3km 밖이면 다른 가게로 보고 버림
            let candidates: [(item: Response.Item, dist: Double)] = decoded.items.compactMap { item in
                guard let x = Double(item.mapx ?? ""), let y = Double(item.mapy ?? "") else { return nil }
                let dLat = (y / 1e7 - lat) * 111_000          // 위도 1도 ≈ 111km
                let dLon = (x / 1e7 - lon) * 88_800           // 경도 1도 ≈ 88.8km (위도 37° 기준)
                return (item, (dLat * dLat + dLon * dLon).squareRoot())
            }
            guard let nearest = candidates.min(by: { $0.dist < $1.dist }), nearest.dist <= 3_000 else {
                return nil
            }
            return NaverPlace(
                roadAddress: nearest.item.roadAddress ?? "",
                address: nearest.item.address ?? ""
            )
        } catch {
            #if DEBUG
            print("⚠️ 네이버 지역 검색 실패: \(error)")
            #endif
            return nil
        }
    }
}
