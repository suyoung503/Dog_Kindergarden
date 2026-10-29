import SwiftUI
import UIKit

// JPEG keeps a square of pixels; circular profile views display exactly the selected circle.
enum PetPhotoCropRenderer {
    static func jpeg(image: UIImage, sourceRect: CGRect) throws -> Data {
        let bounds = CGRect(origin: .zero, size: image.size)
        guard [sourceRect.minX, sourceRect.minY, sourceRect.width, sourceRect.height].allSatisfy(\.isFinite),
              sourceRect.width > 0, sourceRect.width == sourceRect.height, bounds.contains(sourceRect) else {
            throw PetPhotoNormalizationError.invalidImage
        }
        let side = max(1, min(1000, floor(sourceRect.width)))
        let ratio = side / sourceRect.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let cropped = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(x: -sourceRect.minX * ratio, y: -sourceRect.minY * ratio, width: image.size.width * ratio, height: image.size.height * ratio))
        }
        guard let bytes = cropped.jpegData(compressionQuality: 0.85) else { throw PetPhotoNormalizationError.encodingFailed }
        return try PetPhotoNormalizer.normalize(bytes)
    }
}

struct PetPhotoCropPreview: View {
    let image: UIImage
    let crop: PetPhotoCropGeometry

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: crop.imageFrame.width, height: crop.imageFrame.height)
            .position(x: crop.imageFrame.midX, y: crop.imageFrame.midY)
    }
}

struct PetPhotoCropView: View {
    let source: PetPhotoCropSource
    let onCancel: () -> Void
    let onApply: (Data) -> Void
    private let image: UIImage?
    @State private var canvasSize = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var photoOffset = CGSize.zero
    @State private var circleOffset = CGSize.zero
    @State private var diameterFraction: CGFloat = 0.75
    @State private var moveCircle = false
    @State private var errorMessage: String?
    @State private var gestureChange = PetPhotoCropGesture()

    init(source: PetPhotoCropSource, onCancel: @escaping () -> Void, onApply: @escaping (Data) -> Void) {
        self.source = source
        self.onCancel = onCancel
        self.onApply = onApply
        image = UIImage(data: source.data)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("원 안에 강아지를 맞춰주세요")
                    .font(.headline)
                canvas
                controls
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(20)
            .background(Color.brandCream.ignoresSafeArea())
            .navigationTitle("사진 조정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: apply) {
                        Image(systemName: "checkmark").fontWeight(.bold)
                    }
                    .accessibilityLabel("조정한 사진 적용")
                    .disabled(geometry(for: canvasSize) == nil)
                }
            }
            .tint(Color.brandBrown)
        }
        .interactiveDismissDisabled()
    }

    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let image, let crop = geometry(for: proxy.size, change: gestureChange) {
                    PetPhotoCropPreview(image: image, crop: crop)
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: proxy.size))
                        path.addEllipse(in: crop.cropRect)
                    }
                    .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                    Circle()
                        .stroke(.white, lineWidth: 2)
                        .frame(width: crop.cropRect.width, height: crop.cropRect.height)
                        .position(x: crop.cropRect.midX, y: crop.cropRect.midY)
                } else {
                    Text("사진을 표시할 수 없어요. 다시 선택해주세요.").foregroundStyle(.white)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture().simultaneously(with: MagnificationGesture())
                    .onChanged { value in
                        gestureChange.update(translation: value.first?.translation, magnification: value.second)
                    }
                    .onEnded { value in
                        gestureChange.update(translation: value.first?.translation, magnification: value.second)
                        if let crop = geometry(for: proxy.size, change: gestureChange) {
                            commit(crop)
                        }
                        gestureChange = PetPhotoCropGesture()
                    }
            )
            .onAppear { canvasSize = proxy.size; normalizeLayout() }
            .onChange(of: proxy.size) { _, size in canvasSize = size; normalizeLayout() }
            .accessibilityLabel("강아지 사진 원형 미리보기")
        }
        .frame(maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("이동 대상", selection: $moveCircle) {
                Text("사진 이동").tag(false)
                Text("원 이동").tag(true)
            }
            .pickerStyle(.segmented)
            Text(moveCircle ? "드래그해 원의 위치를 조정하세요" : "드래그해 사진 이동 · 두 손가락으로 확대")
                .font(.footnote).foregroundStyle(Color.brandBrownMid)
            HStack {
                Text("원 크기").font(.subheadline).frame(width: 70, alignment: .leading)
                Slider(value: $diameterFraction, in: 0.35...0.9)
                    .accessibilityLabel("원 크기")
            }
            HStack {
                Text("사진 확대").font(.subheadline).frame(width: 70, alignment: .leading)
                Slider(value: $zoom, in: 1...6)
                    .accessibilityLabel("사진 확대")
            }
        }
        .tint(Color.brandOrange)
        .onChange(of: diameterFraction) { _, _ in normalizeLayout() }
        .onChange(of: zoom) { _, _ in normalizeLayout() }
    }

    private func geometry(for size: CGSize, change: PetPhotoCropGesture = PetPhotoCropGesture()) -> PetPhotoCropGeometry? {
        guard let image else { return nil }
        let translation = change.translation
        return PetPhotoCropGeometry(
            imageSize: image.size, canvasSize: size, diameterFraction: diameterFraction,
            circleOffset: CGSize(width: circleOffset.width + (moveCircle ? translation.width : 0), height: circleOffset.height + (moveCircle ? translation.height : 0)),
            zoom: zoom * change.magnification,
            photoOffset: CGSize(width: photoOffset.width + (moveCircle ? 0 : translation.width), height: photoOffset.height + (moveCircle ? 0 : translation.height))
        )
    }

    private func commit(_ crop: PetPhotoCropGeometry) {
        zoom = crop.zoom
        photoOffset = crop.photoOffset
        circleOffset = crop.circleOffset
    }

    private func normalizeLayout() {
        if let crop = geometry(for: canvasSize) { commit(crop) }
    }

    private func apply() {
        guard let image, let crop = geometry(for: canvasSize, change: gestureChange) else { return }
        do {
            onApply(try PetPhotoCropRenderer.jpeg(image: image, sourceRect: crop.sourceRect))
        } catch {
            errorMessage = "사진을 조정하지 못했어요. 다시 시도하거나 다른 사진을 선택해주세요."
        }
    }
}
