import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Dog_kindergarden

@Suite("Pet photo visible pixels and uploaded selection")
@MainActor
struct PetPhotoPixelTests {
    @Test("Zoom and movement preview matches JPEG pixels and the selected upload")
    func previewAndUploadPixels() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
            UIColor.blue.setFill(); context.fill(CGRect(x: 200, y: 0, width: 200, height: 400))
        }
        let sourceData = try #require(source.jpegData(compressionQuality: 1))
        let normalized = try #require(UIImage(data: PetPhotoNormalizer.normalize(sourceData)))
        let canvasSize = CGSize(width: 300, height: 400)
        var gesture = PetPhotoCropGesture()
        gesture.update(translation: CGSize(width: -180, height: 0), magnification: 3)
        let crop = try #require(PetPhotoCropGeometry(imageSize: normalized.size, canvasSize: canvasSize, zoom: gesture.magnification, photoOffset: gesture.translation))
        let preview = ImageRenderer(content: ZStack {
            Color.black
            PetPhotoCropPreview(image: normalized, crop: crop)
        }.frame(width: canvasSize.width, height: canvasSize.height).clipped())
        preview.scale = 1
        // Render once into owned bitmap memory. A deferred uiImage provider can time out on
        // its first one-pixel draw while the simulator compiles its Metal pipeline.
        let previewBitmap = try #require(CGContext(
            data: nil, width: Int(canvasSize.width), height: Int(canvasSize.height),
            bitsPerComponent: 8, bytesPerRow: Int(canvasSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        preview.render(rasterizationScale: 1) { size, draw in
            #expect(size == canvasSize)
            draw(previewBitmap)
        }
        let visible = UIImage(cgImage: try #require(previewBitmap.makeImage()))
        // Pinch ends before the remaining dragging finger; its missing value must not mean zoom 1.
        gesture.update(translation: CGSize(width: -180, height: 0), magnification: nil)
        let appliedCrop = try #require(PetPhotoCropGeometry(imageSize: normalized.size, canvasSize: canvasSize, zoom: gesture.magnification, photoOffset: gesture.translation))
        #expect(appliedCrop.sourceRect == crop.sourceRect)
        let jpeg = try PetPhotoCropRenderer.jpeg(image: normalized, sourceRect: appliedCrop.sourceRect)
        let saved = try #require(UIImage(data: jpeg))
        #expect(saved.size.width < normalized.size.width)
        #expect(crop.sourceRect.minX > 200)
        for fraction in [0.2, 0.5, 0.8] {
            let shown = try pixel(visible, x: crop.cropRect.minX + crop.cropRect.width * fraction, y: crop.cropRect.midY)
            let stored = try pixel(saved, x: saved.size.width * fraction, y: saved.size.height / 2)
            #expect(shown.blue > 200 && shown.red < 30)
            #expect(stored.blue > 200 && stored.red < 30)
            #expect(abs(shown.blue - stored.blue) < 12)
        }
        var selection = PetPhotoSelectionState()
        let started = selection.begin(isSaving: false)
        let id = try #require(started)
        let loaded = selection.finish(sourceData, selectionID: id, isSaving: false)
        #expect(loaded)
        let applied = selection.apply(jpeg, selectionID: id, isSaving: false)
        #expect(applied)
        #expect(selection.selectedData == jpeg)
        #expect(selection.selectedData != sourceData)
    }

    @Test("Finished drag and empty end events retain the last visible combined gesture")
    func independentlyFinishedGestures() {
        var gesture = PetPhotoCropGesture()
        let offset = CGSize(width: 43, height: -21)
        gesture.update(translation: offset, magnification: 2)
        gesture.update(translation: nil, magnification: 3)
        gesture.update(translation: nil, magnification: nil)
        #expect(gesture.translation == offset)
        #expect(gesture.magnification == 3)
    }

    private func pixel(_ image: UIImage, x: CGFloat, y: CGFloat) throws -> (red: Int, blue: Int) {
        let cgImage = try #require(image.cgImage)
        var rgba = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: -floor(x), y: floor(y) + 1 - CGFloat(cgImage.height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return (Int(rgba[0]), Int(rgba[2]))
    }
}
