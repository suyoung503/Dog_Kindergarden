import Foundation
import Observation

// MARK: - 데이터 스토어

// 지도 핀 소스 — 백엔드가 선별(is_curated)한 서울 유치원/호텔만 가져온다.
// (공공데이터 전수 페이지네이션 대신 우리가 이미 폐업 여부·주소를 검증해 둔 큐레이션 목록을 사용)
@Observable
final class BoardingStore {
    var pins: [MapPin] = []
    private(set) var isLoaded = false
    private var isLoading = false

    func loadIfNeeded() async {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let stores = try await APIClient.shared.fetchStores()
            let mapped: [MapPin] = stores.compactMap { store in
                guard let name = store.name, !name.isEmpty,
                      let key = store.storeKey, !key.isEmpty,
                      let lat = store.latitude, let lon = store.longitude else { return nil }
                return MapPin(
                    name: name,
                    type: store.storeType ?? "호텔",
                    rating: 0,
                    distance: "",
                    latitude: lat,
                    longitude: lon,
                    province: "서울",
                    address: store.address ?? "",
                    phone: store.phone ?? "",
                    status: store.status ?? "",
                    storeKeyOverride: key
                )
            }
            await MainActor.run {
                self.pins = mapped
                self.isLoaded = true
            }
        } catch {
            #if DEBUG
            print("⚠️ 큐레이션 가게 목록 로드 실패: \(error)")
            #endif
        }
    }

    func pins(forProvinceKey key: String) -> [MapPin] {
        pins.filter { $0.province == key }
    }
}
