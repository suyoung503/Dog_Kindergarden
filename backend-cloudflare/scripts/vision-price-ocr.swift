import Foundation
import Vision
import AppKit

guard CommandLine.arguments.count > 1 else {
    fputs("usage: vision-price-ocr <image-path>\n", stderr)
    exit(2)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: url),
      let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data),
      let cgImage = bitmap.cgImage else {
    fputs("image decode failed\n", stderr)
    exit(3)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.recognitionLanguages = ["ko-KR", "en-US"]
request.minimumTextHeight = 0.008

do {
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
} catch {
    fputs("Vision OCR error: \(error)\n", stderr)
    exit(4)
}

for observation in (request.results ?? []).sorted(by: {
    if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.015 {
        return $0.boundingBox.midY > $1.boundingBox.midY
    }
    return $0.boundingBox.minX < $1.boundingBox.minX
}) {
    if let candidate = observation.topCandidates(1).first {
        print(candidate.string)
    }
}
