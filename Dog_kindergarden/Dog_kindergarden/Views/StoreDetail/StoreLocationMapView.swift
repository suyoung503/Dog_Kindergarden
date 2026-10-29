import SwiftUI

struct StoreLocationMapContext: Identifiable {
    let pin: MapPin
    var id: UUID { pin.id }
}

// 상세 화면에만 속하는 표시 상태. 홈 지도 카메라나 라우터를 변경하지 않는다.
struct StoreLocationMapPresentation {
    var context: StoreLocationMapContext?

    mutating func present(pin: MapPin?, detail: StoreDetailResponse?, name: String, storeKey: String, address: String) {
        var locationPin: MapPin
        if let pin, Self.isValid(latitude: pin.latitude, longitude: pin.longitude) {
            locationPin = pin
        } else if let latitude = detail?.latitude, let longitude = detail?.longitude,
                  Self.isValid(latitude: latitude, longitude: longitude) {
            // 원본 TM 좌표를 위경도로 추정하지 않고, 유효한 WGS84만 사용한다.
            locationPin = MapPin(
                name: name, type: detail?.storeType ?? "", rating: 0, distance: "",
                latitude: latitude, longitude: longitude, province: "",
                address: detail?.address ?? "", storeKeyOverride: storeKey
            )
        } else {
            context = nil
            return
        }
        if !address.isEmpty { locationPin.address = address }
        context = StoreLocationMapContext(pin: locationPin)
    }

    mutating func dismiss() {
        context = nil
    }

    private static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && latitude != 0 && longitude != 0
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct StoreLocationMapView: View {
    let context: StoreLocationMapContext
    let onClose: () -> Void

    var map: KakaoMapContainer {
        KakaoMapContainer(
            pins: [context.pin],
            centerLat: context.pin.latitude,
            centerLon: context.pin.longitude,
            zoomLevel: 16
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("가게 위치")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.brandBrown)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brandBrown)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("지도 닫기")
            }
            .padding(.leading, 20)
            .padding(.trailing, 8)
            .padding(.top, 12)

            map
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.pin.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.brandBrown)
                        Label(context.pin.address.isEmpty ? "주소 정보가 없어요" : context.pin.address, systemImage: "mappin")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.brandBrownMid)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brandBeigeBorder, lineWidth: 1))
                    .padding(16)
                }
        }
        .background(Color.brandCream)
    }
}
