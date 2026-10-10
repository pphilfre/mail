import Foundation
import UniformTypeIdentifiers
import Vision
import ImageIO
import CoreML

struct AttachmentInspection: Sendable {
    let hash: String
    let type: SecurityFinding
    let qr: SecurityFinding
    let qrLinks: [String]
    let previewAllowed: Bool
}

enum AttachmentSecurity {
    static func detectedMIME(_ data: Data) -> String? {
        let b = Array(data.prefix(16))
        if b.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) { return "image/png" }
        if b.starts(with: [0xff, 0xd8, 0xff]) { return "image/jpeg" }
        if data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)) { return "image/gif" }
        if data.starts(with: Data("%PDF-".utf8)) { return "application/pdf" }
        if b.starts(with: [0x50, 0x4b, 0x03, 0x04]) || b.starts(with: [0x50, 0x4b, 0x05, 0x06]) { return "application/zip" }
        if b.starts(with: [0x4d, 0x5a]) { return "application/x-dosexec" }
        if b.starts(with: [0x7f, 0x45, 0x4c, 0x46]) { return "application/x-executable" }
        if b.starts(with: [0xcf, 0xfa, 0xed, 0xfe]) || b.starts(with: [0xfe, 0xed, 0xfa, 0xcf]) || b.starts(with: [0xce, 0xfa, 0xed, 0xfe]) { return "application/x-mach-binary" }
        if b.count >= 12, String(bytes: b[0..<4], encoding: .ascii) == "RIFF", String(bytes: b[8..<12], encoding: .ascii) == "WEBP" { return "image/webp" }
        return nil
    }
    static func inspect(_ data: Data, filename: String, declaredMIME: String) throws -> AttachmentInspection {
        guard data.count <= AttachmentCache.maximumBytes else { throw AttachmentError.tooLarge }
        let declared = declaredMIME.lowercased().components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
        let ext = (filename as NSString).pathExtension.lowercased()
        let expected = UTType(filenameExtension: ext)?.preferredMIMEType
        let detected = detectedMIME(data)
        let activeExtensions = ["html", "htm", "svg", "js", "exe", "com", "bat", "cmd", "sh", "ps1", "mobileconfig", "app", "ipa", "scr", "lnk", "url"]
        let active = activeExtensions.contains(ext) || ["application/x-dosexec", "application/x-executable", "application/x-mach-binary"].contains(detected ?? "")
        // ZIP signatures alone cannot identify OOXML contents. Keep these unknown, not mismatches.
        let zipContainer = detected == "application/zip" && ["docx", "xlsx", "pptx", "epub"].contains(ext)
        let mismatch = (expected != nil && declared != "application/octet-stream" && expected != declared) ||
            (!zipContainer && ((detected != nil && declared != "application/octet-stream" && detected != declared) ||
            (detected != nil && expected != nil && detected != expected)))
        let isText = ext == "txt" && declared == "text/plain" && String(data: data, encoding: .utf8) != nil && !data.contains(0) && detected == nil
        let consistent = !zipContainer && (detected != nil || isText) && !mismatch && !active
        let type = SecurityFinding(id: "type", title: "Attachment type", verdict: mismatch || active ? .concern : (consistent ? .checked : .unknown),
            explanation: "Declared \(declared); extension \(ext.isEmpty ? "missing" : ext); signature \(detected ?? "unrecognised"). " +
                (active ? "Executable or active content is blocked from preview." : mismatch ? "File type disagrees with its name or MIME declaration; preview is blocked." : consistent ? "Recognised type agrees with available metadata. This is not a malware scan." : "Contents are not fully identified; preview is blocked. Archives and Office containers need deeper analysis."),
            points: mismatch || active ? 30 : 0)
        var qrLinks: [String] = []
        let qr: SecurityFinding
        if detected?.hasPrefix("image/") == true {
            do {
                qrLinks = try QRCodeSecurity.payloads(data)
                qr = QRCodeSecurity.finding(qrLinks)
            } catch {
                qr = SecurityFinding(id: "qr", title: "QR codes", verdict: .unknown, explanation: "Vision could not inspect this image, or its dimensions exceeded the local limit. No QR verdict is available.")
            }
        } else {
            qr = SecurityFinding(id: "qr", title: "QR codes", verdict: .unknown, explanation: "QR analysis covers downloaded raster images and embedded data images only. PDF pages, archives and remote images are not inspected.")
        }
        return AttachmentInspection(hash: MailSecurityObservations.sha256(data), type: type, qr: qr, qrLinks: qrLinks,
            previewAllowed: consistent && (["application/pdf", "image/png", "image/jpeg", "image/gif", "image/webp"].contains(detected ?? "") || isText))
    }
}

enum QRCodeSecurity {
    static func payloads(_ data: Data) throws -> [String] {
        guard data.count <= AttachmentCache.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 20_000_000 else { throw AttachmentError.unavailable }
        var completed = false
        var lastError: Error?
        var seen = Set<Int>()
        // Retry supported older Vision decoders when a runtime returns no payload.
        // Every reported payload still comes from an actual Vision observation.
        for revision in [VNDetectBarcodesRequest.defaultRevision, VNDetectBarcodesRequestRevision2, VNDetectBarcodesRequestRevision1]
            where seen.insert(revision).inserted && VNDetectBarcodesRequest.supportedRevisions.contains(revision) {
            let request = VNDetectBarcodesRequest()
            request.revision = revision
            request.symbologies = [.qr]
            #if targetEnvironment(simulator)
            request.usesCPUOnly = true
            if let stages = try? request.supportedComputeStageDevices {
                for (stage, devices) in stages {
                    if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                        request.setComputeDevice(cpu, for: stage)
                    }
                }
            }
            #endif
            do {
                try VNImageRequestHandler(data: data, options: [:]).perform([request])
                completed = true
                let values = (request.results ?? []).compactMap(\.payloadStringValue)
                if !values.isEmpty { return values }
            } catch { lastError = error }
        }
        if !completed { throw lastError ?? AttachmentError.unavailable }
        return []
    }
    static func finding(_ payloads: [String]) -> SecurityFinding {
        let observations = MailSecurityObservations(html: "", text: payloads.joined(separator: "\n"))
        let concerns = observations.links.flatMap(\.concerns)
        return SecurityFinding(id: "qr", title: "QR codes", verdict: concerns.isEmpty ? .unknown : .concern,
            explanation: payloads.isEmpty ? "Vision found no QR payload in the inspected image. This does not exclude small, rotated, obscured or other-frame QR codes." : "Vision decoded \(payloads.count) QR payload(s). QR codes can hide phishing destinations; decoded links have not been opened or verified. " + concerns.joined(separator: "; "), points: concerns.isEmpty ? 0 : 15)
    }
    static func embeddedFinding(_ payloads: [String], imageCount: Int, failures: Int) -> SecurityFinding {
        let observed = finding(payloads)
        let coverage = imageCount == 0 ? "No supported embedded data images found. Remote and CID images have not been fetched or inspected." :
            failures > 0 ? "\(failures) embedded images could not be inspected; coverage is incomplete." :
            "Inspected \(imageCount) supported embedded data images. Remote and CID images remain uninspected."
        return SecurityFinding(id: "embedded-qr", title: "Embedded QR codes", verdict: observed.verdict,
            explanation: observed.explanation + " " + coverage, points: observed.points)
    }
    static func embeddedImages(_ html: String) -> [Data] {
        MailSecurityObservations.matches(#"(?i)\bsrc\s*=\s*["']data:image/(?:png|jpeg|gif|webp);base64,([^"']+)["']"#, in: html, group: 1)
            .prefix(12).compactMap { value in
                guard value.utf8.count <= 8_000_000 else { return nil }
                return Data(base64Encoded: value, options: .ignoreUnknownCharacters)
            }
    }
}
