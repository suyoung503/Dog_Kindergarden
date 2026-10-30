import Testing
@testable import Dog_kindergarden

@Suite("Home map navigation restoration")
@MainActor
struct HomeMapRestorationTests {
    @Test("Store detail round trip preserves the full browsing state")
    func storeDetailRoundTrip() {
        let router = AppRouter()
        router.go(.home)
        router.homeMapState.searchText = "코코"
        router.homeMapState.activeType = "유치원"
        router.homeMapState.activeFilters = [.cctv, .pickup]
        router.homeMapState.bounds = MapBounds(
            minLat: 37.4, maxLat: 37.6, minLon: 126.8, maxLon: 127.1,
            centerLat: 37.5, centerLon: 126.95
        )
        let camera = MapCameraState(
            latitude: 37.5, longitude: 126.95, height: 1234.567,
            rotation: 0.4, tilt: 0.2
        )
        router.homeMapState.camera = camera

        router.go(.storeDetail)
        router.back()

        #expect(router.current == .home)
        #expect(router.homeMapState.searchText == "코코")
        #expect(router.homeMapState.activeType == "유치원")
        #expect(router.homeMapState.activeFilters == [.cctv, .pickup])
        #expect(router.homeMapState.bounds?.centerLat == 37.5)
        #expect(router.homeMapState.bounds?.maxLon == 127.1)
        #expect(router.homeMapState.camera == camera)
    }

    @Test("Session reset clears previous account's browsing state")
    func sessionReset() {
        let router = AppRouter()
        router.homeMapState.searchText = "코코"
        router.homeMapState.activeType = "호텔"
        router.homeMapState.activeFilters = [.largeDog]
        router.homeMapState.bounds = MapBounds(
            minLat: 37.4, maxLat: 37.6, minLon: 126.8, maxLon: 127.1,
            centerLat: 37.5, centerLon: 126.95
        )
        router.homeMapState.camera = MapCameraState(
            latitude: 37.5, longitude: 126.95, height: 1234.567,
            rotation: 0.4, tilt: 0.2
        )

        router.reset(to: .start)

        #expect(router.homeMapState.searchText.isEmpty)
        #expect(router.homeMapState.activeType == nil)
        #expect(router.homeMapState.activeFilters.isEmpty)
        #expect(router.homeMapState.bounds == nil)
        #expect(router.homeMapState.camera == nil)
    }
}
