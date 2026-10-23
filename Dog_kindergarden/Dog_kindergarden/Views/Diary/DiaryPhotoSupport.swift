import SwiftUI
import UIKit
import ImageIO
import CoreTransferable
import UniformTypeIdentifiers

enum DiaryPhotoPolicy {
    static let maxPhotoCount = 3
    static let maxOriginalByteCount = 5_000_000
    static let maxUploadByteCount = 1_500_000
    static let maxDimension: CGFloat = 1_600

    static func remainingSelectionCount(existingCount: Int, newSelectionCount: Int) -> Int {
        max(0, maxPhotoCount - max(0, existingCount) - max(0, newSelectionCount))
    }
}

enum DiaryPhotoURLResolver {
    static func resolve(_ rawValue: String?, baseURL: URL = APIEnvironment.apiBaseURL) -> URL? {
        guard let rawValue else { return nil }
        let raw = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }

        if raw.hasPrefix("/") {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.path = "/"
            components?.query = nil
            components?.fragment = nil
            guard let origin = components?.url else { return nil }
            return URL(string: raw, relativeTo: origin)?.absoluteURL
        }

        var directory = baseURL
        if !directory.absoluteString.hasSuffix("/") {
            directory.appendPathComponent("")
        }
        return URL(string: raw, relativeTo: directory)?.absoluteURL
    }
}

enum DiaryPhotoNormalizationError: Error, Equatable {
    case originalTooLarge
    case invalidImage
    case encodingFailed
    case normalizedImageTooLarge
}

struct DiaryPhotoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let copyURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return DiaryPhotoFile(url: copyURL)
        }
    }
}

enum DiaryPhotoNormalizer {
    static func normalize(_ originalData: Data) throws -> Data {
        guard originalData.count <= DiaryPhotoPolicy.maxOriginalByteCount else {
            throw DiaryPhotoNormalizationError.originalTooLarge
        }
        guard let source = CGImageSourceCreateWithData(originalData as CFData, nil) else {
            throw DiaryPhotoNormalizationError.invalidImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(DiaryPhotoPolicy.maxDimension),
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DiaryPhotoNormalizationError.invalidImage
        }
        let normalizedImage = UIImage(cgImage: thumbnail)

        for quality in stride(from: 0.82, through: 0.12, by: -0.10) {
            guard let jpeg = normalizedImage.jpegData(compressionQuality: quality) else {
                throw DiaryPhotoNormalizationError.encodingFailed
            }
            if jpeg.count <= DiaryPhotoPolicy.maxUploadByteCount {
                return jpeg
            }
        }
        throw DiaryPhotoNormalizationError.normalizedImageTooLarge
    }
}

struct AuthenticatedDiaryImage: View {
    let photo: DiaryPhoto
    var contentMode: ContentMode = .fill
    var onOpen: (() -> Void)?
    var actionLabel: String?

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var didFail = false
    @State private var retryCount = 0

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
                    .tint(placeholderColor)
                    .accessibilityLabel("알림장 사진 불러오는 중")
            } else if didFail {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: placeholderSize))
                    Text("다시 시도")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(placeholderColor)
            }
        }
        .task(id: "\(photo.id)-\(retryCount)") { await load() }
        .contentShape(Rectangle())
        .onTapGesture { activate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .modifier(OptionalAccessibilityAction(
            isEnabled: didFail || onOpen != nil,
            action: activate
        ))
    }

    private func load() async {
        guard let url = DiaryPhotoURLResolver.resolve(photo.url) else {
            isLoading = false
            return
        }

        isLoading = true
        didFail = false
        image = nil
        var request = APITransport.request(url: url)
        request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await APITransport.data(for: request)
            guard let loaded = UIImage(data: data) else {
                throw DiaryPhotoNormalizationError.invalidImage
            }
            image = loaded
        } catch is CancellationError {
            return
        } catch {
            didFail = true
        }
        isLoading = false
    }

    private var placeholderColor: Color {
        switch contentMode {
        case .fit: return .white.opacity(0.65)
        case .fill: return Color.brandOrange
        @unknown default: return Color.brandOrange
        }
    }

    private var placeholderSize: CGFloat {
        switch contentMode {
        case .fit: return 44
        case .fill: return 24
        @unknown default: return 24
        }
    }

    private var accessibilityText: String {
        if image != nil { return actionLabel ?? "알림장 사진" }
        return isLoading
            ? "알림장 사진 불러오는 중"
            : "알림장 사진을 불러오지 못함, 다시 시도"
    }

    private func activate() {
        if didFail {
            retryCount += 1
        } else if image != nil {
            onOpen?()
        }
    }
}

private struct OptionalAccessibilityAction: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityAction { action() }
        } else {
            content
        }
    }
}

struct DiaryPhotoGalleryView: View {
    let photos: [DiaryPhoto]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    AuthenticatedDiaryImage(photo: photo, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
                        .accessibilityLabel("알림장 사진 \(index + 1)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Text("\(selectedIndex + 1) / \(photos.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("사진 닫기")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
        }
        .onAppear {
            if !photos.indices.contains(selectedIndex) { selectedIndex = 0 }
        }
    }
}
