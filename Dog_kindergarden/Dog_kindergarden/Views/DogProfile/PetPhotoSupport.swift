import SwiftUI
import UIKit
import ImageIO
import CoreTransferable
import UniformTypeIdentifiers

enum PetPhotoPolicy {
    nonisolated static let maxOriginalByteCount = 50_000_000
    nonisolated static let maxUploadByteCount = 1_500_000
    nonisolated static let maxDimension = 1_600
}

enum PetPhotoNormalizationError: Error, Equatable {
    case originalTooLarge, invalidImage, encodingFailed
}

struct PetPhotoFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= PetPhotoPolicy.maxOriginalByteCount else { throw PetPhotoNormalizationError.originalTooLarge }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PetPhotoFile(url: copy)
        }
    }
}

enum PetPhotoNormalizer {
    nonisolated static func normalize(_ data: Data) throws -> Data {
        guard data.count <= PetPhotoPolicy.maxOriginalByteCount else { throw PetPhotoNormalizationError.originalTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw PetPhotoNormalizationError.invalidImage
        }
        return try downsample(source)
    }

    nonisolated static func normalize(fileURL: URL) throws -> Data {
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= PetPhotoPolicy.maxOriginalByteCount else { throw PetPhotoNormalizationError.originalTooLarge }
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw PetPhotoNormalizationError.invalidImage
        }
        return try downsample(source)
    }

    nonisolated private static func downsample(_ source: CGImageSource) throws -> Data {
        // Decode a bounded thumbnail, not the full HEIC/JPEG; also apply EXIF orientation.
        for dimension in [PetPhotoPolicy.maxDimension, 1200, 800] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension,
                kCGImageSourceShouldCacheImmediately: false,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw PetPhotoNormalizationError.invalidImage
            }
            let image = UIImage(cgImage: thumbnail)
            for quality in [0.85, 0.70, 0.55, 0.40] {
                // Re-encoding strips location and other original metadata.
                if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= PetPhotoPolicy.maxUploadByteCount { return jpeg }
            }
        }
        throw PetPhotoNormalizationError.encodingFailed
    }
}

enum PetPhotoURLResolver {
    static func resolve(_ raw: String?, baseURL: URL = APIEnvironment.apiBaseURL) -> URL? {
        guard let raw, let candidate = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
              let components = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              components.scheme == baseURL.scheme, components.host == baseURL.host, components.port == baseURL.port,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.path.range(of: #"^/api/(pets/[1-9][0-9]*/photo|reservations/[1-9][0-9]*/pet-photo)$"#, options: .regularExpression) != nil else { return nil }
        return candidate
    }
}

struct AuthenticatedPetImage: View {
    let value: String?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image("dog_c").resizable().scaledToFit() }
        }
        .task(id: value) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .apiSessionInvalidated)) { _ in image = nil }
    }

    private func load() async {
        image = nil
        guard let value else { return }
        if value.hasPrefix("data:image/"), let comma = value.firstIndex(of: ","),
           value[..<comma].contains(";base64"), let bytes = Data(base64Encoded: String(value[value.index(after: comma)...])) {
            image = UIImage(data: bytes)
            return
        }
        guard let url = PetPhotoURLResolver.resolve(value) else { return }
        var request = APITransport.request(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        do {
            let (bytes, _) = try await APITransport.data(for: request)
            try Task.checkCancellation()
            image = UIImage(data: bytes)
        } catch { image = nil }
    }
}
