import Foundation
import Testing
import UIKit
@testable import Dog_kindergarden

@Suite("Private pet photo regressions")
struct PetPhotoTests {
    @Test("Photo resolution never sends credentials to another origin or endpoint")
    func privatePhotoResolution() {
        let base = URL(string: "https://example.com/api")!
        #expect(PetPhotoURLResolver.resolve("/api/pets/7/photo", baseURL: base)?.absoluteString == "https://example.com/api/pets/7/photo")
        #expect(PetPhotoURLResolver.resolve("https://example.com/api/pets/7/photo", baseURL: base) != nil)
        for value in ["https://other.example.com/api/pets/7/photo", "//other.example.com/api/pets/7/photo", "/api/users/7", "/api/pets/7/photo?token=secret", "https://example.com:444/api/pets/7/photo"] {
            #expect(PetPhotoURLResolver.resolve(value, baseURL: base) == nil)
        }
    }

    @Test("Large compressed originals are downsampled instead of rejected at 750KB")
    func largePhotoDownsampling() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1800))
        let image = renderer.image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
        }
        var original = try #require(image.jpegData(compressionQuality: 1))
        original.append(Data(repeating: 0, count: 6_000_000))
        let optimized = try PetPhotoNormalizer.normalize(original)
        let result = try #require(UIImage(data: optimized))
        #expect(optimized.count <= 1_500_000)
        #expect(max(result.size.width, result.size.height) <= 1600)
        #expect(optimized.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test("Originals above 50MB are refused before decoding")
    func originalLimit() {
        #expect(throws: PetPhotoNormalizationError.originalTooLarge) {
            try PetPhotoNormalizer.normalize(Data(repeating: 0, count: 50_000_001))
        }
    }

    @Test("File normalization rejects an oversized sparse file before loading pixels")
    func fileOriginalLimit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 50_000_001)
        try handle.close()
        #expect(throws: PetPhotoNormalizationError.originalTooLarge) { try PetPhotoNormalizer.normalize(fileURL: url) }
    }
}
