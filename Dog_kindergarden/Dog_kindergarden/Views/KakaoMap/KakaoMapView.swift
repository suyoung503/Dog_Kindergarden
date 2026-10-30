import SwiftUI
import KakaoMapsSDK

// MARK: - Data

struct MapPin: Identifiable, Codable {
    let id = UUID()
    let name: String
    let type: String      // "호텔" | "유치원"
    let rating: Double
    let distance: String
    let latitude: Double
    let longitude: Double
    let province: String  // 소속 도(道)
    var address: String = ""
    var phone: String = ""
    var status: String = ""
    // 서버에 저장된 원본 키 — 찜 목록처럼 보강된 주소로 복원할 때 키가 달라지는 것 방지
    var storeKeyOverride: String? = nil
    var imageUrl: String? = nil

    // 최근 본 가게 영속(JSON)용 — id는 실행마다 새로 부여하므로 제외
    private enum CodingKeys: String, CodingKey {
        case name, type, rating, distance, latitude, longitude, province
        case address, phone, status, storeKeyOverride, imageUrl
    }

    // 리뷰 식별 키 (백엔드 store_key)
    var storeKey: String {
        if let key = storeKeyOverride, !key.isEmpty { return key }
        return address.isEmpty ? name : "\(name)|\(address)"
    }
}

// 현재 지도 화면에 보이는 위경도 범위 (viewport)
struct MapBounds {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    let centerLat: Double
    let centerLon: Double

    func contains(lat: Double, lon: Double) -> Bool {
        lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
    }
}

// 장소(유치원/호텔) 데이터는 data.go.kr 동물 위탁관리업 API에서 가져옵니다.
// → AnimalBoardingService.swift의 BoardingStore 참고

// 도(道)별 중심 좌표 — 클릭 시 해당 지역으로 지도 확대
struct ProvinceCenter {
    let latitude: Double
    let longitude: Double
}

let provinceCenters: [String: ProvinceCenter] = [
    "서울":     ProvinceCenter(latitude: 37.5665, longitude: 126.9780),
    "경기":   ProvinceCenter(latitude: 37.4138, longitude: 127.5183),
    "강원":   ProvinceCenter(latitude: 37.8228, longitude: 128.1555),
    "충북": ProvinceCenter(latitude: 36.6357, longitude: 127.4917),
    "충남": ProvinceCenter(latitude: 36.5184, longitude: 126.8000),
    "경북": ProvinceCenter(latitude: 36.4919, longitude: 128.8889),
    "경남": ProvinceCenter(latitude: 35.4606, longitude: 128.2132),
    "전북": ProvinceCenter(latitude: 35.7175, longitude: 127.1530),
    "전남": ProvinceCenter(latitude: 35.1595, longitude: 126.8526),  // 광주 중심
    "제주":   ProvinceCenter(latitude: 33.4890, longitude: 126.4983),
]

// 도 마커 "표시 위치" — 실제 중심과 분리해 겹침/치우침 보정
// (탭 시 줌 중심은 provinceCenters를 그대로 사용)
let provinceMarkerCenters: [String: ProvinceCenter] = [
    "서울": ProvinceCenter(latitude: 37.62, longitude: 126.92),  // 위로 분리
    "경기": ProvinceCenter(latitude: 37.30, longitude: 127.25),  // 서울 아래로 분리
    "강원": ProvinceCenter(latitude: 37.60, longitude: 128.30),  // 살짝 아래로
    "충북": ProvinceCenter(latitude: 36.90, longitude: 127.80),  // 북동으로
    "충남": ProvinceCenter(latitude: 36.55, longitude: 126.85),  // 오른쪽으로 살짝
    "경북": ProvinceCenter(latitude: 36.30, longitude: 128.90),
    "경남": ProvinceCenter(latitude: 35.30, longitude: 128.30),
    "전북": ProvinceCenter(latitude: 35.75, longitude: 127.20),
    "전남": ProvinceCenter(latitude: 35.00, longitude: 126.95),  // 광주 쪽으로 (우상향)
]

// 도별 마커 색상
let provinceUIColors: [String: UIColor] = [
    "서울":     UIColor(Color(hex: "#6B8EAD")),
    "경기":   UIColor(Color(hex: "#6B8EAD")),
    "강원":   UIColor(Color(hex: "#6FAE8E")),
    "충북": UIColor(Color(hex: "#E8A55C")),
    "충남": UIColor(Color(hex: "#E8A55C")),
    "경북": UIColor(Color(hex: "#D87E63")),
    "경남": UIColor(Color(hex: "#BC8A5F")),
    "전북": UIColor(Color(hex: "#5FB3BD")),
    "전남": UIColor(Color(hex: "#5FB3BD")),
    "제주":   UIColor(Color(hex: "#CC7FA6")),
]

// 도 단위가 보이는 줌 레벨 (값이 클수록 확대)
private let provinceZoomLevel = 9

// 우리나라 전체가 보이는 줌 레벨 (홈 카드용)
private let countryZoomLevel = 7
private let countryCenter = ProvinceCenter(latitude: 36.4, longitude: 127.8)

// MARK: - KakaoMapView (SwiftUI)

struct KakaoMapView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BoardingStore.self) private var boarding
    @State private var selectedPin: MapPin? = nil
    @State private var showBottomCard = false

    // 선택한 도(道)에 등록된 장소만 필터링 (data.go.kr API)
    private var pins: [MapPin] {
        boarding.pins(forProvinceKey: router.selectedProvince)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 지도 — 선택한 도(道)로 확대
            KakaoMapContainer(
                province: router.selectedProvince,
                pins: pins,
                onPinTapped: { pin in
                    selectedPin = pin
                    withAnimation(.spring(response: 0.35)) { showBottomCard = true }
                }
            )
            .ignoresSafeArea()

            // 상단 헤더 오버레이
            VStack {
                headerOverlay
                Spacer()
            }

            // 가게 선택 카드
            if showBottomCard, let pin = selectedPin {
                storeBottomCard(pin)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header

    private var headerOverlay: some View {
        HStack(spacing: 10) {
            Button(action: router.back) {
                Circle()
                    .fill(.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.brandBrown)
                    )
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.brandBrownLight)
                Text("\(router.selectedProvince) · 강아지 케어 \(pins.count)곳")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBrown)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        }
        .padding(.horizontal, 16)
        .safeAreaTopPadding()
    }

    // MARK: - Bottom card

    private func storeBottomCard(_ pin: MapPin) -> some View {
        VStack(spacing: 0) {
            // 드래그 핸들
            Capsule()
                .fill(Color.brandBeigeBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack(spacing: 14) {
                // 썸네일
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(pin.type == "호텔" ? Color(hex: "#FFE6CC") : Color.brandGreenLight)
                        .frame(width: 64, height: 64)
                    EmojiIcon(emoji: storeTypeEmoji(pin.type), size: 30)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(pin.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.brandBrown)
                        Text(pin.type)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.brandBrown)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(pin.type == "호텔" ? Color(hex: "#FFE6CC") : Color.brandGreenLight)
                            .clipShape(Capsule())
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.brandOrange)
                        Text(String(format: "%.1f", pin.rating))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.brandBrown)
                        Text("·")
                            .foregroundStyle(Color.brandBrownMid)
                        Text(pin.distance)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.brandBrownMid)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.brandBrownMid)
                        Text(router.selectedCity)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.brandBrownMid)
                    }
                }
                Spacer()

                Button(action: {
                    router.selectedStore = pin.name
                    router.selectedPin = pin
                    router.go(.storeDetail)
                }) {
                    Text("보기")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Color.brandOrange)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // 핀 목록 미니 리스트
            Divider()
                .foregroundStyle(Color.brandBeigeBorder)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pins) { p in
                        miniPinCard(p, isSelected: p.id == pin.id)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4)
        .padding(.horizontal, 0)
    }

    private func miniPinCard(_ pin: MapPin, isSelected: Bool) -> some View {
        Button(action: { selectedPin = pin }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    EmojiIcon(emoji: storeTypeEmoji(pin.type), size: 14)
                    Text(pin.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.brandBrown)
                        .lineLimit(1)
                }
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.brandOrange)
                    Text(String(format: "%.1f", pin.rating))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.brandBrown)
                    Text(pin.distance)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.brandBrownMid)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color(hex: "#FFF1DC") : Color.brandCream)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(isSelected ? Color.brandOrange : Color.brandBeigeBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
    }
}


// MARK: - KakaoMapContainer (UIViewControllerRepresentable)

struct KakaoMapContainer: UIViewControllerRepresentable {
    var province: String = ""
    var pins: [MapPin] = []
    var countryView: Bool = false        // true면 우리나라 전체를 보여줌 (홈 카드용)
    var centerLat: Double? = nil         // 지정 시 이 좌표로 시작 (도 중심 대신)
    var centerLon: Double? = nil
    var zoomLevel: Int? = nil            // 지정 시 이 줌으로 시작
    var restoredCamera: MapCameraState? = nil
    var onPinTapped: (MapPin) -> Void = { _ in }
    var onProvinceTapped: (String) -> Void = { _ in }   // 전국 보기에서 도 마커 탭
    var onCameraStopped: (MapBounds) -> Void = { _ in }  // 지도 이동/줌 멈춤 → 현재 보이는 범위
    var onCameraStateChanged: (MapCameraState) -> Void = { _ in }

    func makeUIViewController(context: Context) -> KakaoMapViewController {
        let vc = KakaoMapViewController()
        vc.province = province
        vc.pins = pins
        vc.countryView = countryView
        vc.centerLat = centerLat
        vc.centerLon = centerLon
        vc.zoomOverride = zoomLevel
        vc.restoredCamera = restoredCamera
        vc.onPinTapped = onPinTapped
        vc.onProvinceTapped = onProvinceTapped
        vc.onCameraStopped = onCameraStopped
        vc.onCameraStateChanged = onCameraStateChanged
        return vc
    }

    func updateUIViewController(_ uiViewController: KakaoMapViewController, context: Context) {
        // 클로저는 SwiftUI 재렌더마다 새로 생성되므로 최신 값으로 교체 (stale 캡처 방지)
        uiViewController.onPinTapped = onPinTapped
        uiViewController.onCameraStopped = onCameraStopped
        uiViewController.onCameraStateChanged = onCameraStateChanged

        let newIDs = Set(pins.map { $0.id })
        let oldIDs = Set(uiViewController.pins.map { $0.id })
        guard newIDs != oldIDs else { return }
        uiViewController.pins = pins
        uiViewController.refreshPins()
    }

    static func dismantleUIViewController(_ uiViewController: KakaoMapViewController, coordinator: ()) {
        uiViewController.tearDownMap()
    }
}

// MARK: - KakaoMapViewController

// 컨테이너와 엔진을 함께 주입해 수명주기 테스트에서 네이티브 렌더러를 생성하지 않는다.
protocol KakaoMapEngine: AnyObject {
    var delegate: MapControllerDelegate? { get set }
    @discardableResult func prepareEngine() -> Bool
    func activateEngine()
    func pauseEngine()
    func resetEngine()
    func getView(_ viewName: String) -> ViewBase?
    func addView(_ viewInfo: ViewInfo)
}

extension KMController: KakaoMapEngine {}

final class KakaoMapViewController: UIViewController, MapControllerDelegate, KakaoMapEventDelegate, UIGestureRecognizerDelegate {
    var province: String = "경기도"
    var pins: [MapPin] = []
    var countryView: Bool = false
    var centerLat: Double? = nil
    var centerLon: Double? = nil
    var zoomOverride: Int? = nil
    var restoredCamera: MapCameraState? = nil
    var onPinTapped: ((MapPin) -> Void)?
    var onProvinceTapped: ((String) -> Void)?
    var onCameraStopped: ((MapBounds) -> Void)?
    var onCameraStateChanged: ((MapCameraState) -> Void)?
    var makeMapResources: (CGRect) -> (UIView, any KakaoMapEngine) = { frame in
        let container = KMViewContainer(frame: frame)
        return (container, KMController(viewContainer: container))
    }

    private var mapController: (any KakaoMapEngine)?
    private var mapContainer: UIView?
    private weak var readyMap: KakaoMap?
    private var isDismantled = false
    private var isMapVisible = false
    private var callbackGeneration = 0
    private var initialViewportWork: DispatchWorkItem?
    private var poiIdToPin: [String: MapPin] = [:]
    private var storeLayer: LabelLayer? = nil  // 재사용할 레이어 참조
    // 지도 영역 위 드래그를 가로채서 바깥 ScrollView가 스크롤하지 않도록 하는 보조 제스처
    private lazy var blockPan: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handleBlockPan(_:)))
        g.delegate = self
        g.cancelsTouchesInView = false   // 터치를 지도 엔진에 그대로 전달
        g.delaysTouchesBegan = false
        g.delaysTouchesEnded = false
        return g
    }()

    @objc private func handleBlockPan(_ g: UIPanGestureRecognizer) {}

    // 지도(상세)와 동시 인식 허용 — 실제 패닝은 카카오맵 엔진이 처리
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: - 엔진 생성 (카카오 공식 라이프사이클)

    deinit {
        initialViewportWork?.cancel()
        mapController?.pauseEngine()
        mapController?.delegate = nil
        mapController?.resetEngine()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard !isDismantled else { return }

        let (container, controller) = makeMapResources(view.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(container)
        self.mapContainer = container

        controller.delegate = self          // delegate 먼저 연결
        self.mapController = controller
        controller.prepareEngine()          // 준비 완료 시 addViews() 콜백
    }

    // 뷰가 화면에 보인 뒤 엔진 활성화 — 이 시점엔 controller가 항상 존재
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isDismantled else { return }
        isMapVisible = true
        mapController?.activateEngine()
        if let readyMap, !countryView { scheduleInitialViewport(readyMap) }

        // 상세 지도: 카드 안에서 드래그하면 지도가 패닝되도록 바깥 스크롤을 양보시킴
        if !countryView {
            if blockPan.view == nil { view.addGestureRecognizer(blockPan) }
            if let scrollView = enclosingScrollView() {
                scrollView.panGestureRecognizer.require(toFail: blockPan)
            }
        }
    }

    // 상위 뷰 계층에서 SwiftUI ScrollView의 UIScrollView 찾기
    private func enclosingScrollView() -> UIScrollView? {
        var v: UIView? = view.superview
        while let cur = v {
            if let sv = cur as? UIScrollView { return sv }
            v = cur.superview
        }
        return nil
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isMapVisible = false
        invalidatePendingCallbacks()
        mapController?.pauseEngine()
    }

    // pause만으로는 SDK 객체가 해제되지 않는다. eventDelegate도 strong이므로
    // SwiftUI가 VC를 제거하는 시점에 순환참조를 끊고, reset 전에 SDK 참조를 비운다.
    func tearDownMap() {
        guard !isDismantled else { return }
        isDismantled = true
        isMapVisible = false
        invalidatePendingCallbacks()
        onPinTapped = nil
        onProvinceTapped = nil
        onCameraStopped = nil
        onCameraStateChanged = nil
        mapController?.pauseEngine()
        readyMap?.eventDelegate = nil
        mapController?.delegate = nil
        storeLayer = nil
        poiIdToPin.removeAll()
        readyMap = nil
        mapController?.resetEngine()
        mapController = nil
        mapContainer?.removeFromSuperview()
        mapContainer = nil
    }

    private func invalidatePendingCallbacks() {
        callbackGeneration += 1
        initialViewportWork?.cancel()
        initialViewportWork = nil
    }

    // MARK: - MapControllerDelegate

    // prepareEngine() 성공 후 SDK가 호출 — 여기서 뷰를 추가해야 안정적
    func addViews() {
        guard !isDismantled else { return }
        // 전국 보기면 우리나라 중심, 아니면 선택한 도 중심
        let pc: ProvinceCenter
        let level: Int
        if countryView {
            pc = countryCenter
            level = countryZoomLevel
        } else if let camera = restoredCamera {
            pc = ProvinceCenter(latitude: camera.latitude, longitude: camera.longitude)
            level = zoomOverride ?? provinceZoomLevel
        } else if let lat = centerLat, let lon = centerLon {
            // 특정 좌표(가게 등)로 시작
            pc = ProvinceCenter(latitude: lat, longitude: lon)
            level = zoomOverride ?? provinceZoomLevel
        } else {
            pc = provinceCenters[province] ?? ProvinceCenter(latitude: 37.4138, longitude: 127.5183)
            level = zoomOverride ?? provinceZoomLevel
        }
        let center = MapPoint(longitude: pc.longitude, latitude: pc.latitude)
        let info = MapviewInfo(
            viewName: "mapview",
            viewInfoName: "map",
            defaultPosition: center,
            defaultLevel: level
        )
        mapController?.addView(info)
    }

    // addView 성공 콜백 — 이 시점에 KakaoMap이 준비됨
    func addViewSucceeded(_ viewName: String, viewInfoName: String) {
        guard !isDismantled,
              let kakaoMap = mapController?.getView(viewName) as? KakaoMap else { return }
        readyMap = kakaoMap
        if let camera = restoredCamera, !countryView {
            let position = CameraPosition(
                target: MapPoint(longitude: camera.longitude, latitude: camera.latitude),
                height: camera.height, rotation: camera.rotation, tilt: camera.tilt
            )
            kakaoMap.moveCamera(CameraUpdate.make(cameraPosition: position))
        }
        kakaoMap.eventDelegate = self
        if countryView {
            // 카카오 기본 지명 라벨(대한민국/지역명) 숨기기
            kakaoMap.setPoiEnabled(false)
            // 모든 카메라 제스처 비활성화 — 이동·확대 없이 도 선택만 가능
            let gestures: [GestureType] = [.pan, .zoom, .rotate, .tilt, .doubleTapZoomIn,
                                           .twoFingerTapZoomOut, .longTapAndDrag, .rotateZoom, .oneFingerZoom]
            for g in gestures { kakaoMap.setGestureEnable(type: g, enable: false) }
            // 전국 보기: 도(道) 마커를 위경도에 직접 박음 (기기 무관하게 정위치)
            addProvincePOIs(to: kakaoMap)
        } else {
            // 상세 지도: 이동·확대·축소·회전 등 모든 제스처 허용
            let gestures: [GestureType] = [.pan, .zoom, .rotate, .tilt, .doubleTapZoomIn,
                                           .twoFingerTapZoomOut, .longTapAndDrag, .rotateZoom, .oneFingerZoom]
            for g in gestures { kakaoMap.setGestureEnable(type: g, enable: true) }
            addPOIStyle(to: kakaoMap)
            addPins(to: kakaoMap)
            // 지도 정착 후 최초 1회 현재 보이는 범위를 알려 초기 핀을 채움
            scheduleInitialViewport(kakaoMap)
        }
    }

    func viewWillDestroyed(_ view: ViewBase) {
        guard readyMap === view else { return }
        readyMap?.eventDelegate = nil
        readyMap = nil
        storeLayer = nil
        poiIdToPin.removeAll()
        invalidatePendingCallbacks()
    }

    private func scheduleInitialViewport(_ kakaoMap: KakaoMap) {
        initialViewportWork?.cancel()
        let generation = callbackGeneration
        let work = DispatchWorkItem { [weak self, weak kakaoMap] in
            guard let self, let kakaoMap,
                  !self.isDismantled, self.isMapVisible,
                  self.callbackGeneration == generation,
                  self.readyMap === kakaoMap else { return }
            self.reportViewport(kakaoMap)
        }
        initialViewportWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func addViewFailed(_ viewName: String, viewInfoName: String) {
        print("⚠️ KakaoMap addView 실패: \(viewName)")
    }

    // 인증 실패 — 조용한 실패 방지용 로그
    func authenticationFailed(_ errorCode: Int, desc: String) {
        print("⚠️ KakaoMap 인증 실패 [\(errorCode)]: \(desc)")
    }

    // MARK: - KakaoMapEventDelegate

    func poiDidTapped(kakaoMap: KakaoMap, layerID: String, poiID: String, position: MapPoint) {
        // SDK 콜백 안에서 화면을 파괴하지 않는다. 다음 main turn에서 여전히
        // 살아 있는 동일 지도인지 확인한 뒤에만 SDK 좌표를 읽고 화면을 전환한다.
        DispatchQueue.main.async { [weak self, weak kakaoMap] in
            guard let self, let kakaoMap,
                  !self.isDismantled, self.isMapVisible,
                  self.readyMap === kakaoMap else { return }
            if self.countryView {
                self.onProvinceTapped?(poiID)
                return
            }
            guard let pin = self.poiIdToPin[poiID] else { return }
            let camera = self.cameraState(kakaoMap)
            let bounds = self.computeBounds(kakaoMap)
            if let camera { self.onCameraStateChanged?(camera) }
            if let bounds { self.onCameraStopped?(bounds) }
            self.onPinTapped?(pin)
        }
    }

    // 지도 이동/줌이 멈추면 현재 보이는 범위를 상위로 전달 → viewport 기준 핀 갱신
    func cameraDidStopped(kakaoMap: KakaoMap, by: MoveBy) {
        DispatchQueue.main.async { [weak self, weak kakaoMap] in
            guard let self, let kakaoMap,
                  !self.isDismantled, self.isMapVisible,
                  self.readyMap === kakaoMap else { return }
            self.reportViewport(kakaoMap)
        }
    }

    private func reportViewport(_ kakaoMap: KakaoMap) {
        let camera = cameraState(kakaoMap)
        let bounds = computeBounds(kakaoMap)
        let generation = callbackGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDismantled, self.isMapVisible,
                  self.callbackGeneration == generation else { return }
            if let camera { self.onCameraStateChanged?(camera) }
            if let bounds { self.onCameraStopped?(bounds) }
        }
    }

    private func cameraState(_ kakaoMap: KakaoMap) -> MapCameraState? {
        guard let position = CameraUpdate.make(mapView: kakaoMap).cameraPosition else { return nil }
        let coordinate = position.targetPoint.wgsCoord
        return MapCameraState(
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            height: kakaoMap.cameraHeight,
            rotation: kakaoMap.rotationAngle, tilt: kakaoMap.tiltAngle
        )
    }

    // 화면 네 모서리를 위경도로 변환해 현재 보이는 범위 계산 (회전 대비 min/max)
    private func computeBounds(_ kakaoMap: KakaoMap) -> MapBounds? {
        guard let size = mapContainer?.bounds.size, size.width > 0, size.height > 0 else { return nil }
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height),
        ].map { kakaoMap.getPosition($0).wgsCoord }
        let lats = corners.map { $0.latitude }
        let lons = corners.map { $0.longitude }
        let center = kakaoMap.getPosition(CGPoint(x: size.width / 2, y: size.height / 2)).wgsCoord
        return MapBounds(
            minLat: lats.min() ?? 0, maxLat: lats.max() ?? 0,
            minLon: lons.min() ?? 0, maxLon: lons.max() ?? 0,
            centerLat: center.latitude, centerLon: center.longitude
        )
    }

    // MARK: - 도(道) 마커 (전국 보기)

    private func addProvincePOIs(to kakaoMap: KakaoMap) {
        let manager = kakaoMap.getLabelManager()
        let layerOption = LabelLayerOptions(
            layerID: "provinceLayer",
            competitionType: .none,
            competitionUnit: .poi,
            orderType: .rank,
            zOrder: 2000
        )
        guard let layer = manager.addLabelLayer(option: layerOption) else { return }

        // 마커는 표시 전용 좌표 사용 (겹침 보정)
        for (name, center) in provinceMarkerCenters {
            let color = provinceUIColors[name] ?? .systemGray
            let styleID = "prov_\(name)"
            let icon = PoiIconStyle(
                symbol: makeProvinceMarker(name: name, color: color),
                anchorPoint: CGPoint(x: 0.5, y: 0.5)
            )
            manager.addPoiStyle(PoiStyle(styleID: styleID, styles: [
                PerLevelPoiStyle(iconStyle: icon, level: 0)
            ]))

            let opt = PoiOptions(styleID: styleID, poiID: name)
            opt.rank = 1
            opt.clickable = true
            let pos = MapPoint(longitude: center.longitude, latitude: center.latitude)
            layer.addPoi(option: opt, at: pos)?.show()
        }
    }

    // 도 이름 캡슐 마커 이미지 — 지도 크기에 맞춰 작게
    private func makeProvinceMarker(name: String, color: UIColor) -> UIImage {
        let font = UIFont.systemFont(ofSize: 9, weight: .bold)
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = (name as NSString).size(withAttributes: attr)
        let padH: CGFloat = 6, padV: CGFloat = 3.5
        let size = CGSize(width: ceil(textSize.width) + padH * 2,
                          height: ceil(textSize.height) + padV * 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)
            color.setFill()
            path.fill()
            (name as NSString).draw(at: CGPoint(x: padH, y: padV), withAttributes: attr)
        }
    }

    // MARK: - 핀 갱신 (updateUIViewController에서 호출)

    func refreshPins() {
        guard !isDismantled, let kakaoMap = readyMap else {
            // 지도 아직 준비 안 됨 — addViewSucceeded에서 self.pins로 그릴 것
            return
        }
        poiIdToPin.removeAll()
        storeLayer?.clearAllItems()   // 레이어 재사용 시 기존 핀 누적 방지
        addPins(to: kakaoMap)
    }

    // MARK: - POI 스타일 등록

    private func addPOIStyle(to kakaoMap: KakaoMap) {
        let manager = kakaoMap.getLabelManager()

        let hotelIcon = PoiIconStyle(
            symbol: makeMarkerImage(emoji: "🏨", color: UIColor(Color.brandOrange)),
            anchorPoint: CGPoint(x: 0.5, y: 1.0)
        )
        let hotelStyle = PoiStyle(styleID: "hotel", styles: [
            PerLevelPoiStyle(iconStyle: hotelIcon, level: 0)
        ])

        let kgIcon = PoiIconStyle(
            symbol: makeMarkerImage(emoji: "🏠", color: UIColor(Color.brandGreen)),
            anchorPoint: CGPoint(x: 0.5, y: 1.0)
        )
        let kgStyle = PoiStyle(styleID: "kindergarten", styles: [
            PerLevelPoiStyle(iconStyle: kgIcon, level: 0)
        ])

        manager.addPoiStyle(hotelStyle)
        manager.addPoiStyle(kgStyle)
    }

    // MARK: - 핀 추가

    private func addPins(to kakaoMap: KakaoMap) {
        let manager = kakaoMap.getLabelManager()

        // 이미 레이어가 있으면 재사용, 없으면 새로 생성
        let layer: LabelLayer
        if let existing = storeLayer {
            layer = existing
        } else {
            let layerOption = LabelLayerOptions(
                layerID: "storeLayer",
                competitionType: .none,
                competitionUnit: .poi,
                orderType: .rank,
                zOrder: 1000
            )
            guard let newLayer = manager.addLabelLayer(option: layerOption) else { return }
            storeLayer = newLayer
            layer = newLayer
        }

        for pin in pins {
            let styleID = pin.type == "호텔" ? "hotel" : "kindergarten"
            let poiOption = PoiOptions(styleID: styleID, poiID: pin.id.uuidString)
            poiOption.rank = 1
            poiOption.clickable = true        // 탭 이벤트(poiDidTapped) 활성화
            poiOption.addText(PoiText(text: pin.name, styleIndex: 0))

            let position = MapPoint(longitude: pin.longitude, latitude: pin.latitude)
            if let poi = layer.addPoi(option: poiOption, at: position) {
                poi.show()
                poiIdToPin[pin.id.uuidString] = pin
            }
        }
    }

    // MARK: - 마커 이미지 생성

    private func makeMarkerImage(emoji: String, color: UIColor) -> UIImage {
        let size = CGSize(width: 52, height: 60)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let bubbleRect = CGRect(x: 2, y: 2, width: 48, height: 48)
            color.setFill()
            UIBezierPath(ovalIn: bubbleRect).fill()

            UIColor.white.setStroke()
            let strokePath = UIBezierPath(ovalIn: bubbleRect.insetBy(dx: 0.5, dy: 0.5))
            strokePath.lineWidth = 3
            strokePath.stroke()

            let tail = UIBezierPath()
            tail.move(to: CGPoint(x: 20, y: 46))
            tail.addLine(to: CGPoint(x: 26, y: 58))
            tail.addLine(to: CGPoint(x: 32, y: 46))
            tail.close()
            color.setFill()
            tail.fill()

            // PNG가 있는 이모지는 이미지로, 없으면 이모지 텍스트로
            if let assetName = emoji.petAssetName, let img = UIImage(named: assetName) {
                let s: CGFloat = 30
                img.draw(in: CGRect(x: (size.width - s) / 2, y: (48 - s) / 2, width: s, height: s))
            } else {
                let attr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24)]
                let str = NSAttributedString(string: emoji, attributes: attr)
                let textSize = str.size()
                str.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                                     y: (48 - textSize.height) / 2))
            }
        }
    }
}
