import Foundation
import Testing
#if canImport(SwiftUI)
import SwiftUI
#endif
@testable import Dog_kindergarden

@Suite("Store detail in-app location map")
@MainActor
struct StoreLocationMapTests {
    @Test("Map action presents the selected WGS84 pin instead of raw detail coordinates")
    func selectedPinIsPreferred() throws {
        var presentation = StoreLocationMapPresentation()
        let selected = pin(latitude: 37.5, longitude: 127.04)
        let detail = try detail(latitude: 451_234, longitude: 203_456)

        presentation.present(pin: selected, detail: detail, name: "코코", storeKey: "coco", address: "서울 강남구")

        let context = try #require(presentation.context)
        #expect(context.pin.id == selected.id)
        #expect(context.pin.latitude == 37.5)
        #expect(context.pin.longitude == 127.04)
        #expect(context.pin.address == "서울 강남구")
        presentation.dismiss()
        #expect(presentation.context == nil)
    }

    @Test("A valid detail coordinate can supply the one store pin when no selected pin exists")
    func detailFallback() throws {
        var presentation = StoreLocationMapPresentation()
        presentation.present(pin: nil, detail: try detail(latitude: 37.51, longitude: 127.05),
                             name: "코코", storeKey: "coco", address: "서울 강남구")
        let context = try #require(presentation.context)
        #expect(context.pin.latitude == 37.51)
        #expect(context.pin.longitude == 127.05)
        #expect(context.pin.name == "코코")
        #expect(context.pin.storeKey == "coco")
    }

    @Test("Missing, zero, nonfinite, out-of-range and raw TM coordinates never present a map")
    func invalidCoordinates() throws {
        var presentation = StoreLocationMapPresentation()
        for (latitude, longitude) in [(0.0, 0.0), (37.5, 0), (0, 127.0), (.nan, 127),
                                      (37.5, .infinity), (91, 127), (37.5, 181), (451_234, 203_456)] {
            presentation.present(pin: pin(latitude: latitude, longitude: longitude), detail: nil,
                                 name: "코코", storeKey: "coco", address: "서울 강남구")
            #expect(presentation.context == nil)
        }
        presentation.present(pin: nil, detail: try detail(latitude: 451_234, longitude: 203_456),
                             name: "코코", storeKey: "coco", address: "서울 강남구")
        #expect(presentation.context == nil)
        presentation.present(pin: nil, detail: nil, name: "코코", storeKey: "coco", address: "서울 강남구")
        #expect(presentation.context == nil)
    }

    #if canImport(KakaoMapsSDK)
    @Test("The local map has one centered store pin and its callbacks cannot replace the home camera")
    func isolatedMapConfiguration() throws {
        let router = AppRouter()
        router.go(.home)
        router.go(.storeDetail)
        let camera = MapCameraState(latitude: 37.2, longitude: 126.8, height: 4321, rotation: 0.4, tilt: 0.2)
        router.homeMapState.camera = camera
        var presentation = StoreLocationMapPresentation()
        let selected = pin(latitude: 37.5, longitude: 127.04)
        presentation.present(pin: selected, detail: nil, name: "코코", storeKey: "coco", address: "서울 강남구")
        let context = try #require(presentation.context)
        let view = StoreLocationMapView(context: context, onClose: { presentation.dismiss() })
        let map = view.map
        #expect(map.pins.count == 1)
        #expect(map.pins.first?.id == selected.id)
        #expect(map.centerLat == 37.5)
        #expect(map.centerLon == 127.04)
        #expect(map.zoomLevel == 16)
        #expect(map.restoredCamera == nil)

        map.onPinTapped(selected)
        map.onCameraStateChanged(MapCameraState(latitude: 35, longitude: 129, height: 500, rotation: 0, tilt: 0))
        view.onClose()

        #expect(presentation.context == nil)
        #expect(router.current == .storeDetail)
        #expect(router.homeMapState.camera == camera)
    }
    #endif

    private func pin(latitude: Double, longitude: Double) -> MapPin {
        MapPin(name: "코코", type: "유치원", rating: 0, distance: "", latitude: latitude,
               longitude: longitude, province: "서울", address: "기본 주소", storeKeyOverride: "coco")
    }

    private func detail(latitude: Double, longitude: Double) throws -> StoreDetailResponse {
        let data = try JSONSerialization.data(withJSONObject: ["latitude": latitude, "longitude": longitude])
        return try JSONDecoder().decode(StoreDetailResponse.self, from: data)
    }
}
