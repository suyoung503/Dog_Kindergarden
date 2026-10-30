import Foundation
import CoreGraphics
import Testing
@testable import Dog_kindergarden
#if canImport(UIKit)
import UIKit
import ImageIO
import UniformTypeIdentifiers
#endif

@Suite("Pet photo crop geometry and selection")
struct PetPhotoCropTests {
    @Test("Landscape and portrait crops use the correct centered source pixels")
    func aspectRatios() throws {
        let landscape = try #require(PetPhotoCropGeometry(imageSize: CGSize(width: 800, height: 400), canvasSize: CGSize(width: 300, height: 400)))
        #expect(landscape.sourceRect == CGRect(x: 287.5, y: 87.5, width: 225, height: 225))
        let portrait = try #require(PetPhotoCropGeometry(imageSize: CGSize(width: 400, height: 800), canvasSize: CGSize(width: 300, height: 400)))
        #expect(portrait.sourceRect == CGRect(x: 50, y: 250, width: 300, height: 300))
    }

    @Test("Tiny photos stay within their pixels instead of producing an empty crop")
    func tinyPhoto() throws {
        let crop = try #require(PetPhotoCropGeometry(imageSize: CGSize(width: 8, height: 4), canvasSize: CGSize(width: 300, height: 400)))
        #expect(crop.sourceRect == CGRect(x: 2.875, y: 0.875, width: 2.25, height: 2.25))
    }

    @Test("Moving and resizing the circle or dragging a zoomed photo never exposes empty pixels")
    func boundaries() throws {
        for size in [CGSize(width: 800, height: 400), CGSize(width: 400, height: 800)] {
            for direction: CGFloat in [-1, 1] {
                let crop = try #require(PetPhotoCropGeometry(imageSize: size, canvasSize: CGSize(width: 300, height: 400), diameterFraction: 3, circleOffset: CGSize(width: direction * 10000, height: direction * 10000), zoom: 100, photoOffset: CGSize(width: -direction * 10000, height: direction * 10000)))
                #expect(crop.cropRect.width == 270)
                #expect(crop.cropRect.width == crop.cropRect.height)
                #expect(CGRect(x: 0, y: 0, width: 300, height: 400).contains(crop.cropRect))
                #expect(crop.sourceRect.minX >= -0.0001 && crop.sourceRect.minY >= -0.0001)
                #expect(crop.sourceRect.maxX <= size.width + 0.0001)
                #expect(crop.sourceRect.maxY <= size.height + 0.0001)
                #expect(abs(crop.sourceRect.width - crop.sourceRect.height) < 0.0001)
            }
        }
    }

    @Test("Zero and nonfinite layouts cannot be applied")
    func invalidLayout() {
        #expect(PetPhotoCropGeometry(imageSize: .zero, canvasSize: CGSize(width: 300, height: 400)) == nil)
        #expect(PetPhotoCropGeometry(imageSize: CGSize(width: 100, height: 100), canvasSize: .zero) == nil)
        #expect(PetPhotoCropGeometry(imageSize: CGSize(width: 100, height: 100), canvasSize: CGSize(width: 300, height: 400), zoom: .nan) == nil)
    }

    @Test("Only the checkmark replaces a previously applied photo; cancel keeps it")
    func applyAndCancel() throws {
        var selection = PetPhotoSelectionState()
        let result1 = selection.begin(isSaving: false)
        let first = try #require((result1))
        let result2 = selection.finish(Data([1]), selectionID: first, isSaving: false)
        #expect((result2))
        #expect(selection.selectedData == nil)
        let result3 = selection.apply(Data([2]), selectionID: first, isSaving: false)
        #expect((result3))
        let result4 = selection.begin(isSaving: false)
        let second = try #require((result4))
        let result5 = selection.finish(Data([3]), selectionID: second, isSaving: false)
        #expect((result5))
        #expect(selection.selectedData == Data([2]))
        selection.cancel()
        #expect(selection.selectedData == Data([2]))
        #expect(selection.pendingCrop == nil && !selection.isLoading)
        let result6 = selection.apply(Data([4]), selectionID: second, isSaving: false)
        #expect((!result6))
    }

    @Test("An earlier slow selection or a cancelled request cannot replace a later selection")
    func selectionRace() throws {
        var selection = PetPhotoSelectionState()
        let result7 = selection.begin(isSaving: false)
        let old = try #require((result7))
        let result8 = selection.begin(isSaving: false)
        let new = try #require((result8))
        let result9 = selection.finish(Data([1]), selectionID: old, isSaving: false)
        #expect((!result9))
        let result10 = selection.fail(selectionID: old)
        #expect((!result10))
        #expect(selection.isLoading)
        let result11 = selection.finish(Data([2]), selectionID: new, isSaving: false)
        #expect((result11))
        #expect(selection.pendingCrop?.data == Data([2]))
        selection.cancel()
        let result12 = selection.finish(Data([3]), selectionID: new, isSaving: false)
        #expect((!result12))
        #expect(selection.pendingCrop == nil)
    }

    @Test("Saving blocks selection, late loads, and applying a crop")
    func savingBlocksChanges() throws {
        var selection = PetPhotoSelectionState()
        let result13 = selection.begin(isSaving: true)
        #expect((result13 == nil))
        let result14 = selection.begin(isSaving: false)
        let id = try #require((result14))
        let result15 = selection.finish(Data([1]), selectionID: id, isSaving: true)
        #expect((!result15))
        #expect(selection.selectedData == nil && selection.pendingCrop == nil)
        let result16 = selection.finish(Data([1]), selectionID: id, isSaving: false)
        #expect((result16))
        let result17 = selection.apply(Data([2]), selectionID: id, isSaving: true)
        #expect((!result17))
        #expect(selection.selectedData == nil)
        selection.reset()
        #expect(selection.pendingCrop == nil && selection.selectedData == nil && !selection.isLoading)
    }

    #if canImport(UIKit)
    @Test("Applying a crop produces a square bounded JPEG even from a tiny image")
    func renderedJPEG() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 4), format: format).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        }
        let data = try PetPhotoCropRenderer.jpeg(image: image, sourceRect: CGRect(x: 2, y: 0, width: 4, height: 4))
        let result = try #require(UIImage(data: data))
        #expect(result.size == CGSize(width: 4, height: 4))
        #expect(data.count <= PetPhotoPolicy.maxUploadByteCount)
        #expect(data.starts(with: [0xff, 0xd8, 0xff]))
        #expect(throws: PetPhotoNormalizationError.invalidImage) {
            try PetPhotoCropRenderer.jpeg(image: image, sourceRect: .zero)
        }
        #expect(throws: PetPhotoNormalizationError.invalidImage) {
            try PetPhotoCropRenderer.jpeg(image: image, sourceRect: CGRect(x: 7, y: 0, width: 4, height: 4))
        }
    }

    @Test("EXIF rotation is normalized before computing crop coordinates")
    func exifRotation() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let raw = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(raw, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(image.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let normalized = try #require(UIImage(data: PetPhotoNormalizer.normalize(raw as Data)))
        #expect(normalized.size == CGSize(width: 80, height: 120))
        #expect(normalized.imageOrientation == .up)
        let crop = try #require(PetPhotoCropGeometry(imageSize: normalized.size, canvasSize: CGSize(width: 300, height: 400)))
        let result = try #require(UIImage(data: PetPhotoCropRenderer.jpeg(image: normalized, sourceRect: crop.sourceRect)))
        #expect(result.size.width == result.size.height && result.size.width > 0)
    }
    #endif
}
