import Foundation

/// Inspects only downloaded content. Network verification remains an explicit inspector action.
@MainActor extension AppRuntime {
    func inspectOpenedMail(_ message: MailMessage, attachments: [MailAttachment]) async {
        let fingerprint = MailSecurityContent.fingerprint(message, attachments: attachments)
        guard securityReports[message.id]?.fingerprint != fingerprint,
              !securityInspecting.contains(message.id) else { return }
        securityInspecting.insert(message.id)
        defer { securityInspecting.remove(message.id) }
        let headers = (try? repository?.securityHeaders(message.id)) ?? []
        let history = (try? repository?.senderSecurityHistory(for: message)) ?? []
        let sender = message.sender, replyTo = message.replyTo
        let html = message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let text = message.plainTextBody ?? message.snippet
        let cache = gmail?.attachmentCache ?? AttachmentCache()
        var attachmentFindings: [SecurityFinding] = []
        var attachmentQR: [String] = []
        for file in attachments {
            guard !Task.isCancelled else { return }
            if let inspection = try? await cache.inspect(file.cachedRelativePath, filename: file.filename, mimeType: file.mimeType) {
                attachmentFindings += [inspection.type, inspection.qr]
                attachmentQR += inspection.qrLinks
            } else {
                attachmentFindings.append(.init(id: file.id.uuidString, title: file.filename, verdict: .unknown, explanation: "Attachment contents are not downloaded or could not be inspected."))
            }
        }
        let qrFromAttachments = attachmentQR
        let work = Task.detached(priority: .utility) {
            var findings = MailAuthentication.findings(headers: headers)
                + SenderSecurity.findings(sender: sender, replyTo: replyTo, history: history)
            let images = QRCodeSecurity.embeddedImages(html)
            var values: [String] = [], failures = 0
            for data in images {
                try Task.checkCancellation()
                do { values += try QRCodeSecurity.payloads(data) } catch { failures += 1 }
            }
            findings.append(QRCodeSecurity.embeddedFinding(values, imageCount: images.count, failures: failures))
            let observations = MailSecurityObservations(html: html, text: text)
            let qr = MailSecurityObservations(html: "", text: (values + qrFromAttachments).joined(separator: "\n"))
            let known = Set(history.filter { !$0.spam }.map { SenderSecurity.domain($0.email) })
            let concerns = (observations.links + qr.links).flatMap { $0.concerns + SenderSecurity.domainConcerns($0.host.lowercased(), known: known) }
            findings.append(.init(id: "links", title: "Links and redirects", verdict: concerns.isEmpty ? .unknown : .concern,
                explanation: concerns.isEmpty ? "Cached links inspected; destinations have not been visited or verified." : Array(Set(concerns)).sorted().joined(separator: " "), points: concerns.isEmpty ? 0 : 20))
            return findings
        }
        do {
            let findings = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled, fingerprint == MailSecurityContent.fingerprint(message, attachments: attachments) else { return }
            let report = SecurityReport(findings: findings + attachmentFindings + [
                .init(id: "unscanned", title: "Malware coverage", verdict: .unknown, explanation: "No local antivirus engine is installed.")
            ])
            // A more complete inspector result may have arrived while automatic checks ran.
            if securityReports[message.id]?.fingerprint != fingerprint { securityReports[message.id] = (fingerprint, report) }
        } catch { }
    }
}
