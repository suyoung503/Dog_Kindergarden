import Foundation
import Observation

// MARK: - data.go.kr 동물 위탁관리업 API 응답 모델

private struct BoardingResponse: Decodable {
    let response: Body
    struct Body: Decodable { let body: Inner }
    struct Inner: Decodable { let items: Items }
    struct Items: Decodable { let item: [Item] }
    struct Item: Decodable {
        let BPLC_NM: String?          // 상호명
        let CRD_INFO_X: String?       // TM X
        let CRD_INFO_Y: String?       // TM Y
        let ROAD_NM_ADDR: String?     // 도로명 주소
        let LOTNO_ADDR: String?       // 지번 주소
        let TELNO: String?            // 전화
        let SALS_STTS_NM: String?     // 영업상태
    }
}

// MARK: - 좌표 변환 (EPSG:5181 중부원점 TM → WGS84)

enum TMConverter {
    // GRS80
    private static let a = 6378137.0
    private static let f = 1.0 / 298.257222101
    private static let lat0 = 38.0 * .pi / 180.0   // 원점 위도
    private static let lon0 = 127.0 * .pi / 180.0  // 원점 경도
    private static let k0 = 1.0
    private static let FE = 200000.0               // false easting
    private static let FN = 500000.0               // false northing (5181)

    static func toWGS84(x: Double, y: Double) -> (lat: Double, lon: Double) {
        let e2 = f * (2 - f)
        let ep2 = e2 / (1 - e2)

        func meridionalArc(_ lat: Double) -> Double {
            a * ((1 - e2/4 - 3*e2*e2/64 - 5*e2*e2*e2/256) * lat
                - (3*e2/8 + 3*e2*e2/32 + 45*e2*e2*e2/1024) * sin(2*lat)
                + (15*e2*e2/256 + 45*e2*e2*e2/1024) * sin(4*lat)
                - (35*e2*e2*e2/3072) * sin(6*lat))
        }

        let M0 = meridionalArc(lat0)
        let M = M0 + (y - FN) / k0
        let mu = M / (a * (1 - e2/4 - 3*e2*e2/64 - 5*e2*e2*e2/256))
        let e1 = (1 - sqrt(1 - e2)) / (1 + sqrt(1 - e2))

        let phi1 = mu
            + (3*e1/2 - 27*pow(e1,3)/32) * sin(2*mu)
            + (21*e1*e1/16 - 55*pow(e1,4)/32) * sin(4*mu)
            + (151*pow(e1,3)/96) * sin(6*mu)
            + (1097*pow(e1,4)/512) * sin(8*mu)

        let sinPhi1 = sin(phi1), cosPhi1 = cos(phi1), tanPhi1 = tan(phi1)
        let C1 = ep2 * cosPhi1 * cosPhi1
        let T1 = tanPhi1 * tanPhi1
        let N1 = a / sqrt(1 - e2 * sinPhi1 * sinPhi1)
        let R1 = a * (1 - e2) / pow(1 - e2 * sinPhi1 * sinPhi1, 1.5)
        let D = (x - FE) / (N1 * k0)

        let lat = phi1 - (N1 * tanPhi1 / R1) *
            (D*D/2 - (5 + 3*T1 + 10*C1 - 4*C1*C1 - 9*ep2) * pow(D,4)/24
             + (61 + 90*T1 + 298*C1 + 45*T1*T1 - 252*ep2 - 3*C1*C1) * pow(D,6)/720)
        let lon = lon0 + (D - (1 + 2*T1 + C1) * pow(D,3)/6
             + (5 - 2*C1 + 28*T1 - 3*C1*C1 + 8*ep2 + 24*T1*T1) * pow(D,5)/120) / cosPhi1

        return (lat * 180 / .pi, lon * 180 / .pi)
    }
}

// MARK: - 주소 → 도(道) 축약키 매칭 (광역시는 인접 도로 편입)

private func provinceKey(from address: String) -> String? {
    let table: [(prefix: String, key: String)] = [
        ("서울", "서울"),
        ("경기", "경기"), ("인천", "경기"),
        ("강원", "강원"),
        ("충청북도", "충북"), ("충북", "충북"),
        ("충청남도", "충남"), ("충남", "충남"), ("대전", "충남"), ("세종", "충남"),
        ("경상북도", "경북"), ("경북", "경북"), ("대구", "경북"),
        ("경상남도", "경남"), ("경남", "경남"), ("부산", "경남"), ("울산", "경남"),
        ("전라북도", "전북"), ("전북", "전북"),
        ("전라남도", "전남"), ("전남", "전남"), ("광주", "전남"),
    ]
    for t in table where address.hasPrefix(t.prefix) { return t.key }
    return nil
}

// 상호명으로 호텔/유치원 추정
private func boardingType(from name: String) -> String {
    if name.contains("호텔") { return "호텔" }
    if name.contains("유치원") || name.contains("스쿨") || name.contains("학교") || name.contains("케어") { return "유치원" }
    return "호텔"
}

// MARK: - 데이터 스토어

@Observable
final class BoardingStore {
    var pins: [MapPin] = []
    private(set) var isLoaded = false
    private var isLoading = false

    // Info.plist의 DATA_GO_KR_SERVICE_KEY에서 주입 (소스에 키 하드코딩 금지)
    private let serviceKey = Bundle.main.object(forInfoDictionaryKey: "DATA_GO_KR_SERVICE_KEY") as? String ?? ""

    func loadIfNeeded() async {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var comps = URLComponents(string: "https://apis.data.go.kr/1741000/animal_boarding/info")!
        comps.queryItems = [
            URLQueryItem(name: "serviceKey", value: serviceKey),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "numOfRows", value: "1000"),
            URLQueryItem(name: "type", value: "json"),
        ]
        guard let url = comps.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(BoardingResponse.self, from: data)
            let mapped: [MapPin] = decoded.response.body.items.item.compactMap { item in
                guard let name = item.BPLC_NM, !name.isEmpty,
                      let xs = item.CRD_INFO_X, let x = Double(xs),
                      let ys = item.CRD_INFO_Y, let y = Double(ys),
                      x > 0, y > 0 else { return nil }
                let addr = item.ROAD_NM_ADDR?.isEmpty == false ? item.ROAD_NM_ADDR! : (item.LOTNO_ADDR ?? "")
                guard let key = provinceKey(from: addr) else { return nil }
                let coord = TMConverter.toWGS84(x: x, y: y)
                // 대한민국 영역 밖 좌표 제외
                guard coord.lat > 33, coord.lat < 39, coord.lon > 124, coord.lon < 132 else { return nil }
                return MapPin(
                    name: name,
                    type: boardingType(from: name),
                    rating: 0,
                    distance: "",
                    latitude: coord.lat,
                    longitude: coord.lon,
                    province: key,
                    address: addr,
                    phone: item.TELNO ?? "",
                    status: item.SALS_STTS_NM ?? ""
                )
            }
            await MainActor.run {
                self.pins = mapped
                self.isLoaded = true
            }
        } catch {
            #if DEBUG
            print("⚠️ 동물위탁업 API 로드 실패: \(error)")
            #endif
        }
    }

    func pins(forProvinceKey key: String) -> [MapPin] {
        pins.filter { $0.province == key }
    }
}
