import Foundation
import CoreGraphics

struct PetPhotoCropSource: Identifiable {
    let id: UUID
    let data: Data
}

struct PetPhotoCropGesture {
    var translation = CGSize.zero
    var magnification: CGFloat = 1

    mutating func update(translation: CGSize?, magnification: CGFloat?) {
        // Simultaneous gestures finish independently; nil is not a reset to the original photo.
        if let translation { self.translation = translation }
        if let magnification { self.magnification = magnification }
    }
}

// A gallery load is only a draft. Only an apply from the current draft can replace the upload.
struct PetPhotoSelectionState {
    private(set) var selectedData: Data?
    private(set) var pendingCrop: PetPhotoCropSource?
    private(set) var isLoading = false
    private var selectionID = UUID()

    mutating func begin(isSaving: Bool) -> UUID? {
        guard !isSaving else { return nil }
        selectionID = UUID()
        pendingCrop = nil
        isLoading = true
        return selectionID
    }

    mutating func finish(_ data: Data, selectionID: UUID, isSaving: Bool) -> Bool {
        guard self.selectionID == selectionID, !isSaving else { return false }
        pendingCrop = PetPhotoCropSource(id: selectionID, data: data)
        isLoading = false
        return true
    }

    mutating func fail(selectionID: UUID) -> Bool {
        guard self.selectionID == selectionID else { return false }
        isLoading = false
        return true
    }

    mutating func apply(_ data: Data, selectionID: UUID, isSaving: Bool) -> Bool {
        guard !isSaving, self.selectionID == selectionID, pendingCrop?.id == selectionID else { return false }
        selectedData = data
        cancel()
        return true
    }

    mutating func cancel() {
        selectionID = UUID()
        pendingCrop = nil
        isLoading = false
    }

    mutating func reset() { self = Self() }
}

struct PetPhotoCropGeometry {
    let cropRect: CGRect
    let imageFrame: CGRect
    let sourceRect: CGRect
    let zoom: CGFloat
    let circleOffset: CGSize
    let photoOffset: CGSize

    init?(imageSize: CGSize, canvasSize: CGSize, diameterFraction: CGFloat = 0.75, circleOffset: CGSize = .zero, zoom: CGFloat = 1, photoOffset: CGSize = .zero) {
        let values = [imageSize.width, imageSize.height, canvasSize.width, canvasSize.height, diameterFraction, circleOffset.width, circleOffset.height, zoom, photoOffset.width, photoOffset.height]
        guard values.allSatisfy(\.isFinite), imageSize.width > 0, imageSize.height > 0, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let diameter = min(canvasSize.width, canvasSize.height) * min(max(diameterFraction, 0.35), 0.9)
        let radius = diameter / 2
        let center = CGPoint(
            x: min(max(canvasSize.width / 2 + circleOffset.width, radius), canvasSize.width - radius),
            y: min(max(canvasSize.height / 2 + circleOffset.height, radius), canvasSize.height - radius)
        )
        cropRect = CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)
        self.circleOffset = CGSize(width: center.x - canvasSize.width / 2, height: center.y - canvasSize.height / 2)
        self.zoom = min(max(zoom, 1), 6)
        let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height) * self.zoom
        let displayed = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let centeredOrigin = CGPoint(x: (canvasSize.width - displayed.width) / 2, y: (canvasSize.height - displayed.height) / 2)
        // Clamp the photo against the circle, not against the screen, so the crop has no blank edge.
        let origin = CGPoint(
            x: min(max(centeredOrigin.x + photoOffset.width, cropRect.maxX - displayed.width), cropRect.minX),
            y: min(max(centeredOrigin.y + photoOffset.height, cropRect.maxY - displayed.height), cropRect.minY)
        )
        self.photoOffset = CGSize(width: origin.x - centeredOrigin.x, height: origin.y - centeredOrigin.y)
        imageFrame = CGRect(origin: origin, size: displayed)
        let side = min(diameter / scale, imageSize.width, imageSize.height)
        sourceRect = CGRect(
            x: min(max((cropRect.minX - origin.x) / scale, 0), imageSize.width - side),
            y: min(max((cropRect.minY - origin.y) / scale, 0), imageSize.height - side),
            width: side, height: side
        )
    }
}
