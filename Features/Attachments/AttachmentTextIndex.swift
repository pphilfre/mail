import Foundation
import Vision
import ImageIO
import PDFKit
import CryptoKit

actor AttachmentTextIndex {
    static let shared = AttachmentTextIndex()
    func text(at url: URL, id: String) throws -> String {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard (values.fileSize ?? 0) <= 30 * 1024 * 1024 else { return "" }
        let revision = id + "|" + String(values.contentModificationDate?.timeIntervalSince1970 ?? 0) + "|" + String(values.fileSize ?? 0)
        let digest = SHA256.hash(data: Data(revision.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "AttachmentOCR")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cached = folder.appending(path: digest + ".txt")
        if let text = try? String(contentsOf: cached, encoding: .utf8) { return text }
        var result = ""
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
            for index in 0..<min(pdf.pageCount, 40) {
                try Task.checkCancellation()
                guard let page = pdf.page(at: index) else { continue }
                if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result += text + "\n"; continue }
                guard let ref = page.pageRef else { continue }
                let rect = ref.getBoxRect(.mediaBox)
                guard rect.width > 0, rect.height > 0 else { continue }
                let scale = min(1600 / rect.width, 1600 / rect.height)
                guard let context = CGContext(data: nil, width: max(1, Int(rect.width * scale)), height: max(1, Int(rect.height * scale)), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
                context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale))
                context.scaleBy(x: scale, y: scale); context.translateBy(x: -rect.minX, y: -rect.minY); context.drawPDFPage(ref)
                if let image = context.makeImage() { result += try recognize(image) + "\n" }
            }
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
            result = try recognize(image)
        }
        result = String(result.prefix(300_000))
        try result.write(to: cached, atomically: true, encoding: .utf8)
        return result
    }
    private func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
